
-- Config
local enableDebugPrint = true
local isDecimalComma = true -- true for 1.000,00 :: false for 1,000.00
local username = "your@email.com"
local password = "password"
local siteID = "0000000"

-- Upvalues
local timezoneOffset = 0


local function LogDebug(domoticz, log)
  if enableDebugPrint then
    print(string.format('dzRequestSolarInfo : %s', log))
  end
end


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


local function AddReportData(json, component)
  local id = tostring(component.id)
  component.DayWh = 0
  if json.reportersData[id] then
    component.DayWh = json.reportersData[id].unscaledEnergy or 0
  end
end


local function AddReportInfo(json, component)
  local id = tostring(component.id)
  data = json.reportersInfo[id]
  component.Watt = 0
  if data then
    if data.lastMeasurement then
      -- Not always updated although there is new data
      -- unixtimestamp in mSec and LOCAL time
      component.LastMeasurement = (data.lastMeasurement / 1000) + timezoneOffset
    else
      component.LastMeasurement = 0
    end

    component.Name = data.name
    for k, v in pairs(data.localizedMeasurements or {}) do
      if string.match(k, "%[W%]") then
        component.Watt = MakeCleanNumber(v)
      end
    end
  end
end


local function GetOptimizerData(json, component)
  if component.data and component.data.type == "POWER_BOX" then
    local optimizer = component.data
    AddReportData(json, optimizer)
    AddReportInfo(json, optimizer)
    return optimizer
  end
end


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


local function RequestSolardEdge(domoticz)
    
    local authorization = string.format("%s:%s", username, password)
    authorization = string.format("Basic %s", domoticz.utils.toBase64(authorization))

    local request = {}
    request.url = string.format("https://monitoring.solaredge.com/solaredge-apigw/api/sites/%s/layout/logical", siteID) 
    request.headers = { ['Authorization'] = authorization }
    request.method = 'GET'
    request.callback = 'SolarEdgeWebResponse'

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
    LogDebug(domoticz, string.format('Last Update: %s', os.date('%Y-%m-%d %H:%M:%S', device.LastMeasurement)))

    LogDebug(domoticz, string.format('device.DayWh=%0.3f  lastDayWh=%0.3f  device.Watt=%0.3f  lastWatt=%0.3f', device.DayWh, lastDayWh, device.Watt, lastWatt))
    LogDebug(domoticz, string.format('device.DayWh - lastDayWh = addWh => %0.3f - %0.3f = %0.3f', device.DayWh, lastDayWh, addWh))
    LogDebug(domoticz, string.format('old.WhTotal + addWh = newWh => %0.3f + %0.3f = %0.3f', dzDevice.WhTotal, addWh, newWh))

    LogDebug(domoticz, string.format('OldTotal=%0.3f   DomoticzToday=%0.3f   lastDayWh=%0.3f   PanelToday=%0.3f   newWh=%0.3f', dzDevice.WhTotal, dzDevice.WhToday, lastDayWh, device.DayWh, newWh))

    LogDebug(domoticz, string.format('%s "%s" Today = %0.2f Wh   Now = %0.2f W', deviceType, device.Name, device.DayWh, device.Watt))
  end
  dzDevice.updateElectricity(device.Watt, newWh)

  domoticz.data.LastData[device.Name] = {Watt = device.Watt, DayWh=device.DayWh}
end


--[[----------------------------------------------------------------------------
Timestamps in the json are local times, not UTC.
Here we calculate the timezoneOffset upvalue.
It has a known bug. Arround the daylight saving switch it has an error of 1 hour
--]]
local function CalculateTimezone()
  timezoneOffset = os.time{year=1970, month=1, day=1, hour=0}
  local localTime = os.date("*t", os.time())
  if localTime.isdst then
    timezoneOffset = timezoneOffset - 3600
  end
end


local interface = {}
interface.active = true

interface.on = {}
interface.on.timer = {'every 1 minutes at civildaytime'}
interface.on.httpResponses = {'SolarEdgeWebResponse'}

interface.data = {}
interface.data.LastData = { initial = {} }

function interface.execute(domoticz, item)
    if (item.isTimer) then
      LogDebug(domoticz, "-=[ Start HTTP Request ]======================================")
      RequestSolardEdge(domoticz)
    elseif (item.isHTTPResponse) then
      LogDebug(domoticz, "-=[ Start HTTP Response ]=====================================")
      if (item.ok) then
        CalculateTimezone()

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

return interface
