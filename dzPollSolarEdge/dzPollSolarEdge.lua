--------------------------------------------------------------------------------
-- Config
local enableDebugPrint = true
local ip = "192.168.2.122"
local port = 1502
local script = "/home/dols/effe/sunspec-status"
-- Also check trigger
-- check device names
--------------------------------------------------------------------------------
-- Enum of the csv fields
local timestamp = 1
local status = 2
local ac_power = 3
local dc_power = 4
local total_production = 5
local ac_voltage = 6
local ac_current = 7
local dc_voltage = 8
local dc_current = 9
local temperature = 10
local exported_energy_m1 = 11
local imported_energy_m1 = 12
local exported_energy_m2 = 13
local imported_energy_m2 = 14
--------------------------------------------------------------------------------
-- Status to string
local statusStringMap= {}
statusStringMap[0] = "Unknown"
statusStringMap[1] = "OFF"
statusStringMap[2] = "SLEEPING"
statusStringMap[3] = "STARTING"
statusStringMap[4] = "ON (MPPT)"
statusStringMap[5] = "THROTTLED"
statusStringMap[6] = "SHUTTING DOWN"
statusStringMap[7] = "FAULT"
statusStringMap[8] = "STANDBY"
--------------------------------------------------------------------------------
local function LogDebug(domoticz, log)
    if enableDebugPrint then
        print(string.format('dzPollSolarEdge : %s', log))
    end
end
--------------------------------------------------------------------------------
local function LogError(domoticz, log)
    print(string.format('dzPollSolarEdge : %s', log))
end
--------------------------------------------------------------------------------
return 
{
    --------------------------------------------------------------------------------
	active = true,
    --------------------------------------------------------------------------------

	on = 
	{
        devices = 
		{
		    'P1 kWh',
		},

		timer = 
		{
		    --'Every 1 minutes'
		}
	},
    --------------------------------------------------------------------------------
	data = {},
    --------------------------------------------------------------------------------
	execute = function(domoticz, triggeredItem)
        --LogDebug(domoticz, "--==[ Start ]==-----------------------------------")

        -- Execute perl script
        cmd = string.format("perl %s --numeric --meter=0 --port=%d %s", script, port, ip) 
        local f = io.popen(cmd, 'r')
        local result = f:read('*a')
        f:close()

        -- Convert CSV result line into array
        local fields = {}
        for value in result:gmatch('([^,]+)') do
            table.insert(fields, tonumber(value))
        end
        
        -- Update domoticz counters
        local deviceExists = domoticz.utils.deviceExists --Caching for speed
        if #fields > 10 then
            if deviceExists("SE ModBus Energy") then
                local dzDevice = domoticz.devices("SE ModBus Energy")
                dzDevice.updateElectricity(fields[ac_power], fields[total_production])
            end
            if deviceExists("SE ModBus Current AC") then
                local dzDevice = domoticz.devices("SE ModBus Current AC")
                dzDevice.updateCurrent(fields[ac_current])
    
            end
            if deviceExists("SE ModBus Current DC") then
                local dzDevice = domoticz.devices("SE ModBus Current DC")
                dzDevice.updateCurrent(fields[dc_current])
            end
            if deviceExists("SE ModBus Temperature") then
                local dzDevice = domoticz.devices("SE ModBus Temperature")
                dzDevice.updateTemperature(fields[temperature])
            end
            if deviceExists("SE ModBus Status") then
                local dzDevice = domoticz.devices("SE ModBus Status") -- Text sensor
                local statusId = fields[status]
                local statusString  = string.format("%d %s", statusId, statusStringMap[statusId])
                if dzDevice.text ~= statusString then
                    dzDevice.updateText(statusString)
                end
            end
            if deviceExists("P1 kWh") and deviceExists("Energy Consumed") then
                local dzDeviceP1 = domoticz.devices("P1 kWh")
                local dzDeviceHouseEnergy = domoticz.devices("Energy Consumed")

                local houseUsageWatt = dzDeviceP1.usage + fields[ac_power] - dzDeviceP1.usageDelivered
                local houseUsageKwh = dzDeviceP1.usage1 + dzDeviceP1.usage2 - dzDeviceP1.return1 - dzDeviceP1.return2 + fields[total_production]
                houseUsageKwh = math.max(houseUsageKwh, dzDeviceHouseEnergy.usage) -- Guarding rounding erros in the wrong direction

                dzDeviceHouseEnergy.updateElectricity(houseUsageWatt, houseUsageKwh)

                --LogDebug(domoticz, string.format("Usage1 %d  Usage2 %d  return1 %d  return2 %d  production %d", dzDeviceP1.usage1, dzDeviceP1.usage2, dzDeviceP1.return1, dzDeviceP1.return2, fields[total_production]))
                --LogDebug(domoticz, string.format("houseUsageKwh %d", houseUsageKwh))
            end
        else
            LogError(domoticz, "No valid response")
        end

        --LogDebug(domoticz, "--==[ End ]==-----------------------------------")
	end
}
