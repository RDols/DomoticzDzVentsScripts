
-- Config
local enableDebugPrint = true
local username = "your@email.com"
local password = "password"
local siteID = "0000000"

local function LogDebug(domoticz, log)
  if enableDebugPrint then
    print(string.format('dzRequestSolarInfo : %s', log))
  end
end


local function AddReportData(json, component)
  local id = tostring(component.id)
  if json.reportersData[id] then
    component.DayWh = json.reportersData[id].unscaledEnergy
  end
end


local function GetOptimizerData(json, component)
  if component.data and component.data.type == "POWER_BOX" then
    local optimizer = component.data
    AddReportData(json, optimizer)
    return optimizer
  end
end


local function GetStringData(json, info, component)
  if component.data and component.data.type == "STRING" then
    local powerstring = component.data
    AddReportData(json, powerstring)
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


local function GetInverterData(json, info, component)
  if component.data and (component.data.type == "INVERTER" or component.data.type == "INVERTER_3PHASE") then
    local inverter = component.data
    AddReportData(json, inverter)
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


local function RequestLogical(domoticz)
    
    local authorization = string.format("%s:%s", username, password)
    authorization = string.format("Basic %s", domoticz.utils.toBase64(authorization))

    local request = {}
    request.url = string.format("https://monitoring.solaredge.com/solaredge-apigw/api/sites/%s/layout/logical", siteID) 
    request.headers = { ['Authorization'] = authorization }
    request.method = 'GET'
    request.callback = 'ResponseLogical'

    domoticz.openURL(request)
end


local function UpdateDevice(domoticz, deviceType, device)
  device.Name = device.Name or device.name
  device.Name = string.gsub(device.Name, "Module", "Panel")

  if not domoticz.utils.deviceExists(device.Name) then
    LogDebug(domoticz, string.format('to monitor create an dummy device type="Electric (Instant+Counter) name="%s"', device.Name))
    return
  end

  local lastData = domoticz.data.LastData[device.Name]
  if lastData == nil then
    domoticz.data.LastData[device.Name] = {Watt = device.Watt, DayWh=device.DayWh}
    return
  end

  local lastWatt = lastData.Watt or 0
  local lastDayWh = lastData.DayWh or 0
  device.Watt = device.Watt or lastWatt
  device.DayWh = device.DayWh or lastDayWh

  if device.DayWh == lastDayWh and device.Watt == lastWatt then
    return -- No new data
  end

  if device.DayWh < lastDayWh  then
    lastDayWh = 0 -- Most likely a new day
  end

  local dzDevice = domoticz.devices(device.Name)
  local addWh = device.DayWh - lastDayWh
  local newWh = dzDevice.WhTotal + addWh

  if enableDebugPrint and (device.Name == "Panel 1.0.1" or device.Name == "Panel 1.0.4" or device.Name == "Inverter 1") then
    LogDebug(domoticz, string.format('----- %s "%s" ----------------------------------', deviceType, device.Name))

    LogDebug(domoticz, string.format('device.DayWh=%0.3f  lastDayWh=%0.3f  device.Watt=%0.3f  lastWatt=%0.3f', device.DayWh, lastDayWh, device.Watt, lastWatt))
    LogDebug(domoticz, string.format('device.DayWh - lastDayWh = addWh => %0.3f - %0.3f = %0.3f', device.DayWh, lastDayWh, addWh))
    LogDebug(domoticz, string.format('old.WhTotal + addWh = newWh => %0.3f + %0.3f = %0.3f', dzDevice.WhTotal, addWh, newWh))

    LogDebug(domoticz, string.format('OldTotal=%0.3f   DomoticzToday=%0.3f   lastDayWh=%0.3f   PanelToday=%0.3f   newWh=%0.3f', dzDevice.WhTotal, dzDevice.WhToday, lastDayWh, device.DayWh, newWh))

    LogDebug(domoticz, string.format('%s "%s" Today = %0.2f Wh   Now = %0.2f W', deviceType, device.Name, device.DayWh, device.Watt))
  end
  dzDevice.updateElectricity(device.Watt, newWh)

  domoticz.data.LastData[device.Name] = {Watt = device.Watt, DayWh=device.DayWh}
end


local function OnLogicalResponse(domoticz, item)
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
end


--[[ ======================================================================== ]]
local interface = {}
interface.active = true

interface.on = {}
interface.on.timer = {'every 5 minutes at civildaytime'}
interface.on.httpResponses = {'ResponseLogical', 'ResponseSystemData'}

interface.data = {}
interface.data.LastData = { initial = {} }

function interface.execute(domoticz, item)
    if (item.isTimer) then
      LogDebug(domoticz, "-=[ Start HTTP Request ]======================================")
      RequestLogical(domoticz)
    elseif (item.isHTTPResponse) then
      LogDebug(domoticz, "-=[ Start HTTP Response ]=====================================")
      if (item.ok) then
        if item.callback == "ResponseLogical" then
          OnLogicalResponse(domoticz, item)
        end
      else
        LogDebug(domoticz, string.format("Error in HTTP request. Error %d - %s", item.statusCode, item.statusText))
      end
    end

    LogDebug(domoticz, "-=[ End ]=====================================================")
end

return interface
