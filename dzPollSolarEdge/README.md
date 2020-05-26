# dzPollSolarEdge
dzVents script for Domoticz to poll modbus/tcp data from solaredge inverter. It can be triggered by the P1 port of your smart meter, Also can calculate the total energy you are using.

it uses Sunspec monitor perl script.
https://github.com/tjko/sunspec-monitor

## Status
2020-05-24 : Initial commit, work in progress
2020-05-26 : Refactored and added Energy Consumed

## Usage
1. Create an new dzVents script in Domoticz
2. Copy content of dzPollSolarEdge.lua into script
3. Modify config block
5. check the trigger, likely you need to change the P1 sensor
6. Check the name of the P1 matches you on line 116
4. Add virtual sensors:
  - SE ModBus Energy (Energy Instant+Counter)
  - SE ModBus Current AC (Ampere 1 phase)
  - SE ModBus Current DC (Ampere 1 phase)
  - SE ModBus Temperature (Temperature)
  - SE ModBus Status (Text)
  - Energy Consumed (Energy Instant+Counter)
 
