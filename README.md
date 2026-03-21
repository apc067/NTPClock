# Nixie Tube Propeller Clock

This repo contains the firmware for the **world's first** propeller clock using a Nixie tube.

## Build

The firmware can be built in **MPLAB IDE v8.92**, using the provided MCP-file.

## Version History

* 1.2.0	-	Add initial FW & support for Control button
* 2.0.0	-	Implement significant improvements (setting, etc.)
* 2.0.2	-	Fix "ISR context switch may corrupt Z flag" bug
* 3.0.0	-	Implement POC sound generation & Chirpie tune
* 3.1.0	-	Re-architect display implementation
* 3.2.0	-	Implement button double-click to change music
* 3.3.0	-	Implement music infrastructure
* 3.4.0	-	Add music tunes & test sounds
* 3.4.1	-	Add AdvClock/PrintTime contention test
* 3.5.0	-	Clean up sound calculations & raise tune pitch
* 3.5.1	-	Redesign Index Hole handling
* 3.6.0	-	Finalize diagnostic GPIOs (Idle & PrintTime)
* 3.7.0	-	Protect PrintTime from erroneous printouts
* 3.7.1	-	Fully fix "ISR context switch may corrupt Z" bug
* 3.7.2	-	Fully eliminate spin-loop waiting for Index Hole
* 3.8.0	-	Implement major refactor of OutputBuffer handling
* 3.8.1	-	Implement minor Device Info improvements
* 3.9.0	-	Finalize diagnostic tunes
* 3.9.1	-	Define DDEBUG to stretch display timing 64-fold
* 3.9.2	-	Apply equation-based constant calculation results
* 3.9.3	-	Debug FW for Index Hole visibility measurements
* 3.9.4	-	Rename "side" to "field" & remove Index Hole DOE
* 3.9.5	-	Improve headings & remove runaway code detection
* 3.10.0	-	Implement identical treatment of display fields
* 3.10.1	-	Implement sound generation timing improvements
* 3.10.2	-	Fix "Single click can cause Dizzy condition" bug
* 3.11.0	-	Add new creative display mode "Magnetic Spin"
* 3.12.0	-	Add "Jet Set Willy" tune
* 3.12.1	-	Improve "Summary of Behaviors" comments
* 3.12.2	-	Rename "field" to "arc"
* 3.12.3	-	Improve exit from Device Info mode
* 3.13.0	-	Add "Woodycock" tune
* 3.14.0	-	Down-shift range of playable notes
* 3.14.1	-	Rename "Magnetic Spin" to "MagnetoSpin"
* 3.14.2	-	Implement geometry characterization debug flags
* 3.14.3	-	Adjust Parallax Correction
* 3.14.4	-	Improve Index Hole LED visibility counter reset
* 3.14.5	-	Issue minor comment improvements
* 3.14.6	-	Delay checking Control button status on boot
* 3.15.0	-	Add new stationary display modes
* 3.16.0	-	Add unconditional "splash screen" upon boot
* 3.17.0	-	Return Device Info to be Firmware Info again
* 3.17.1	-	Improve timing of printouts with suppressed zeroes

## Author Info

Email: apc067@gmail.com

Project link: https://www.nixiana.com/projects/ntpclock/
