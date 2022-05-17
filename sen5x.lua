local sen5x = {}
local device_address = 0x69

sen5x.bus_id = 0

function sen5x.start()
	i2c.start(sen5x.bus_id)
	if not i2c.address(sen5x.bus_id, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(sen5x.bus_id, {0x00, 0x21})
	i2c.stop(sen5x.bus_id)
	return true
end

function sen5x.stop()
	i2c.start(sen5x.bus_id)
	if not i2c.address(sen5x.bus_id, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(sen5x.bus_id, {0x01, 0x04})
	i2c.stop(sen5x.bus_id)
	return true
end

function sen5x.read_value(data, index)
	local val = string.byte(data, index) * 256 + string.byte(data, index+1)
	if val == 0xffff or val == 0x7fff then
		val = nil
	end
	return val
end

function sen5x.prepare_read()
	i2c.start(sen5x.bus_id)
	if not i2c.address(sen5x.bus_id, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(sen5x.bus_id, {0x03, 0xc4})
	i2c.stop(sen5x.bus_id)
	return true
end

function sen5x.read()
	i2c.start(sen5x.bus_id)
	if not i2c.address(sen5x.bus_id, device_address, i2c.RECEIVER) then
		return false
	end
	local data = i2c.read(sen5x.bus_id, 24)
	i2c.stop(sen5x.bus_id)
	sen5x.pm1 = sen5x.read_value(data, 1)
	sen5x.pm2_5 = sen5x.read_value(data, 4)
	sen5x.pm4 = sen5x.read_value(data, 7)
	sen5x.pm10 = sen5x.read_value(data, 10)
	sen5x.humidity = sen5x.read_value(data, 13)
	sen5x.temperature = sen5x.read_value(data, 16)
	sen5x.voc = sen5x.read_value(data, 19)
	sen5x.nox = sen5x.read_value(data, 22)
	return true
end

function sen5x.prepare_get_product()
	i2c.start(sen5x.bus_id)
	if not i2c.address(sen5x.bus_id, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(sen5x.bus_id, {0xd0, 0x14})
	i2c.stop(sen5x.bus_id)
	return true
end

function sen5x.get_product()
	i2c.start(sen5x.bus_id)
	if not i2c.address(sen5x.bus_id, device_address, i2c.RECEIVER) then
		return nil
	end
	local data = i2c.read(sen5x.bus_id, 48)
	i2c.stop(sen5x.bus_id)
	local ret = ""
	ret = ret .. string.sub(data, 1, 2)
	ret = ret .. string.sub(data, 4, 5)
	ret = ret .. string.sub(data, 7, 7)
	return ret
end

return sen5x
