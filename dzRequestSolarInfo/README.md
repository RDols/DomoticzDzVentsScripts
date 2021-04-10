# dzRequestSolarInfo
dzVents script for Domoticz to request optimizer data from the SolarEdge website

## Status
2020-05-18 : Initial commit, only happy flow and hard configurations, one evening work...  
2020-05-21 : Fixed issue with updating the energy usage for day statistics. (not fully tested yet)  
2020-05-26 : Fixed issue with updating the energy usage for day statistics. (for real now)  
2021-04-10 : SolarEdge changed their interface. Fixed the changed names. But power (Watt) is not available anymore :(  

## Usage
1. Create an new dzVents script in Domoticz
2. Copy content of dzRequestSolarInfo.lua into script
3. Modify username, password and siteID on lines 5, 6 and 7
4. Add dummy devices for eacht optimizer and inverter type "Electric (instant+Counter)" Name is the name of optimizer or inverter  
5. When done, set "enableDebugPrint = false" on line 3
  
## Known Isuues
 - It needs domoticz V4.11543 or newer
