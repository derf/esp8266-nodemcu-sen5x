station_cfg = {}
publishing_mqtt = false
publishing_http = false

watchdog = tmr.create()
push_timer = tmr.create()
chip_id = string.format("%06X", node.chipid())
device_id = "esp8266_" .. chip_id
mqtt_prefix = "sensor/" .. device_id
mqttclient = mqtt.Client(device_id, 120)

dofile("config.lua")

print("ESP8266 " .. chip_id)

ledpin = 4
gpio.mode(ledpin, gpio.OUTPUT)
gpio.write(ledpin, 0)

sen5x = require("sen5x")
i2c.setup(sen5x.bus_id, 2, 1, i2c.SLOW)

function log_restart()
	print("Network error " .. wifi.sta.status())
end

function setup_client()
	print("Connected")
	gpio.write(ledpin, 1)
	if not sen5x.start() then
		print("SEN5x initialization error")
	end
	publishing_mqtt = true
	mqttclient:publish(mqtt_prefix .. "/state", "online", 0, 1, function(client)
		publishing_mqtt = false
		push_timer:start()
		prepare_push_data()
	end)
end

function connect_mqtt()
	print("IP address: " .. wifi.sta.getip())
	print("Connecting to MQTT " .. mqtt_host)
	mqttclient:on("connect", prepare_hass_register)
	mqttclient:on("offline", log_restart)
	mqttclient:lwt(mqtt_prefix .. "/state", "offline", 0, 1)
	mqttclient:connect(mqtt_host)
end

function connect_wifi()
	print("WiFi MAC: " .. wifi.sta.getmac())
	print("Connecting to ESSID " .. station_cfg.ssid)
	wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, connect_mqtt)
	wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, log_restart)
	wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, log_restart)
	wifi.setmode(wifi.STATION)
	wifi.sta.config(station_cfg)
	wifi.sta.connect()
end

function prepare_push_data()
	if sen5x.prepare_read() == false then
		print("SEN5x error")
	else
		local delayed_read_data = tmr.create()
		delayed_read_data:register(20, tmr.ALARM_SINGLE, push_data)
		delayed_read_data:start()
	end
end

function push_data()
	if sen5x.read() == false then
		print("SEN5x error")
	else
		local json_str = "{"
		local influx_str = ""
		if sen5x.pm1 ~= nil then
			json_str = string.format('%s"pm1_ugm3":%d.%01d,', json_str, sen5x.pm1/10, sen5x.pm1%10)
			influx_str = string.format("%spm1_ugm3=%d.%01d,", influx_str, sen5x.pm1/10, sen5x.pm1%10)
		end
		if sen5x.pm2_5 ~= nil then
			json_str = string.format('%s"pm2_5_ugm3":%d.%01d,', json_str, sen5x.pm2_5/10, sen5x.pm2_5%10)
			influx_str = string.format("%spm2_5_ugm3=%d.%01d,", influx_str, sen5x.pm2_5/10, sen5x.pm2_5%10)
		end
		if sen5x.pm4 ~= nil then
			json_str = string.format('%s"pm4_ugm3":%d.%01d,', json_str, sen5x.pm4/10, sen5x.pm4%10)
			influx_str = string.format("%spm4_ugm3=%d.%01d,", influx_str, sen5x.pm4/10, sen5x.pm4%10)
		end
		if sen5x.pm10 ~= nil then
			json_str = string.format('%s"pm10_ugm3":%d.%01d,', json_str, sen5x.pm10/10, sen5x.pm10%10)
			influx_str = string.format("%spm10_ugm3=%d.%01d,", influx_str, sen5x.pm10/10, sen5x.pm10%10)
		end
		if sen5x.humidity ~= nil then
			json_str = string.format('%s"humidity_relpercent":%d.%01d,', json_str, sen5x.humidity/100, (sen5x.humidity%100)/10)
			influx_str = string.format("%shumidity_relpercent=%d.%01d,", influx_str, sen5x.humidity/100, (sen5x.humidity%100)/10)
		end
		if sen5x.temperature ~= nil then
			json_str = string.format('%s"temperature_celsius":%d.%01d,', json_str, sen5x.temperature/200, (sen5x.temperature%200)/20)
			influx_str = string.format("%stemperature_celsius=%d.%01d,", influx_str, sen5x.temperature/200, (sen5x.temperature%200)/20)
		end
		if sen5x.voc ~= nil then
			json_str = string.format('%s"voc":%d.%01d,', json_str, sen5x.voc/10, sen5x.voc%10)
			influx_str = string.format("%svoc=%d.%01d,", influx_str, sen5x.voc/10, sen5x.voc%10)
		end
		if sen5x.nox ~= nil then
			json_str = string.format('%s"nox":%d.%01d,', json_str, sen5x.nox/10, sen5x.nox%10)
			influx_str = string.format("%snox=%d.%01d,", influx_str, sen5x.nox/10, sen5x.nox%10)
		end
		json_str = string.format('%s"rssi_dbm":%d}', json_str, wifi.sta.getrssi())
		influx_str = string.format("%srssi_dbm=%d", influx_str, wifi.sta.getrssi())

		if not publishing_mqtt then
			watchdog:start(true)
			publishing_mqtt = true
			gpio.write(ledpin, 0)
			mqttclient:publish(mqtt_prefix .. "/data", json_str, 0, 0, function(client)
				publishing_mqtt = false
				if influx_url and influx_attr and influx_str then
					publish_influx(influx_str)
				else
					gpio.write(ledpin, 1)
					collectgarbage()
				end
			end)
		end
	end
end

function publish_influx(payload)
	if not publishing_http then
		publishing_http = true
		http.post(influx_url, influx_header, "sen5x" .. influx_attr .. " " .. payload, function(code, data)
			publishing_http = false
			gpio.write(ledpin, 1)
			collectgarbage()
		end)
	end
end

function prepare_hass_register()
	sen5x.prepare_get_product()
	local delayed_hass_register = tmr.create()
	delayed_hass_register:register(20, tmr.ALARM_SINGLE, hass_register)
	delayed_hass_register:start()
end

function hass_register()
	local product_name = sen5x.get_product()
	if product_name then
		print("Registering " .. product_name)
	else
		product_name = "SEN5x"
	end

	local hass_device = string.format('{"connections":[["mac","%s"]],"identifiers":["%s"],"model":"ESP8266 + %s","name":"%s %s","manufacturer":"derf"}', wifi.sta.getmac(), device_id, product_name, product_name, chip_id)
	local hass_entity_base = string.format('"device":%s,"state_topic":"%s/data","expire_after":120', hass_device, mqtt_prefix)
	local publish_queue = {}

	local hass_pm1 = string.format('{%s,"name":"PM1.0","object_id":"%s_pm1","unique_id":"%s_pm1","device_class":"pm1","unit_of_measurement":"µg/m³","value_template":"{{value_json.pm1_ugm3}}"}', hass_entity_base, device_id, device_id)
	table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/pm1/config", hass_pm1})

	local hass_pm2_5 = string.format('{%s,"name":"PM2.5","object_id":"%s_pm2_5","unique_id":"%s_pm2_5","device_class":"pm25","unit_of_measurement":"µg/m³","value_template":"{{value_json.pm2_5_ugm3}}"}', hass_entity_base, device_id, device_id)
	table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/pm2_5/config", hass_pm2_5})

	local hass_pm4 = string.format('{%s,"name":"PM4.0","object_id":"%s_pm4","unique_id":"%s_pm4","device_class":"pm25","unit_of_measurement":"µg/m³","value_template":"{{value_json.pm4_ugm3}}"}', hass_entity_base, device_id, device_id)
	table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/pm4/config", hass_pm4})

	local hass_pm10 = string.format('{%s,"name":"PM10","object_id":"%s_pm1*","unique_id":"%s_pm10","device_class":"pm10","unit_of_measurement":"µg/m³","value_template":"{{value_json.pm10_ugm3}}"}', hass_entity_base, device_id, device_id)
	table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/pm10/config", hass_pm10})

	if product_name ~= "SEN50" then
		local hass_temp = string.format('{%s,"name":"Temperature","object_id":"%s_temperature","unique_id":"%s_temperature","device_class":"temperature","unit_of_measurement":"°c","value_template":"{{value_json.temperature_celsius}}"}', hass_entity_base, device_id, device_id)
		table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/temperature/config", hass_temp})

		local hass_humi = string.format('{%s,"name":"Humidity","object_id":"%s_humidity","unique_id":"%s_humidity","device_class":"humidity","unit_of_measurement":"%%","value_template":"{{value_json.humidity_relpercent}}"}', hass_entity_base, device_id, device_id)
		table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/humidity/config", hass_humi})

		local hass_voc = string.format('{%s,"name":"VOC","object_id":"%s_voc","unique_id":"%s_voc","unit_of_measurement":"VOC","icon":"mdi:air-filter","value_template":"{{value_json.voc}}"}', hass_entity_base, device_id, device_id)
		table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/voc/config", hass_voc})
	end

	if product_name == "SEN55" then
		local hass_nox = string.format('{%s,"name":"NOx","object_id":"%s_nox","unique_id":"%s_nox","unit_of_measurement":"NOx","icon":"mdi:molecule","value_template":"{{value_json.nox}}"}', hass_entity_base, device_id, device_id)
		table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/nox/config", hass_nox})
	end

	local hass_rssi = string.format('{%s,"name":"RSSI","object_id":"%s_rssi","unique_id":"%s_rssi","device_class":"signal_strength","unit_of_measurement":"dBm","value_template":"{{value_json.rssi_dbm}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)
	table.insert(publish_queue, {"homeassistant/sensor/" .. device_id .. "/rssi/config", hass_rssi})

	hass_mqtt(publish_queue)
end

function hass_mqtt(queue)
	local table_n = table.getn(queue)
	if table_n > 0 then
		local topic = queue[table_n][1]
		local message = queue[table_n][2]
		table.remove(queue)
		mqttclient:publish(topic, message, 0, 1, function(client)
			hass_mqtt(queue)
		end)
	else
		collectgarbage()
		setup_client()
	end
end

watchdog:register(90 * 1000, tmr.ALARM_SEMI, node.restart)
push_timer:register(20 * 1000, tmr.ALARM_AUTO, prepare_push_data)
watchdog:start()

connect_wifi()
