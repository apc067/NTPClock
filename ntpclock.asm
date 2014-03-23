; ntpclock.asm
;
; NTPClock Firmware v3.9.3
; PIC16F84A Assembly Code for the World's First Nixie Tube Propeller Clock
;
; (C) Peter Csaszar - http://www.nixiana.com


;        1         2         3         4         5         6         7         8        
; 34567890123456789012345678901234567890123456789012345678901234567890123456789012345678
;
; Recommended tab spacing: 8


;***************************************************************************************
; Hardware configuration
;***************************************************************************************

; Option		Set to	 Bit	Value	INC-file EQU	uC default
;-----------------------------------------------------------------------------
; Code Protection	 Off	13-4	  1	 _CP_OFF	   Off
; Power On Timer	 On	  3 	  0	 _PWRTE_ON	   Off
; Watchdog Timer	 Off	  2	  0	 _WDT_OFF	   On
; Oscillator Type	 HS	 1-0	 10	 _HS_OSC	   RC


; I/O ports:
;
; PORTA 0 (O): Digit bit A (LSB)
; PORTA 1 (O): Digit bit B
; PORTA 2 (O): Digit bit C
; PORTA 3 (O): Digit bit D (MSB)
; PORTA 4 (O): Decimal point
;
; PORTB 0 (I): Index Hole input (active low)
; PORTB 1 (I): Control Button input (active low)
; PORTB 2 (O): In ISR output [diagnostics]
; PORTB 3 (I): 12/24-hour Selector input (low: 24h)
; PORTB 4 (O): Buzzer output
; PORTB 5 (I): <Unused>
; PORTB 6 (O): PrintTime output [diagnostics] / ICSP Clock
; PORTB 7 (O): Idle output [diagnostics] / ICSP Data


;***************************************************************************************
; Summary of Behaviors
;***************************************************************************************

; 1. Hour Notation
;    - 12-hour: "12/24h" Jumper off
;    - 24-hour: "12/24h" Jumper on
;
; 2. Display Mode
;    - Alternating:  vDspMod = 0 (Stationary display with alternating date/time sides)
;    - Left-Scroll:  vDspMod = 1
;    - Stand-Scroll: vDspMod = 2 (Quasi-stationary - for fun / to tune display timing)
;    - Right-Scroll: vDspMod = 3
;
; 3. Operating State
;    - Running: vSetPrt = 0
;    - Setting: vSetPtr = Non0
;
; 4. Different conditions
;    - Frozen Clock: vFlags2:bFROZEN = 1 (Waiting for button push to start clock)
;    - Device Info:  vFlags2:bDEVINF = 1 (Displaying device info instead of time)
;
; 5. Display behavior
;    - Stationary: Display position is stabilized using the Index Hole
;       - Display Mode = Alternating  -OR-
;       - Operating State = Setting   -OR-
;       - Frozen Clock Condition
;    - Scrolling: Not Stationary


;***************************************************************************************
; Environment directives
;***************************************************************************************

		processor 16f84a
		radix dec			; More convenient with constant calcs
		#include <p16f84a.inc>		; Microchip's uC-specific constants
		__config b'11111111110010'	; Config data embedded in the ASM source


;***************************************************************************************
; Definitions
;***************************************************************************************

;==== Debug Control ====================================================================

DDEBUG		equ	0			; Display Debug (stretch time by 64)


;==== Constants ========================================================================

; Customization constants

cVSCRL		equ	4			; Display scroll speed [rev/min]
cLNGTM		equ	750			; Long Button Press min time [ms]
cDBLTM		equ	200			; Double Click depress max time [ms]
cDRMUL		equ	1			; Note duration multiplier {1}			
cPDMUL		equ	3			; Buzzer pitch divider multiplier {2}

; Sentinel constants

cNUMMOD		equ	4			; Number of different display modes
cNUMMUS		equ	5			; Number of different music options

; Time Magnifier (for DEBUG reasons)

cMAGCNT		equ	64			; Stretch time to 0.5 sec/digit

; System constants

cFCLK		equ	19660800		; Clock freq (cycles per second) [cc/s]
cVSPIN		equ	360			; Carousel rotation speed [rev/min]
cCCPIC		equ	4			; Clock cycles per instr cycle [cc/ic]
cPTPREV		equ	2000			; Points per revolution [point/rev]
cSDPREV		equ	2			; Display sides per revolution [sd/rev]

; Geometrical constants

cRMIN		equ	50			; Innermost digit from center [mm]
cRAVG		equ	54			; Middle digit from center [mm]
cDIGWID		equ	8			; Digit width [mm]

; Timing configuration & adjustment constants

cTCKCOR		equ	0			; Seconds per 1 leap second (0: unused)
cTMRPSC		equ	256			; Timer0 prescaler (Also see {#}!)
cTMRCNT		equ	256			; Timer0 required count (Just max out)

; Calculated system constants (Note: tick = Timer0 interrupt)

cTMRRLD		equ	256-cTMRCNT		; Timer0 reload value (Now unused!)
cICPS		equ	cFCLK/cCCPIC		; Instruction cycles per sec [ic/s]

cITRPPT		equ	54			; Loop iters per point [iter/point] {2}

cSCRGAP		equ	cPTPREV*cVSCRL/cVSPIN	; Angle gap causing scroll [point]
cDIGWAN		equ	50			; Max angle of digit width [point]
						; = arctan(cDIGWID/(2*cRMIN))*cPTPREV/PI
cTMRDIV		equ	cTMRPSC*cTMRCNT		; Total timer divider
cTCKPS		equ	cICPS/cTMRDIV		; Ticks per sec [tick/s]
cLNGTCK		equ	cLNGTM*cTCKPS/1000	; Long Button Event min time [tick]
cDBLTCK		equ	cDBLTM*cTCKPS/1000	; Double Click depress max time [tick]

		if	cTCKPS*cTMRDIV!=cICPS
		messg	"*** WARNING! Timer tick period is not a divisor of 1 second!
		endif

; Point delay constants for display layout [point]

cDIGLTP		equ	10			; Digit Light-Up Pause
cDIGWP		equ	cDIGWAN			; Digit Width Pause
cDIGIT		equ	cDIGLTP+cDIGWP		; Total Digit width
cIDP		equ	15			; Inter-Digit Pause
cHDIGP		equ	cDIGIT/2		; Half Digit Pause
cNUMBER		equ	2*cDIGIT+cIDP		; Total Number width
cINP		equ	42			; Inter-Number Pause
cSTRING		equ	3*cNUMBER+2*cINP	; Total String width
cPRESP		equ	(cPTPREV/2-cSTRING)/2	; Pre-String Pause
cPSP		equ	cSCRGAP			; Post-Side Pause
cPOSTSP		equ	cPRESP-cPSP		; Post-String Pause
cREVCOR		equ	27			; Revolution Correction {3}
cPRXCOR		equ	80			; Index Hole Parallax Correction {4}
 		
 		if	cPRESP>255 		; Check the value of cPRESP {5}
		error 	"*** ERROR! Pre-String Pause value doesn't fit into a byte"
		endif

; Notes:
;
; {1} Note duration multiplier: Determines how many display sides [the atomic duration
; of note generation] make up a 1/16 note [the shortest note that can be played], and
; thus the Beats Per Minute value of the played music (90 @ cDRMUL=2, 180 @ cDRMUL=1)
;
; {2} The PtDelay Inner Loop Iterations Per Point (IterPerPoint, a.k.a. cITRPPT), the
; Pitch Divider Multiplier (PitchDivMul, a.k.a. cPDMUL) and the individual Pitch
; Dividers (PitchDiv) are determined throught the following equations:
;
;    ICPerIter = 6 + 7 / IterPerPoint + ( 4 + 3 / PitchDiv ) / PitchDivMul    (1)
;    IterPerPoint = IC_PER_SEC / ( POINT_PER_SEC * ICPerIter )                (2)
;    f(PitchDiv) = IC_PER_SEC / ( 2 * PitchDivMul * PitchDiv * ICPerIter )    (3)
;    f(256) >~ 390                                                            (4)
;
; The constants in (1) represent instruction cycles of loop execution in PtDelay;
; Intruction Cycles Per Second (IC_PER_SEC, a.k.a. cICPS) and Points Per Second
; (POINT_PER_SEC) are known values. Equation (4) states that the lowest frequency
; that can be played should be around 390 Hz or slightly higher (due to the buzzer's
; properties).
;
; All values except ICPerIter are integers. IterPerPoint should be smaller than its
; ideal value, so that Revolution Correction (see {3}) becomes positive as desired.
; Technically speaking, IterPerPoint is also a function of PitchDiv. However, by
; putting the PitchDivMul counting "at a lower order" than the PitchDiv counting, a
; much higher execution time stability is achieved, and IterPerPoint remains the same
; across the PitchDivider values of all reasonable frequencies.
;
; {3} The final Idle delay within a full display cycle, which is a "shim" factor to
; synchronize the angular speed of display generation to the angular speed of the
; carousel as much as possible. It accounts for the truncation error of the cITRPPT
; value, as well as for all the instruction cycles not spent in the Idle-code (which
; works the opposite way than the previous factor). It is tuned by finding the value,
; where the Stand-Scrolling display is the closest to stationary. Despite all these
; efforts, achieving a quasi-stationary display this way is virtually impossible, and it
; may also be affected by temperature and other factors. Therefore, for the stationary
; display of the Alternating Mode, position syncronization is done using the "Index
; Hole" IR LED/photodiode pair recycled from the original floppy drive. However,
; fine-tuning the display synchronity will maximize the correctness of the specified
; display scroll angular speed (cVSCRL) for the scrolling display modes.
;
; {4} Correction factor compensating for the fact that while the "Index Hole" IR LED is
; positioned such that it perfectly lines up with the photodiode when the longer edge of
; the rotating circuit board is parallel to the front of the floppy drive [the starting
; position of display generation], the photodiode begins to "see" the IR LED even before
; perfect alignment. It is tuned by finding the value, where the middle of the display
; sections in Alternating Mode line up with the middle of the floppy drive.
;
; {5} The Pre-String Pause is the longest delay during display generation. If its value
; fits into a byte [so that PtDelay's implementation can be simpler], everything else
; does too. However, this value IS dangerously close to the byte limit, therefore the
; different display layout delays need to be picked carefully.

; Character-related constants

cSPACE		equ	15			; SPACE character

bDP		equ	4			; Decimal Point attribute's bit#
bSUPZ		equ	5			; Suppress If Zero attrubute's bit#
bFLASH		equ	6			; Flashing attribute's bit#

cDPMSK		equ	1<<bDP			; Decimal Point attribute's bit mask
cDIGMSK		equ	cDPMSK-1		; Digit mask (excl. attributes)
cSUPMSK		equ	1<<bSUPZ		; Suppress If Zero attribute's bit mask
cXDMSK		equ	(1<<bFLASH)-1		; Extended digit mask (incl. attributes)

bFSHBIT		equ	2			; Flashing Char Counter's desired bit
cFSHON		equ	1<<bFSHBIT		; Initial value of above to turn char on

; vFlags bit constants

bBUTST		equ	0			; Button State flag's bit#
bSHORTB		equ	1			; Short Button Event flag's bit#
bLONGB		equ	2			; Long Button Event flag's bit#
bDBLCLK		equ	3			; Double Click flag's bit#
bCANSHT		equ	4			; Cancel Short Button Event flag's bit#

; vFlags2 bit constants

bSDCNT		equ	0			; Side Count flag's bit#
cSDMSK		equ	1<<bSDCNT		; Side Count flag's bit mask
bFROZEN		equ	1			; Frozen Clock Condition flag's bit#
bDEVINF		equ	2			; Device Info Condition flag's bit#
bQUIDLE		equ	3			; Idx Hole Should Quit Idle flag's bit#
bSAWIDX		equ	4			; Saw Idx Hole During Quidle flag's bit#

; I/O port bit constants

bINDEXH		equ	0			; Index Hole input's bit# (PORTB)
bBUTTON		equ	1			; Control Button input's bit# (PORTB)
bINISR		equ	2			; In ISR output's bit# (PORTB)
b1224H		equ	3			; 12/24-hr Selector input's bit# (PORTB)
bBUZZER		equ	4			; Buzzer output's bit# (PORTB)
cBZMSK		equ	1<<bBUZZER		; Buzzer output's bit mask
bPRINTM		equ	6			; PrintTime output's bit#
bIDLE		equ	7			; Idle output's bit#

; Music-related constants

cDRWID		equ	3			; # of Dur ID bits in ND (Also see {$}!)
cDRMSK		equ	(1<<cDRWID)-1		; Duration ID mask in Note Descriptor
cPCHMSK		equ	(~cDRMSK&0xFF)>>cDRWID	; Pitch ID mask in Note D. [after shift]
cISTUNE		equ	2			; Music ID of the first tune
cISSMOO		equ	3			; Music ID of the first smooth tune
cATST		equ	cNUMMUS-2		; Last-1 music option: A-Note Test
cPCHTST		equ	cNUMMUS-1		; Last music option: Pitch Test
cBPM		equ	cVSPIN*cSDPREV/cDRMUL/4	; Beats Per Minute [1/4 notes/min]

; Tune definition formalism

; --- Pitch ID's ('s' = sharp [#])

A4		equ	0			; The lowest note
As4		equ	1
Bb4		equ	1			; Equal temperament for max efficiency
B4		equ	2

C5		equ	3			; Octave 5
Cs5		equ	4
Db5		equ	4
D5		equ	5
Ds5		equ	6
Eb5		equ	6
E5		equ	7
F5		equ	8
Fs5		equ	9
Gb5		equ	9
G5		equ	10
Gs5		equ	11
Ab5		equ	11
A5		equ	12
As5		equ	13
Bb5		equ	13
B5		equ	14

C6		equ	15			; Octave 6
Cs6		equ	16
Db6		equ	16
D6		equ	17
Ds6		equ	18
Eb6		equ	18
E6		equ	19
F6		equ	20
Fs6		equ	21
Gb6		equ	21
G6		equ	22
Gs6		equ	23
Ab6		equ	23
A6		equ	24
As6		equ	25
Bb6		equ	25
B6		equ	26

C7		equ	27			; Octave 7 (partial)
Cs7		equ	28
Db7		equ	28
D7		equ	29
Ds7		equ	30
Eb7		equ	30

Pse		equ	31			; Pause

; --- Duration (value) ID's

V1_16		equ	0			; 1/16
V1_8		equ	1			; 1/8
V3_16		equ	2			; 3/16
V1_4		equ	3			; 1/4
V3_8		equ	4			; 3/8
V1_2		equ	5			; 1/2
V3_4		equ	6			; 3/4
V1		equ	7			; 1

; --- End of Tune marker

ENDTUNE		equ	255			; Replacing the 1-long pause

; --- Note definition shorthand for the Note Descriptor
;
; Structure of the Note Descriptor:
;
; Bits: 7 6 5 4 3        - Pitch ID
;                 2 1 0  - Duration ID

#define	N(pch,dr)	(pch<<cDRWID | dr)	; Cram Pitch ID & Duration ID in 1 byte


;==== Variables ========================================================================

; Fundamental system variables

vDspMod		equ	0x0C			; Display Mode
vSetPtr		equ	0x0D			; Pointer to Clock variable being set
vFlags		equ	0x0E			; System flags
vFlags2		equ	0x0F			; System flags #2

; Notes:
;
; vDspMod: Determines the Display Mode ("Mode" for short)
;
;   0 - Alternating, 1 - Left-Scroll, 2 - Stand-Scroll, 3 - Right-Scroll
;
; vSetPtr: Determines the Operating State ("State" for short)
;
;   0 - Running State, Non0 - Setting State [address of clock variable being set]
;
; vFlags:
;
;   Bits: 7 6 5 4 3 2 1 0
;         - - - X D L S B
;
;         B (0): Button State flag (1 = pressed)
;         S (1): Short Button Event flag
;         L (2): Long Button Event flag
;         D (3): Double Click flag
;         X (4): Cancel Short Button Event flag
;
; vFlags2:
;
;   Bits: 7 6 5 4 3 2 1 0
;         - - - I Q N F S
;
;         S (0): Side Count flag [1-bit side counter: 0-front, 1-back]
;         F (1): Frozen Clock Condition flag
;         N (2): Device Info Condition flag
;         Q (3): Index Hole Should Quit Idle ("Quidle") flag
;         I (4): Saw Index Hole During Quidle flag

; Clock Memory (In display order)
;
; CUSTOMIZATION: Change the order of variables to reflect display preferences (updating
; the variable addresses to retain the increasing order from 0x10 to 0x15, of course).

pClkMem		equ	0x10			; Pointer to the start of Clock Memory

vHour		equ	0x10			; Hour (00..23)
vMin		equ	0x11			; Minute (00..59)
vSec		equ	0x12			; Second (00..59)	
vMonth		equ	0x13			; Month (1..12)
vDay		equ	0x14			; Day (1..)
vYear		equ	0x15			; Year (00..99) [CurrYear-2000]

; Temporary registers for the Interrupt Handler

vWTmp		equ 	0x16			; Temporary W
vStsTmp		equ	0x17			; Temporary STATUS
vFsrTmp		equ	0x18			; Temporary FSR

; Display-related variables

vClkPtr		equ	0x1A			; Current Clock Memory pointer
vDspPtr		equ	0x1B			; Current Display Buffer pointer
vCurNum		equ	0x1C			; Number to be printed in PrintNum
vCurTen		equ	0x1D			; Number divided by 10 in PrintNum
vFshCtr		equ	0x1E			; Flashing Char Counter

; Notes:
;
; vFshCtr is a [typically] free-running counter incremented in every display cycle,
; whose bit selected by bFSHBIT is the base to turn a flashing character on & off.
; Bit=0: Character on, Bit=1: Character off
;
; vCurNum is also used as a generic loop countdown

; Display Buffer (12 bytes)

pDspBuf		equ	0x20			; Pointer to the start of Display Buffer

; Pointers to the different sections within the Display Buffer

pDspHr		equ	pDspBuf+(vHour-pClkMem)*2
pDspMin		equ	pDspBuf+(vMin-pClkMem)*2
pDspSec		equ	pDspBuf+(vSec-pClkMem)*2
pDspMon		equ	pDspBuf+(vMonth-pClkMem)*2
pDspDay		equ	pDspBuf+(vDay-pClkMem)*2
pDspYr		equ	pDspBuf+(vYear-pClkMem)*2

; Notes:
;
; Total length: 12 bytes
;
; Contents: Front - <Digit1> ... <Digit6>
;           Back  - <Digit1> ... <Digit6>
;
; Interpretation of the content of Digit<n>:
;
; Bits: 7 6 5 4 3 2 1 0
;       - F S D <-num->
;
;             F: Flashing attribute bit
;             S: Suppress If Zero attribute bit
;             D: Decimal Point attribute bit
;       <-num->:    0-9: Number to be displayed
;                cSPACE: Space

; Misc. system variables

vSecTck		equ	0x30			; Second Tick Counter (1 byte!)
vCorTck		equ	0x31			; Second Tick Correction Counter
vButTck		equ	0x32			; Button Hold Tick Counter (1 byte!)
vItrCtr		equ	0x33			; Loop iter ctr for 1 point (PI/1000)
vMagCtr		equ	0x34			; Time Magnifier Counter (for debug)
vPntCtr		equ	0x35			; Delay Counter [point]
vGenCtr		equ	0x36			; Generic loop counter

; Music-related variables

vMsType		equ	0x37			; Music Type (0=Silence, 1=Time-chirp)
vCrpPtr		equ	0x38			; Chirp Pointer (Along Display Buffer)
vTnPtr		equ	0x39			; Tune Pointer (Along current tune LUT)
vNoteDr		equ	0x40			; Current note's [remaining] duration
vBzCtr		equ	0x41			; Buzzer Half-Cycle Counter [iter]
vBzWid		equ	0x42			; Buzzer half-cycle width [iter]
vPDMCtr		equ	0x43			; Buzzer Pitch Div Multiplier Counter

; Music types:
;
;   0 - Silence
;   1 - Chirpie (Play sounds according to the display's contents)
;   2 - Manic Miner game jingle
;   3 - Jet Set Willie game jingle
;   4 - Woodycock (Anonymous)
;   5 - Shimmy (from Imre Kálmán: Die Bajadere)


;***************************************************************************************
; Macros
;***************************************************************************************

;==== 1. Our generic macro library =====================================================

		#include "MyPICMacros.inc"	; Useful macro collection for PIC chips


;==== 2. Other =========================================================================

;---- Streamline point delay generation ------------------------------------------------

; Parameters: Literal: Amount of point delay (0...255)
;
; Operation: PtDelay(Lit)

Point		macro	mcLit
		movlw	mcLit
		call	PtDelay
		endm


;***************************************************************************************
; The Code!
;***************************************************************************************

;==== Initial matters ==================================================================

;---- Reset jump address (0) -----------------------------------------------------------

		org	0
		goto	Start			; Jump to start
		data	'N','i','x'		; "Nix" for Nixie (For fun!)

;---- Interrupt jump address (4) -------------------------------------------------------

		goto	IntHdl			; Jump to the handler


;==== Lookup tables ====================================================================

; Note: Calculated GOTO table must not span a 256-word boundary, so these subroutines
; are better be kept here at the beginning of the code!

;---- Days Per Month lookup table

; Input:  W = Days Per Month Lookup Table offset
; Output: W = Number of days in month + 1

DayLut		addwf	PCL,F 			; Add offset to PC for computed GOTO
						; Non-leap year
		retlw	32			;   January: 31
		retlw	29			;   February: 28
		retlw	32			;   March: 31
		retlw	31			;   April: 30
		retlw	32			;   May: 31
		retlw	31			;   June: 30
		retlw	32			;   July: 31
		retlw	32			;   August: 31
		retlw	31			;   September: 30
		retlw	32			;   October:31
		retlw	31			;   November: 30
		retlw	32			;   December: 31
						; Leap year
		retlw	32			;   January: 31
		retlw	30			;   February: 29
		retlw	32			;   March: 31
		retlw	31			;   April: 30
		retlw	32			;   May: 31
		retlw	31			;   June: 30
		retlw	32			;   July: 31
		retlw	32			;   August: 31
		retlw	31			;   September: 30
		retlw	32			;   October:31
		retlw	31			;   November: 30
		retlw	32			;   December: 31
		
;---- Chirpie digit to note Pitch ID lookup table

; Input:  W = Digit value
; Output: W = Note Pitch ID

DigPitchIDLut	addwf	PCL,F 			; Add offset to PC for computed GOTO
		retlw	C5			; Digit 0
		retlw	D5			; Digit 1
		retlw	E5			; Digit 2
		retlw	G5			; Digit 3
		retlw	A5			; Digit 4
		retlw	C6			; Digit 5
		retlw	D6			; Digit 6
		retlw	E6			; Digit 7
		retlw	G6			; Digit 8
		retlw	A6			; Digit 9

;---- Note Pitch ID to pitch divider lookup table {2}

; Input:  W = Pitch ID
; Output: W = Pitch divider

NotePitchLut	addwf	PCL,F 			; Add offset to PC for computed GOTO
		retlw	249			; A4
		retlw	235			; A#4
		retlw	222			; B4
		retlw	210			; C5
		retlw	198			; C#5
		retlw	187			; D5
		retlw	176			; D#5
		retlw	166			; E5
		retlw	157			; F5
		retlw	148			; F#5
		retlw	140			; G5
		retlw	132			; G#5
		retlw	125			; A5
		retlw	118			; A#5
		retlw	111			; B5
		retlw	105			; C6
		retlw	99			; C#6
		retlw	93			; D6
		retlw	88			; D#6
		retlw	83			; E6
		retlw	78			; F6
		retlw	74			; F#6
		retlw	70			; G6
		retlw	66			; G#6
		retlw	62			; A6
		retlw	59			; A#6
		retlw	55			; B6
		retlw	52			; C7
		retlw	49			; C#7
		retlw	47			; D7
		retlw	44			; D#7
		retlw	0			; Pause (not used as a divide-by-256)

;---- Note Duration ID to duration count lookup table

; Input:  W = Duration ID
; Output: W = Duration count [sd]

NoteDuratnLut	addwf	PCL,F 			; Add offset to PC for computed GOTO
		retlw	1*cDRMUL		; 1/16
		retlw	2*cDRMUL		; 1/8
		retlw	3*cDRMUL		; 3/16
		retlw	4*cDRMUL		; 1/4
		retlw	6*cDRMUL		; 3/8
		retlw	8*cDRMUL		; 1/2
		retlw	12*cDRMUL		; 3/4
		retlw	16*cDRMUL		; 1

;---- Manic Miner tune lookup table

; Input:  W = Tune Pointer [tune note index]
; Output: W = Note Descriptor of corresponding note

ManicTuneLut	addwf	PCL,F 			; Add offset to PC for computed GOTO
		retlw	N(E5,V1_8)
		retlw	N(Fs5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_4)
		retlw	N(C6,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(C6,V1_4)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_4)

		retlw	N(E5,V1_8)
		retlw	N(Fs5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_4)
		retlw	N(C6,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(C6,V1_4)
		retlw	N(B5,V1_2)

		retlw	N(E5,V1_8)
		retlw	N(Fs5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_4)
		retlw	N(C6,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(C6,V1_4)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_4)

		retlw	N(E5,V1_8)
		retlw	N(Fs5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(A5,V1_8)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_8)
		retlw	N(E6,V1_8)
		retlw	N(B5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(E5,V1_8)
		retlw	N(Gs5,V1_8)
		retlw	N(B5,V1_2)
		retlw	ENDTUNE

;---- A-Note Test "tune" lookup table

; Input:  W = Tune Pointer [tune note index]
; Output: W = Note Descriptor of corresponding note

ATestTuneLut	addwf	PCL,F 			; Add offset to PC for computed GOTO
		retlw	N(A4,V1)
		retlw	N(A4,V1)
		retlw	N(A4,V1)
		retlw	N(A4,V1)
		retlw	N(A4,V1)
		retlw	N(A4,V1)
		retlw	N(A5,V1)
		retlw	N(A5,V1)
		retlw	N(A5,V1)
		retlw	N(A5,V1)
		retlw	N(A5,V1)
		retlw	N(A5,V1)
		retlw	N(A6,V1)
		retlw	N(A6,V1)
		retlw	N(A6,V1)
		retlw	N(A6,V1)
		retlw	N(A6,V1)
		retlw	N(A6,V1)
		retlw	ENDTUNE


;==== Main code ========================================================================

; HW configuration errands

Start		Movlf	cSPACE,PORTA		; Blank the Nixie
		clrf	PORTB			; Clear [those few outputs of] Port B
		
		bsf	STATUS,RP0		; SWITCH TO BANK 1
		errorlevel -302			; Disable msg 302 ("Not in bank 0")
		clrf	TRISA			; PortA: All output
		Movlf	b'00101011',TRISB	; PortB: Bit 2, 4, 6 & 7: I; Rest: O
		bcf	OPTION_REG,NOT_RBPU	; Turn on PortB's weak pullups
		bcf	OPTION_REG,PSA		; Prescaler assigned to Timer0
		bsf	OPTION_REG,PS2		; Prescaler: 1:256
		bsf	OPTION_REG,PS1		; {#} Must be in sync w/ cTMRPSC!
		bsf	OPTION_REG,PS0
		bcf	OPTION_REG,T0CS		; Start Timer0
		errorlevel +302			; Re-enable msg 302 ("Not in bank 0")
		bcf	STATUS,RP0		; Switch back to Bank 0

		Movlf	cTMRRLD,TMR0		; Load Timer0 (Super-nitpicky ;-) )

; Initialize variables

		clrf	vSetPtr			; Operating State = Running
		clrf	vFlags			; Reset all flags
		clrf	vFlags2
		Movlf	cTCKPS,vSecTck		; Load the Second Tick Counter
		Movlf	cTCKCOR,vCorTck		; Load the Tick Correction
		clrf	vButTck			; Clear the Button Hold Tick Counter
		clrf	vBzCtr			; Clear the Buzzer Half-Cycle Counter
		Movlf	cPDMUL,vPDMCtr		; Load the Pitch Div Multiplier Counter
		clrf	vMsType			; Music Type = Silence
		Movlf	pDspBuf,vCrpPtr		; Initialize the Chirp Pointer
		clrf	vTnPtr			; Reset the Tune Pointer

		Jset	PORTB,bBUTTON,NormBoot	; Button is not pressed - normal boot
		
; The "hijacked" main program to show device info until next button press

		call	PreloadDevInf		; Preload Clock memory w/ device info
		Movlf	3,vDspMod		; Display Mode = Right-Scroll
		bsf	vFlags2,bDEVINF		; Indicate the Device Info Condition
		
; Device Info Loop (Borrow the bSHORTB flag)

DevInfLoop	Jset	vFlags,bSHORTB,OrigRls	; Original button already released?
		skipclr	PORTB,bBUTTON		; Nope! Button is still being pressed?
		bsf	vFlags,bSHORTB		; Nope! Indicate first release
		goto	DoneOrig		; End of "original button still pressed"
OrigRls		Jclr	PORTB,bBUTTON,QuitLoop	; New button pressed - get ready to quit
DoneOrig	call	PrintTime		; Device info -> Display Buffer
		call	OutputBuff		; Display Buffer -> Nixie
		goto	DevInfLoop		; Device Info Loop iteration done
QuitLoop	Jclr	PORTB,bBUTTON,QuitLoop	; New button still being pressed - stay
		bcf	vFlags2,bDEVINF		; Cancel the Device Info Condition
		Point	10			; Short delay to kill any button bounce

; Normal boot

NormBoot	call	PreloadClk		; Preload Clock Memory w/ a bogus time
		Movlf	1,vDspMod		; Display Mode = Left-Scroll
		clrf	vFshCtr			; Reset the Flashing Character Counter
		bsf	vFlags2,bFROZEN		; Freeze the clock [it became "Dizzy"]
		bsf	INTCON,GIE		; Enable Global Interrupts  
		bsf	INTCON,T0IE		; Enable the Timer0 Interrupt

; The Main Loop

MainLoop	call	PrintTime		; Time Memory -> Display Buffer
		call	OutputBuff		; Display Buffer -> Nixie
		goto	MainLoop		; Main Loop iteration done

; Note: In this very simple case, there is no need to hook up the detection of the Index
; Hole [i.e., the passing of the IR LED under the photodiode] to an interrupt.


;==== Main code subroutines ============================================================

;---- Utilities ------------------------------------------------------------------------
		
;------ Preload the Clock Memory with a bogus time

PreloadClk	Movlf	23,vHour
		Movlf	59,vMin
		Movlf	50,vSec
		Movlf	12,vMonth
		Movlf	31,vDay
		Movlf	99,vYear
		return

	
;------ Preload the Clock Memory with device into

PreloadDevInf	Movlf	3,vHour			; Firmware version# [major.minor.subminor]
		Movlf	9,vMin
		Movlf	3,vSec
		Movlf	1,vMonth		; Required minimum hardware version#
		Movlf	3,vDay
		Movlf	0,vYear
		return

	
;------ Determine the display's behavior

; Output: Z=0 (NZ): Not Scrolling, Z=1 (Z): Scrolling

IsScroll	tst	vDspMod			; Display Mode = Alternating?
		Jz	NoScroll		; Yepp! Not Scrolling
		tst	vSetPtr			; Operation State = Setting?
		Retnz				; Yepp! Not Scrolling
		skipclr	vFlags2,bFROZEN		; Clock is in Frozen Condition?
NoScroll	bcf	STATUS,Z		; Yepp! Not Scrolling
		return				; Nope! Scrolling


;---- Display --------------------------------------------------------------------------

;------ Infamy #1: Print the contents of the Clock Memory into the Display Buffer

PrintTime	incf	vFshCtr,F		; Increment the Flashing Chr Counter
; 1. Print the contents
		Movlf	pClkMem,vClkPtr		; From: Clock Memory
		Movlf	pDspBuf,vDspPtr		; To: Display Buffer
		Movlf	6,vGenCtr		; Initialize the loop countdown
		bcf	INTCON,T0IE		; Disable the Timer0 Interrupt
; *** Start of critical section for Clock Memory access
		bsf	PORTB,bPRINTM		; Set the PrintTime diagnostic bit
PrintLoop	call	PrintNum		; Print the value
		Djnz	vGenCtr,PrintLoop	; Loop until done
		bcf	PORTB,bPRINTM		; Clear the PrintTime diagnostic bit
		
		clrf	vYear
		
; *** End of critical section for Clock Memory access
		bsf	INTCON,T0IE		; Enable the Timer0 Interrupt

; 2 Remaining chores
		bsf	pDspHr+1,bDP		; Decimal point after hours
		bsf	pDspMin+1,bDP		; Decimal point after minutes
		Jclr	vFlags2,bDEVINF,NoDev	; 1. Device Info Condition
		bsf	pDspBuf,bSUPZ		; FW major value leading 0 suppressed
		bsf	pDspBuf+2,bSUPZ		; FW minor value leading 0 suppressed
		bsf	pDspBuf+4,bSUPZ		; FW subminor value leading 0 suppressed
		bsf	pDspBuf+6,bSUPZ		; HW major value leading 0 suppressed
		bsf	pDspBuf+8,bSUPZ		; HW minor value leading 0 suppressed
		bsf	pDspBuf+10,bSUPZ	; HW subminor value leading 0 suppressed
		goto	DonePT			; Done with Device Info printout
NoDev		bsf	pDspMon,bSUPZ		; Month value leading 0 suppressed
		bsf	pDspDay,bSUPZ		; Day  value leading 0 suppressed
		Jclr	PORTB,b1224H,DonePT	; 2. The 12-hour notation
		bsf	pDspHr,bSUPZ		; Hour value leading 0 suppressed
		Cmpfl	vHour,12		; Hour<12 (i.e., AM)?
		Jlt	DonePT			; Yepp! Do not flash the decimal points
		Jset	vFshCtr,bFSHBIT,DonePT	; Flashing bit set: DP's ON this time
		bcf	pDspHr+1,bDP		; Turn off decimal point after hours
		bcf	pDspMin+1,bDP		; Turn off decimal point after minutes
DonePT		return


;------ Print number into the Display Buffer

; Input:  vClkPtr = Current position in the Clock Memory to read from
;         vDspPtr = Current position in the Display Buffer to write into
; Output: vClkPtr & vDspPtr point to the next position

PrintNum	Movff	vClkPtr,FSR		; Load the number
		Movff	INDF,vCurNum		; Save the number
		Cmpfl	vClkPtr,vHour		; Hours are being printed?
		Jnz	H24			; Nope! Don't worry about 12/24h
		Jclr	PORTB,b1224H,H24	; 12-hour notation selected?
		movlw	12			; Yepp! Preload 12 to W
		tst	vCurNum			; Hour=0?
		Jnz	NonZero			; Nope! Move on
		addwf	vCurNum,F		; Make 12 out of 0
		goto	H24			; Done!
NonZero		cmpfw	vCurNum			; Compare hour to 12
		Jz	H24			; =12: No hour adjustment needed
		Jlt	H24			; <12: No hour adjustment needed
		movlw	12			; Reload 12 to W
		subwf	vCurNum,F		; Subtract 12 from hour value
H24		clrf	vCurTen			; Reset the # of tens
		movlw	10			; Prepare to divide by 10
TenLoop		subwf	vCurNum,F
		Jnc	DoneDiv			; No longer positive -> quit loop
		incf	vCurTen,F
		goto	TenLoop
DoneDiv		addwf	vCurNum,F		; Tens->vCurTen, Ones->vCurNum
		call	PrintDig		; Print the tens
		Movff	vCurNum,vCurTen		; Prepare ones for printing
		call	PrintDig		; Print the ones
		incf	vClkPtr,F		; Next clock variable, please!
		return


;------ Print digit into the Display Buffer

; Input:  vCurTen = Digit to print
;         vDspPtr = Current position in the Display Buffer to write into
; Output: vDspPtr points to the next position

; Terminology note: The clock is DIZZY after quitting the Setting State, in which the
; seconds have been changed, therefore the clock is in Frozen condition. A single button
; press snaps the clock out of dizziness, and a brand new full second is started.

PrintDig	Movff	vDspPtr,FSR
		Movff	vCurTen,INDF		; *vDspPtr = vCurTen
		incf	vDspPtr,F		; Advance pointer in the Display Buffer
		Cmpff	vClkPtr,vSetPtr		; Current clock variable being set?
		skipnz				; Nope! Do not make digit flash
		bsf	INDF,bFLASH		; Yepp! Make digit flash
		tst	vSetPtr			; Determine if Dizzy - In Setting State?
		Retnz				; Yepp! Definitely not Dizzy
		skipclr	vFlags2,bFROZEN		; Not Frozen -> not Dizzy either!
		bsf	INDF,bFLASH		; Dizzy -> make digit flash
		return


;------ Infamy #2: Output the Display Buffer's content to the Nixie

OutputBuff	call	OutputSide		; Output one side
		call	OutputSide		; Output the other side
		return


;------ Output Side (& play the selected music)

; Input:  vDspPtr = Beginning of current side in the Display Buffer
; Output: vDspPtr points to the position beyond current side
;
; Note: Also plays the selected tune [or Chirpie]

OutputSide	call	SoundMusic		; Sound that music for the side		
		Movlf	pDspBuf,vDspPtr		; Display Buffer pointer to time
		clrf	vCurNum			; Assume time desired (borrow vCurNum)
		tst	vSetPtr			; Setting State?
		Jz	NoSet			; Nope! Regular clock operation
		Cmpfl	vSetPtr,pClkMem+3	; Yepp! Date is being set?
		Jlt	TimeSd0			; Nope! Keep time on Side 0
		goto	DateSd0			; Yepp! Put date to Side 0
NoSet		Jset	vFlags2,bFROZEN,TimeSd0	; No set: Time on 0 if 1) clock Frozen
		tst	vDspMod			; 2) display is not Alternating
		Jnz	TimeSd0			; Keep time on Side 0
		incf	vSec,W			; Increment: put 59->00 transit to front
		andlw	0x02			; Find the appropriate bit
		Jz	TimeSd0			; 3) desired 2-second interval is on
DateSd0		comf	vCurNum,F		; Desired output is date
TimeSd0		skipclr	vFlags2,bSDCNT		; Outputting Side 0?
		comf	vCurNum,F		; Nope! Desired output is the opposite
		tst	vCurNum			; Is the desired output time?
		Jz	PtrDone			; Yepp! Pointer is at the right position
		Movlf	pDspBuf+6,vDspPtr	; Nope! Display Buffer pointer to date
PtrDone		Point	cPRESP			; Pre-String Pause
		Cmpfl	vMsType,cISSMOO		; Smooth-style tune?
		skipge				; Yepp! Do not turn buzzer off yet
		call	BuzzerOff		; Turn buzzer off
		call	OutputSup		; Pre-String Suppressed Digits Pause		
		Movff	vDspPtr,FSR		; Reset pointer to the Display Buffer
		call	OutputNum		; 1st number
		Point	cINP			; Inter-Number Pause
		call	OutputNum		; 2nd number
		Point	cINP			; Inter-Number Pause
		call	OutputNum		; 3rd number
		call	OutputSup		; Post-String Suppressed Digits Pause
		Movff	FSR,vDspPtr		; Save current Display Buffer pointer
		Cmpfl	vMsType,cATST		; Is it a test music option?
		Jge	TestMus			; Yepp! Don't turn buzzer off at all
		tst	vNoteDr			; Currently played note is over?
		skipnz				; Nope! Don't turn buzzer off yet
		call	BuzzerOff		; Turn buzzer off
TestMus		call	IsScroll		; Display is Scrolling?
		Jz	ScrollDisp		; Yepp! Handle that case separately
		bsf	vFlags2,bQUIDLE		; Nope! Index Hole quits Idle (*)
		Point	cPOSTSP			; "Soft" Post-String Pause
		bcf	vFlags2,bQUIDLE		; Cancel Index Hole quitting Idle
		Jclr	vFlags2,bSDCNT,OutSide0	; Is this Side 0?
		Point	cPRXCOR			; Nope! Uncond. Idx Hole Parallax Corr
OutSide0	Jclr	vFlags2,bSAWIDX,OnePSP	; Index Hole was not seen - 1 PSP & done
		Jset	vFlags2,bSDCNT,OutSide1	; Index Hole seen; is this Side 1?
		Point	cPRXCOR			; Nope! Idx Hole Parallax Corr still due
OutSide1	bcf	vFlags2,bSDCNT		; Upcoming side must be Side 0 [again]
		return
ScrollDisp	Point	cPOSTSP			; Post-String Pause
		Jclr	vFlags2,bSDCNT,OnePSP	; Side 0 - standard single PSP
		Point	cREVCOR			; Side 1 - start w/ Revolution Corr
		Cmpfl	vDspMod,2		; Display Mode is Stand-Scroll?
		Jz	OnePSP			; Yepp! 1 PSP
		Jlt	ZeroPSP			; Left-Scroll: 0 PSP's
		Point	cPSP			; Right-Scroll: 2 PSP's
OnePSP		Point	cPSP			; Stand-Scroll: 1PSP
ZeroPSP		movlw	cSDMSK			; Invert the Side Count bit
		xorwf	vFlags2,F
		return

; (*) Because of the Index Hole parallax phenomenon, during Stationary display behavior
; the Index Hole starts being seen even before the Back Side's Post-String Pause is
; over. The only time this is not the case is when switching from the Right-Scrolling to
; the Alternating display mode. However, instead of having a spinning loop to wait for
; the Index Hole to show up, we just let the display that is scrolling right (this time
; due to the superfluous Index Hole Parallax Correction) gradually bring itself to the
; right orientation (while the music never stops even for a split second).


;------ Output Suppressed Digits Pause

; Input:  vDspPtr = Beginning of current side in the Display Buffer
; Output: FSR points to the position beyond current side

; Note: It is assumed that Suppress If Zero & Decimal Point are mutually exclusive!

OutputSup	Movff	vDspPtr,FSR		; Start of the side's Display Buffer
		Movlf	6,vGenCtr		; Initialize the loop countdown
SupLoop		movf	INDF,W			; Access the current digit
		andlw	cXDMSK			; Cut the Flashing attribute
		xorlw	cSUPMSK			; Reverse the Suppress If Zero attibute
		Jnz	NoSup			; Digit is a suppressed zero?
		Point	cHDIGP			; Yepp! Issue a Half Digit Pause
NoSup		incf	FSR,F			; Increment Dispaly Buffer's pointer
		Djnz	vGenCtr,SupLoop		; Loop until side is over
		return


;------ Output Number

; Input:  FSR = Current position in the Display Buffer to read from
; Output: FSR points to the next position

OutputNum	call	OutputDig		; 1st digit
		Point	cIDP			; Inter-Digit Pause
		call	OutputDig		; 2nd digit
		return


;------ Output Digit
	
; Input:  FSR = Current position in the Display Buffer to read from
; Output: FSR points to the next position

OutputDig	movf	INDF,W			; Access the digit
		andlw	cXDMSK			; Cut the Flashing attribute
		xorlw	cSUPMSK			; Reverse the Suppress If Zero attibute
		Jz	DigDone			; Suppressed! I'm all done here!
		Jclr	INDF,bFLASH,CharOn	; Character not flashing: character on
		Jset	vFshCtr,bFSHBIT,CharOff	; Flashing bit is set: character off
CharOn		Movff	INDF,PORTA		; Light the Nixie
CharOff		Point	cDIGLTP			; Digit Light-Up Pause
		Movlf	cSPACE,PORTA		; Unlight the Nixie
		Point	cDIGWP			; Digit Width Pause
DigDone		incf	FSR,F			; Advance the pointer in Display Buffer
		return
 

;------ Sound the music as part of OutputSide

SoundMusic	call	BuzzerOff		; Start by assuming that buzzer is off
		Cmpfl	vMsType,cISTUNE		; Music is a tune?
		Jge	PlayTune		; Yepp! Play it
		Movff	vCrpPtr,FSR		; Nupp! Chirpie - "Play" the next digit
		movf	INDF,W			; Access the digit
		andlw	cDIGMSK			; Cut all the attributes
		tst	vMsType			; Music type is 0 (Silence)?
		skipnz				; Nupp! Sound the actual digit
		movlw	5			; Yepp! "Sound" a medium pitch silently
		call	DigPitchIDLut		; Look up the digit's Pitch ID
		call	NotePitchLut		; Look up the Pitch ID's pitch divider
		movwf	vBzWid			; Apply it to the current sound
		incf	vCrpPtr,F		; Advance Chirp Pointer to the next digit
		Cmpfl	vCrpPtr,pDspBuf+12	; Reached the end of the Display Buffer?
		Jnz	SoundNote		; Nope! Don't reset the Chirp Pointer
		Movlf	pDspBuf,vCrpPtr		; Yepp! Back to the start of the Display
		goto	SoundNote		; Sound that note
PlayTune	tst	vNoteDr			; Currently played note is over?
		Jnz	PlayNote		; Nupp! Keep playing it
RefetchNote	Cmpfl	vMsType,3		; Music option #2?
		Jge	Music3			; Nupp! Try the next option
		movf	vTnPtr,W		; Get the Tune Pointer
		call	ManicTuneLut		; Play next note in the tune
		goto	ProcessNote		; Process the note
Music3		; *** Next music option here!
ATest		Cmpfl	vMsType,cPCHTST		; Music option A-Note Test?
		Jge	PchTest			; Nupp! Try the next option
		movf	vTnPtr,W		; Get the Tune Pointer
		call	ATestTuneLut		; Play next note in the tune
		goto	ProcessNote		; Process the note
PchTest		Movff	vTnPtr,vBzWid		; Use vTnPtr as free-running pitch ctr
		decf	vTnPtr,F		; Increase the pitch
		goto	SoundPitch		; Sound the current pitch
ProcessNote	movwf	vBzWid			; Capture note Pitch ID from Note Descr.
		movwf	vNoteDr			; Capture the note Duration ID from N.D.
		Cmpfl	vBzWid,ENDTUNE		; Currently played tune over?
		Jnz	KeepNote		; Nupp! Keep processing the note
		clrf	vTnPtr			; Reset the Tune Pointer
		goto	RefetchNote		; Refetch the first note of the tune
KeepNote	incf	vTnPtr,F		; Increment the Tune Pointer
		rrf	vBzWid,F		; Decipher the note Pitch ID
		rrf	vBzWid,F		; {$} Rot# must be in sync w/ cDRWID!
		rrf	vBzWid,F
		movlw	cPCHMSK
		andwf	vBzWid,W
		call	NotePitchLut		; Look up the note pitch divider
		movwf	vBzWid			; Put result back to vBzWid
		movlw	cDRMSK			; Decipher the note Duration ID
		andwf	vNoteDr,W
		call	NoteDuratnLut		; Look up the note duration count
		movwf	vNoteDr			; Put result back to vNoteDr
PlayNote	decf	vNoteDr,F		; Decrement the Duration Counter
SoundNote	tst	vMsType			; Music type is 0 (Silence)?
		Retz 				; Yepp! Do not turn buzzer on
		tst	vBzWid			; Current note is a pause?
		skipz				; Yepp! Do not turn buzzer on
SoundPitch	call	BuzzerOn		; Turn buzzer on
		return


;------ The most executed Idle routine - generate delay for desired carousel revolution

; Input: W = Number of points (PI/1000) of carousel revolution to delay

PtDelay		bsf	PORTB,bIDLE		; Set the Idle diagnostic bit
		movwf	vPntCtr			; Load number of points
		tst	vPntCtr			; Is it 0?
		Jz	QuitIdle		; Yepp! Get out of here quick
PointLoop	
	if DDEBUG
		Movlf	cMAGCNT,vMagCtr		; Load the Time Magnifier (Debug only)
MagniLoop
	endif

		skipset	PORTB,bINDEXH
		incf	vYear,F	

		Movlf	cITRPPT,vItrCtr		; Load the number of iters for 1 point
		Jclr	vFlags2,bQUIDLE,CoreLoop; No quit upon Index Hole detection
		bsf	vFlags2,bSAWIDX		; Assume Index Hole will be seen
		Jclr	PORTB,bINDEXH,QuitIdle	; Index Hole detected: quit Idle!
		bcf	vFlags2,bSAWIDX		; Index Hole wasn't seen
CoreLoop	decfsz	vPDMCtr,F		; Buzzer pitch div multiplier done yet?
		goto	NoToggle		; Nope! Move on
		Movlf	cPDMUL,vPDMCtr		; Reload the Pitch Div Multipler Ctr
		decfsz	vBzCtr,F		; Buzzer half-cycle done yet?
		goto	NoToggle		; Nope! Move on
		Movff	vBzWid,vBzCtr		; Reload the Buzzer Half-Cycle Counter
		movlw	cBZMSK			; Toggle the buzzer output!
		xorwf	PORTB,F
NoToggle	decfsz	vItrCtr,F		; 1 point passed yet?		
		goto	CoreLoop		; Nope! Stay in the Core Loop
	if DDEBUG
		decfsz	vMagCtr,F		; Magnification done yet? (Debug only)
		goto	MagniLoop		; Nope! Stay in loop
	endif
		decfsz	vPntCtr,F		; Point delay passed yet?
		goto	PointLoop		; Nope! Stay in loop
QuitIdle	bcf	PORTB,bIDLE		; Clear the Idle diagnostic bit
		return
 

;------ Turn buzzer on/off

BuzzerOff	clrw				; W = 0 means off
		skipz
BuzzerOn	iorlw	1			; W != 0 means on	
		bsf	STATUS,RP0		; SWITCH TO BANK 1
		errorlevel -302			; Disable msg 302 ("Not in bank 0")
		skipnz				; Buzzer to be turned on?
		bsf	TRISB,bBUZZER		; Nope! Turn buzzer off
		skipz				; Buzzer to be turned off?
		bcf	TRISB,bBUZZER		; Nope! Turn buzzer on
		errorlevel +302			; Re-enable msg 302 ("Not in bank 0")
		bcf	STATUS,RP0		; Switch back to Bank 0
		return


;==== Interrupt Handler ================================================================

IntHdl		Jclr	INTCON,T0IF,CritErr	; Not a Timer0 IT -> OOPS!
		
;---- Timer0 interrupt -----------------------------------------------------------------

		bsf	PORTB,bINISR		; Set the In ISR diagnostic bit
		movwf	vWTmp			; Save W
		swapf	STATUS,W		; Save [a nybble-swapped copy of] STATUS
		movwf	vStsTmp
		Movff	FSR,vFsrTmp		; Save FSR (not needed; just in case)

		call	AdvClock		; Advance the clock
		call	ReadButton		; Read button status & generate events
		call	ProcButton		; Process the button events

		bcf	INTCON,T0IF		; Clear the Timer0 IT flag
		Movff	vFsrTmp,FSR		; Restore FSR
		swapf	vStsTmp,W		; Restore STATUS
		movwf	STATUS
		swapf	vWTmp,F			; Restore W
		swapf	vWTmp,W
		bcf	PORTB,bINISR		; Clear the In ISR diagnostic bit

		retfie
		
; Note: All that SWAPF-trickery: needed, because "movf" alters the Z flag!


;---- Other interrupts -----------------------------------------------------------------

; Since no other interrupts are expected, this scenario results in a CRITICAL ERROR,
; halting the clock and putting up a scary side-show.

CritErr		clrf	vGenCtr			; Reset the free-running counter
InfLoop		Movff	vGenCtr,PORTA		; Throw the character on the display
		Point	cDIGLTP
		Movlf	cSPACE,PORTA		; Wait for the character to rotate
		Point	cDIGWP
		incf	vGenCtr,F		; Increment the counter
		goto	InfLoop			; Stay in the loop infinitely!

		
;==== Interrupt handler subroutines ====================================================

;---- Clock handling -------------------------------------------------------------------

;------ Advance the clock

; Note: Special entry points from ProcButton:
;   1. Inc*: Called when the clock is being set. (No rollover)
;   2. AdjustDay: Called upon return to Running State, to compensate for the infamous
;      "leap year egress" (after setting the date to February 29, the year is changed
;      from a leap year to a non-leap year). This can also be useful when a day-first
;      international date representation option is added to the firmware. (Rollover)
		
AdvClock	Retset	vFlags2,bFROZEN		; Don't advance clock if it is Frozen
		decfsz	vSecTck,F		; Second tick countdown reached zero?
		return				; Nope! Get out of here

		Movlf	cTCKPS,vSecTck		; Yepp! Reload the Ticks Per Sec value
		tst	vCorTck			; Leap second facility in use at all?
		Jz	IncSec			; Nope! Move on
		decfsz	vCorTck,F		; Is this gonna be a "leap second"?
		goto	IncSec			; Nope! Move on
		incf	vSecTck,F		; Leap the second (uncomment one)
;;;		decf	vSecTck,F		; De-Leap the second (uncomment one)
		Movlf	cTCKCOR,vCorTck		; Reload the Tick Correction value
		
IncSec		incf	vSec,F			; Increment seconds
		skipclr	vFlags,bSHORTB		;   Value is being set?
		bsf	vFlags2,bFROZEN		;   Yepp! Freeze the clock
		Cmpfl	vSec,60			;   Radix reached?
		Retnc				;   Nope! Done
		clrf	vSec			;   Yepp! Reset counter & continue
		Retset	vFlags,bSHORTB		;   If value is being set, no rollover!
IncMin		incf	vMin,F			; Increment minutes
		Cmpfl	vMin,60			;   Radix reached?
		Retnc				;   Nope! Done
		clrf	vMin			;   Yepp! Reset counter & continue
		Retset	vFlags,bSHORTB		;   If value is being set, no rollover!
IncHour		incf	vHour,F			; Increment hours
		Cmpfl	vHour,24		;   Radix reached?
		Retnc				;   Nope! Done
		clrf	vHour			;   Yepp! Reset counter & continue
		Retset	vFlags,bSHORTB		;   If value is being set, no rollover!

IncDay		incf	vDay,F			; Increment day
AdjustDay	goto	DayRoll			;   [Insanely variable] radix reached?
JumpBack	Retnc				;   Nope! Done
		Movlf	1,vDay			;   Yepp! Reset counter & continue
		Retset	vFlags,bSHORTB		;   If value is being set, no rollover!
IncMonth	incf	vMonth,F		; Increment month
		Cmpfl	vMonth,13		;   Radix reached?
		Retnc				;   Nope! Done
		Movlf	1,vMonth		;   Yepp! Reset counter & continue
		Retset	vFlags,bSHORTB		;   If value is being set, no rollover!
IncYear		incf	vYear,F			; Increment year
		Cmpfl	vYear,100		;   Radix reached?
		Retnc				;   Nope! Done
		clrf	vYear			;   Yepp! Reset counter
		return


;------ Check day rollover

; ATTENTION! Normally this would be a subroutine, but... we ran out of stack. :-(
; (Fortunately, it is only called from one point...)

; Note: This "subroutine" assumes that every year that is divisible by 4 is a leap
; year. Therefore, while it would have worked perfectly in the special year 2000 (had
; this clock been born before 2000), it will not work correctly in year 2100!

; Output: 
;  - Z set if current day just rolled over
;  - C set if current day exceeds maximum

DayRoll		movlw	0x03			; Mask 0000 0011
		andwf	vYear,W			; W=0: leap year, W=non-0: regular year
		skipz
		movlw	-1			; Regular year: lookup table offset -1
		skipnz
		movlw	11			; Leap year: lookup table offset 11
		addwf	vMonth,W		; Final lookup table offset in W
		call	DayLut			; Look up the number of days in month
		cmpfw	vDay			; Compare current day to days in month
		goto	JumpBack		; "Return" to AdvClock	

		
;---- Button handling ------------------------------------------------------------------

;------ The button status detection state machine

; Generates the button events for ProcButton; however, takes care of unfreezing the
; clock & resetting the Ticks Per Sec Counter "in house".
;
; Button events:
;  - Short Button Event (vFlags:bSHORTB): Generated upon the release of a short press
;  - Long Button Event (vFlags:bLONGB): Generated upon a press reaching the duration
;    (cLNGTCK) that qualifies it as a long press
;
; Persistent states:
;  - Double Click (vFlags:bDBLCLK): Set upon the start of a press that followed the
;    release of a previous press within a sufficiently short time (cDBCTCK); consumed
;    upon the processing of the next button event
;  - Cancel Short Button Event (vFlags:bCANSHT): Set upon the generation of a Long
;    button event or clock unfreeze; consumed upon the next button release

ReadButton	bcf	vFlags,bSHORTB		; Clear the button events
		bcf	vFlags,bLONGB

		Jset	PORTB,bBUTTON,NoPress	; If button not pressed, proceed as such

; 1. Button pressed
		Jset	vFlags,bBUTST,CtPress	; If not start of a press, keep counting
		Cmpfl	vButTck,cDBLTCK		; Press qualifies for a Double Click?
		skipge				; Nope! Do not set the Double Click flag
		bsf	vFlags,bDBLCLK		; Yepp! Set the Double Click flag
		clrf	vButTck			; Reset the Button Tick Counter
		tst	vSetPtr			; In Setting State right now?
		Jnz	CtPress			; Yepp! No action upon start of press
		Jclr	vFlags2,bFROZEN,CtPress	; If clock is not Frozen, -"-
		Movlf	cTCKPS,vSecTck		; Reset the Ticks Per Sec Counter
		bcf	vFlags2,bFROZEN		; Unfreeze the clock
		bsf	vFlags,bCANSHT		; Cancel Short Button Event
CtPress		bsf	vFlags,bBUTST		; Save the current button state
		Cmpfl	vButTck,cLNGTCK		; Long enough for Long Button event?
		Jnz	NoLong			; Nope! Move on
		bsf	vFlags,bLONGB		; Yepp! Set the event's flag
		bsf	vFlags,bCANSHT		; Cancel Short Button Event
NoLong		Cmpfl	vButTck,255		; About to max out on Button Tick?
		skipz				; Yepp! Do not increment Button Tick
		incf	vButTck,F		; Nope! Increment Button Tick
		return

; 2. Button not pressed
NoPress		Jclr	vFlags,bBUTST,CntDeprss	; If not end of a press, keep counting
		clrf	vButTck			; Reset the Button Tick Counter
		skipset	vFlags,bCANSHT		; Short Button Event needs cancel?
		bsf	vFlags,bSHORTB		; Nope! Generate the event
		bcf	vFlags,bCANSHT		; Clear the Short Butt Event Cancel flag
CntDeprss	bcf	vFlags,bBUTST		; Save the current button state
		Cmpfl	vButTck,255		; About to max out on Button Tick?
		skipz				; Yepp! Do not increment Button Tick
		incf	vButTck,F		; Nope! Increment Button Tick
		return


;------ Infamy #3: The button processing state machine

; Interprets the button indications generated by ReadButton.

; Note: The Short & Long Button events are mutually exclusive [per definition]!

ProcButton	tst	vSetPtr			; Setting State?
		Jnz	InSetting		; Yepp! The nastier case...
		
; 1. Running State
		Jclr	vFlags,bSHORTB,RunLong	; Short Button Event? Try Long if not

; 1.1 Short Button Event
		Jset	vFlags,bDBLCLK,DblClk	; If Double Click, proceed as such

; 1.1.1 Single Click
		incf	vDspMod,F		; Advance the Display Mode
		Cmpfl	vDspMod,cNUMMOD		; Maximum reached?
		skiplt				; Nope! Display Mode is OK
		clrf	vDspMod			; Yepp! Reset the Display Mode
		return

; 1.1.2 Double Click
DblClk		bcf	vFlags,bDBLCLK		; Clear Double Click
		movlw	cNUMMOD			; Undo the Display Mode increment
		tst	vDspMod			; Currently at minimum?
		skipnz				; Nope! Display Mode is OK
		movwf	vDspMod			; Yepp! Wrap around the Display Mode
		decf	vDspMod,F		; Decrement the Display Mode
		incf	vMsType,F		; Advance the Music Type
		Cmpfl	vMsType,cNUMMUS		; Max reached?
		skiplt				; Nope! Music Type is OK
		clrf	vMsType			; Yepp! Reset the Music Type
		clrf	vTnPtr			; Reset the Tune Pointer
		clrf	vNoteDr			; Reset the Duration Counter
		return

RunLong		Retclr	vFlags,bLONGB		; Long Button event? Return if not
; 1.2 Long Button event
		bcf	vFlags,bDBLCLK		; Clear Double Click (not used here)
		Movlf	pClkMem,vSetPtr		; Setting State (vSetPrt=Clk Mem start)
		return
		
; 2. Setting State
InSetting	Jclr	vFlags,bSHORTB,SetLong	; Short Button Event? Try Long if not

; 2.1 Short Button Event
		bcf	vFlags,bDBLCLK		; Clear Double Click (not used here)
		clrf	vFshCtr			; Reset Flash Counter to light up number
		Cmpfl	vSetPtr,vHour		; Setting minutes?
		Jz	IncHour			; Yepp! Return through adjusting value
		Cmpfl	vSetPtr,vMin		; Setting minutes?
		Jz	IncMin			; Yepp! Return through adjusting value
		Cmpfl	vSetPtr,vSec		; Setting seconds?
		Jz	IncSec			; Yepp! Return through adjusting value
		Cmpfl	vSetPtr,vMonth		; Setting month?
		Jz	IncMonth		; Yepp! Return through adjusting value
		Cmpfl	vSetPtr,vDay		; Setting day?
		Jz	IncDay			; Yepp! Return through adjusting value
		goto	IncYear			; Return through adjusting year value

SetLong		Retclr	vFlags,bLONGB		; Long Button event? Return if not		

; 2.2 Long Button event
		bcf	vFlags,bDBLCLK		; Clear Double Click (not used here)
		Movlf	cFSHON,vFshCtr		; Set Flash Counter to blank number
		incf	vSetPtr,F		; Move on to the next value
		Cmpfl	vSetPtr,pClkMem+6	; Moved beyond last value to set?
		Retlt				; Nope! Done
		clrf	vSetPtr			; Back to Running State
		goto	AdjustDay		; Return through adjusting the day


;==== Stop that little runaway at Runaway Bay ==========================================

;		org	0x3FF
;		goto	CritErr			; Execution got to this point -> OOPS!


		end
