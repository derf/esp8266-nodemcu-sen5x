local sen5x = {}
local device_address = 0x69

sen5x.status = "Initializing"

function sen5x.start()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(0, {0x00, 0x21})
	i2c.stop(0)
	return true
end

function sen5x.stop()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(0, {0x01, 0x04})
	i2c.stop(0)
	return true
end

function sen5x.read_value(data, index)
	local val = string.byte(data, index) * 256 + string.byte(data, index+1)
	if val == 0xffff or val == 0x7fff then
		val = nil
	elseif val > 0x7fff then
		val = val - 0x10000
	end
	return val
end

function sen5x.prepare_read()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(0, {0x03, 0xc4})
	i2c.stop(0)
	return true
end

function sen5x.read()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.RECEIVER) then
		return false
	end
	local data = i2c.read(0, 24)
	i2c.stop(0)
	if not sen5x.crc_valid(data, 24) then
		return false
	end
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

function sen5x.prepare_read_status()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(0, {0xd2, 0x06})
	i2c.stop(0)
	return true
end

function sen5x.read_status()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.RECEIVER) then
		return false
	end
	local data = i2c.read(0, 6)
	i2c.stop(0)
	if not sen5x.crc_valid(data, 6) then
		return false
	end
	local status1 = string.byte(data, 1)
	local status2 = string.byte(data, 5)

	if bit.isset(status1, 5) then
		sen5x.status = "Fan speed out of range"
	elseif bit.isset(status1, 3) then
		sen5x.status = "Fan cleaning active"
	elseif bit.isset(status2, 7) then
		sen5x.status = "Gas sensor error"
	elseif bit.isset(status2, 6) then
		sen5x.status = "RHT sensor error"
	elseif bit.isset(status2, 5) then
		sen5x.status = "Laser failure"
	elseif bit.isset(status2, 4) then
		sen5x.status = "Fan failure"
	else
		sen5x.status = "OK"
	end
	return true
end

function sen5x.prepare_get_product()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		return false
	end
	i2c.write(0, {0xd0, 0x14})
	i2c.stop(0)
	return true
end

function sen5x.get_product()
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.RECEIVER) then
		return nil
	end
	local data = i2c.read(0, 48)
	i2c.stop(0)
	if not sen5x.crc_valid(data, 48) then
		return false
	end
	local ret = ""
	ret = ret .. string.sub(data, 1, 2)
	ret = ret .. string.sub(data, 4, 5)
	ret = ret .. string.sub(data, 7, 7)
	return ret
end

function sen5x.crc_word(data, index)
	local crc = 0xff
	for i = index, index+1 do
		crc = bit.bxor(crc, string.byte(data, i))
		for j = 8, 1, -1 do
			if bit.isset(crc, 7) then
				crc = bit.bxor(bit.lshift(crc, 1), 0x31)
			else
				crc = bit.lshift(crc, 1)
			end
			crc = bit.band(crc, 0xff)
		end
	end
	return bit.band(crc, 0xff)
end

function sen5x.crc_valid(data, length)
	for i = 1, length, 3 do
		if sen5x.crc_word(data, i) ~= string.byte(data, i+2) then
			return false
		end
	end
	return true
end

return sen5x
