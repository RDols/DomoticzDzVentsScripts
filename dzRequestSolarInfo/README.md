# dzRequestSolarInfo
dzVents script for Domoticz to request optimizer data from the SolarEdge website

## Status
2020-05-18 : Initial commit, only happy flow and hard configurations, one evening work...  
2020-05-21 : fixed issue with updating the energy usage for day statistics. (not fully tested yet)  
2020-05-26 : Fixed issue with updating the energy usage for day statistics. (for real now)

## Usage
1. Create an new dzVents script in Domoticz
2. Copy content of dzRequestSolarInfo.lua into script
3. Modify username, password and siteID on lines 5, 6 and 7
4. If you use a "1,234.00" number format on the SolarEdge website, change line 3 to :  
  "isDecimalComma = false" on line 4
5. Add dummy devices for eacht optimizer and inverter type "Electric (instant+Counter)" Name is the name of optimizer or inverter  
6. When done, set "enableDebugPrint = false" on line 3
  
## Known Isuues
 - It needs domoticz V4.11543 or newer
