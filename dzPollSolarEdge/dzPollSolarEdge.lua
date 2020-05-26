--------------------------------------------------------------------------------
-- Config
local enableDebugPrint = true
local ip = "192.168.2.122"
local port = 1502
local script = "/home/dols/effe/sunspec-status"
-- Also check trigger
-- check device names
--------------------------------------------------------------------------------
-- Status to string
local statusStringMap = {"OFF", "SLEEPING", "STARTING", "ON (MPPT)", "THROTTLED", "SHUTTING DOWN", "FAULT", "STANDBY"}
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
local function GetDevice(domoticz, deviceName, dzDevice)
    if not domoticz.utils.deviceExists(deviceName) then
        return false
    end
    
    dzDevice.meter = domoticz.devices(deviceName)
    return true
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
        cmd = string.format("perl %s --debug --numeric --meter=0 --port=%d %s", script, port, ip) 
        local f = io.popen(cmd, 'r')
        local csv = {}
        for line in f:lines() do
            table.insert(csv, line)
        end
        f:close()
        
        if #csv < 2 then
            LogError(domoticz, "No valid response. Expected two lines.")
            return
        end

        --Parse header
        --timestamp,status,ac_power,dc_power,total_production,ac_voltage,ac_current,dc_voltage,dc_current,temperature,exported_energy_m1,imported_energy_m1,exported_energy_m2,imported_energy_m2
        local names = {}
        for value in csv[1]:gmatch('([^,]+)') do
            table.insert(names, value)
        end
        
        -- Convert CSV result line into table
        local solaredge = {}
        local fieldcount = 0
        for value in csv[2]:gmatch('([^,]+)') do
            fieldcount = fieldcount + 1
            solaredge[names[fieldcount]] = tonumber(value)
        end
        
        if fieldcount < 10 then
            LogError(domoticz, "No valid response. Expected 10 or more fields.")
            return
        end
        
        local dzDevice = {}
        if GetDevice(domoticz, "SE ModBus Energy", dzDevice) then
            dzDevice.meter.updateElectricity(solaredge.ac_power, solaredge.total_production)
        end

        if GetDevice(domoticz, "SE ModBus Current AC", dzDevice) then
            dzDevice.meter.updateCurrent(solaredge.ac_current)
        end

        if GetDevice(domoticz, "SE ModBus Current DC", dzDevice) then
            dzDevice.meter.updateCurrent(solaredge.dc_current)
        end
        
        if GetDevice(domoticz, "SE ModBus Temperature", dzDevice) then
            dzDevice.meter.updateTemperature(solaredge.temperature)
        end

        if GetDevice(domoticz, "SE ModBus Status", dzDevice) then
            local statusId = solaredge.status
            local statusString  = string.format("%d : %s", statusId, statusStringMap[statusId] or "Unknown")
            if dzDevice.meter.text ~= statusString then
                dzDevice.meter.updateText(statusString)
            end
        end
        
        if GetDevice(domoticz, "Energy Consumed", dzDevice) then
            P1 = domoticz.devices("P1 kWh")
            
            local houseUsageWatt = P1.usage + solaredge.ac_power - P1.usageDelivered
            local houseUsageKwh = P1.usage1 + P1.usage2 - P1.return1 - P1.return2 + solaredge.total_production
            houseUsageKwh = math.max(houseUsageKwh, dzDevice.meter.usage) -- Guarding rounding erros in the wrong direction
            dzDevice.meter.updateElectricity(houseUsageWatt, houseUsageKwh)
        end

        --LogDebug(domoticz, "--==[ End ]==-----------------------------------")
	end
}
