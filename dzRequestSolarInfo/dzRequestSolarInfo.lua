--------------------------------------------------------------------------------
--Config
local enableDebugPrint = true
local isDecimalComma = true -- true for 1.000,00 :: false for 1,000.00 
local username = "your@email.com"
local password = "password"
local siteID = "0000000"
--------------------------------------------------------------------------------
local function LogDebug(domoticz, log)
    if enableDebugPrint then
        print(string.format('dzRequestSolarInfo : %s', log))
    end
end
--------------------------------------------------------------------------------
local function MakeCleanNumber(dirtyNumber)
    if isDecimalComma then
        local value = dirtyNumber:gsub("%.", "")
        value = value:gsub(",", ".")
        return tonumber(value)
    else
        local value = dirtyNumber:gsub(",", "")
        return tonumber(value)
    end
end
--------------------------------------------------------------------------------
local function AddReportData(json, component)
    local id = tostring(component.id)
    component.DayEnergy = 0
    if json.reportersData[id] then
        component.DayEnergy = json.reportersData[id].unscaledEnergy or 0
    end
end
--------------------------------------------------------------------------------
local function AddReportInfo(json, component)
    local id = tostring(component.id)
    data = json.reportersInfo[id]
    component.CurrentPower = 0
    if data then
        --component.LastMeasurement = data.lastMeasurement --Not updated by website, useless
        component.Name = data.name
        for k, v in pairs(data.localizedMeasurements or {}) do
            if string.match(k, "%[W%]") then
                component.CurrentPower = MakeCleanNumber(v)
            end
        end
    end
end
--------------------------------------------------------------------------------
local function GetOptimizerData(json, component)
    if component.data and component.data.type == "POWER_BOX" then
        local optimizer = component.data
        AddReportData(json, optimizer)
        AddReportInfo(json, optimizer)
        return optimizer
    end
end
--------------------------------------------------------------------------------
local function GetStringData(json, info, component)
    if component.data and component.data.type == "STRING" then
        local powerstring = component.data
        AddReportData(json, powerstring)
        AddReportInfo(json, powerstring)
        powerstring.Optimizers = {}
        for _, child in pairs(component.children) do
            local optimizer = GetOptimizerData(json, child)
            if optimizer then
                table.insert(powerstring.Optimizers, optimizer)
                table.insert(info.Optimizers, optimizer)
            end
        end
        return powerstring
    end
end
--------------------------------------------------------------------------------
local function GetInverterData(json, info, component)
    if component.data and (component.data.type == "INVERTER" or component.data.type == "INVERTER_3PHASE") then
        local inverter = component.data
        AddReportData(json, inverter)
        AddReportInfo(json, inverter)
        inverter.Strings = {}
        for _, child in pairs(component.children) do
            local string = GetStringData(json, info, child)
            if string then
                table.insert(inverter.Strings, string)
                table.insert(info.Strings, string)
            end
        end
        return inverter
    end
end
--------------------------------------------------------------------------------
local function RequestSolardEdge(domoticz)
    
    local authorization = string.format("%s:%s", username, password)
    authorization = string.format("Basic %s", domoticz.utils.toBase64(authorization))

    local url = string.format("https://monitoring.solaredge.com/solaredge-apigw/api/sites/%s/layout/logical", siteID)
    local headers = { ['Authorization'] = authorization }
    
    domoticz.openURL(
    {
        url = url,
        method = 'GET',
        headers = headers,
        callback = 'SolarEdgeWebResponse'
    })
end
--------------------------------------------------------------------------------
local function UpdateDevice(domoticz, deviceType, device)
    LogDebug(domoticz, string.format('%s "%s" Energy = %0.2f Wh   Current Power = %0.2f W', deviceType, device.Name, device.DayEnergy, device.CurrentPower))
    if domoticz.utils.deviceExists(device.Name) then
        --local newTotalValue = domoticz.devices(device.Name).WhTotal - domoticz.devices(device.Name).WhToday + device.DayEnergy
        local newTotalValue = device.DayEnergy
        domoticz.devices(device.Name).updateElectricity(device.CurrentPower, newTotalValue)
    else
        LogDebug(domoticz, string.format('to monitor create an dummy device type="Electric (Instant+Counter) name="%s"', device.Name))
    end
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
return 
{
--------------------------------------------------------------------------------
	active = true,
--------------------------------------------------------------------------------
    on = 
	{
		timer = 
		{
		    'every 5 minutes at civildaytime' 
		},
	    httpResponses = 
	    { 
	        'SolarEdgeWebResponse' 
	    }
	},
--------------------------------------------------------------------------------
    data = 
	{
    },
--------------------------------------------------------------------------------
    execute = function(domoticz, item)
--------------------------------------------------------------------------------
        if (item.isTimer) then
            LogDebug(domoticz, "-=[ Start HTTP Request]=======================================")
            RequestSolardEdge(domoticz)
        elseif (item.isHTTPResponse) then
            LogDebug(domoticz, "-=[ Start HTTP Response ]=====================================")
            if (item.ok) then
                local info = { Inverters = {}, Strings = {}, Optimizers = {} }
                for _, child in pairs(item.json.logicalTree.children) do
                    local inverter = GetInverterData(item.json, info, child)
                    if inverter then
                        table.insert(info.Inverters, inverter)
                    end
                end
                
                for _, device in ipairs(info.Inverters) do
                    UpdateDevice(domoticz, "Inverter", device)
                end
                
                for _, device in ipairs(info.Strings) do
                    UpdateDevice(domoticz, "String", device)
                end
                
                for _, device in ipairs(info.Optimizers) do
                    UpdateDevice(domoticz, "Optimizer", device)
                end
            else
                LogDebug(domoticz, string.format("Error in HTTP request. Error %d - %s", item.statusCode, item.statusText))
            end
        end
  
        LogDebug(domoticz, "-=[ End ]=====================================================")
 	end
}
