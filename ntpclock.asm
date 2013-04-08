; ntpclock.asm
;
; NTPClock Firmware v3.0.0
; PIC16F84A Assembly Code for the World's First Nixie Tube Propeller Clock
;
; (C) Peter Csaszar, 2002-2013
; http://www.nixiana.com
;
; Created: July 27, 2002
; Last modified: April 8, 2013


;        1         2         3         4         5         6         7         8        
; 34567890123456789012345678901234567890123456789012345678901234567890123456789012345678
;
; Recommended font: Courier New, 9 pt
; Recommended tab:  8


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
; PORTB 0 (I): Index Hole input
; PORTB 1 (I): Control Button input
; PORTB 2 (O): In ISR output [diagnostics]
; PORTB 3 (I): 12/24-hour Selector input
; PORTB 4 (O): Beeper output
; PORTB 5 (I): <Unused>
; PORTB 6 (I): <Unused>  [ICSP Clock]
; PORTB 7 (I): <Unused>  [ICSP Data]


;***************************************************************************************
; Summary of Behaviors
;***************************************************************************************

; 1. Hour Notation
;    - 12-Hour: "12/24H" Jumper off
;    - 24-Hour: "12/24H" Jumper on
;
; 2. Display Mode
;    - Scrolling:  vDspMod=0
;    - Stationary: vDspMod=255
;
; 3. Operating State
;    - Running: vSetPrt=0
;    - Setting: vSetPtr=Non0
;
; 4. Different conditions
;    - Frozen Clock:  vFlags:bFROZEN=1 (Waiting for button push to start clock)
;    - Firmware Info: vFlags:bFIRMWR=1 (Displaying firmware info instead of time)
;    - Carousel Test: vFlags:bCARTST=1 (Quasi-stationary display in Scrolling Mode)


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

;==== Constants ========================================================================

; Customization constants

cFCLK		equ	19660800		; Clock cycles per second [Hz = cc/s]
cFROT		equ	360			; Carousel rotation speed [rev/min]
cFSCR		equ	4			; Display scroll speed [rev/min]
cLNGTM		equ	750			; Long Button Press time [ms]
cBPOCT		equ	3			; Beeper octave downshift

; Time Magnifier (for DEBUG reasons)

cMAGCNT		equ	1			; Normal-1, Debug-64 (0.5 sec/digit)

; Fundamental constants (Note: iter = PtDelay InnerLoop's non-quitting iteration)

cCCPIC		equ	4			; Clock cycles per instr. cycle [cc/ic]
cPTPR		equ	2000			; Points per revolution [point/rev]
cICPITR		equ	6			; Instr. cycles per loop iter [ic/iter]

; Geometrical constants

cRMIN		equ	50			; Innermost digit from center [mm]
cRAVG		equ	54			; Middle digit from center [mm]
cDIGWID		equ	8			; Digit width [mm]

; Timing configuration & adjustment constants

cTCKCOR		equ	0			; Seconds per 1 leap second (0: unused)

cTMRPSC		equ	256			; Timer0 prescaler (Also see "####"!)
cTMRCNT		equ	256			; Timer0 required count (Just max out)
cLPCOR		equ	3			; Loop count overhead correction [iter]
cPRXCOR		equ	80			; IR LED parallax correction [point]

; Calculated system constants (Note: tick = Timer0 interrupt)

cTMRRLD		equ	256-cTMRCNT		; Timer0 reload value (Now unused!)
cTCKPS		equ	cFCLK/cCCPIC/cTMRPSC/cTMRCNT
						; Ticks per sec (truncated!) [tick/s]
cLNGTCK		equ	cLNGTM*cTCKPS/1000	; Ticks until a Long Button Event [tick]
cLPCNT		equ	(cFCLK/(cCCPIC*cICPITR)) / (cFROT*cPTPR/60) - cLPCOR	
						; Loop iterations per point [iter/point]
cSCRGAP		equ	cPTPR*cFSCR/cFROT	; Angle gap causing scroll [point]
cDIGWAN		equ	50			; Max angle of digit width [point]
						; 2*arctg(cDIGWID/(2*cRMIN))*cPTPROT/PI
; Point delay constants for display layout [point]

cDIGLTP		equ	10			; Digit Light Pause
cDIGWP		equ	cDIGWAN			; Digit Width Pause
cDIGIT		equ	cDIGLTP+cDIGWP		; Total Digit width
cIDP		equ	15			; Inter-Digit Pause
cHDIGP		equ	cDIGIT/2		; Half Digit Pause
cNUMBER		equ	2*cDIGIT+cIDP		; Total Number width
cINP		equ	42			; Inter-Number Pause
cSTRING		equ	3*cNUMBER+2*cINP	; Total String width
cPRESP		equ	(cPTPR/2-cSTRING)/2	; Pre-String Pause
cISP		equ	cSCRGAP			; Inter-Side Pause
cPOSTSP		equ	cPRESP-cISP		; Post-String Pause
cFUDGE		equ	10			; Empirical 1000-point correction (*)
 		
 		if	cPRESP>255 		; Check the value of cPRESP {**}
		error 	"Pre-String Pause value doesn't fit into a byte"
		endif

; (*) Set by attempting to stop a scrolling display ["quasi-stationary" display] in
; Carousel Test Condition, so that the rotation speed of scrolling messages set by cFROT
; will be accurate. It compensates for the discrepancy introduced by rounding errors,
; the ISR's delay effect and the relative inaccuracy of the floppy motor's speed control
; and the uC's quartz crystal. Note however that despite all these efforts, achieving a
; stationary display is virtually impossible without some position syncronization [such
; as the "Index Hole" using the IR LED/photodiode pair in this particular solution]. So
; then why be so dead serious about it? Just for FUN...! :-)
;
; {**} The Pre-String Pause is the longest delay during display generation. If its value
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

; Flag bit constants

bSHORTB		equ	0			; Short Button Press Event flag's bit#
bLONGB		equ	1			; Long Button Press Event flag's bit#
bCANSHT		equ	2			; Cancel Short Button flag's bit#
bFROZEN		equ	3			; Frozen Clock Condition flag's bit#
bFIRMWR		equ	4			; Firmware Info Condition flag's bit#
bCARTST		equ	5			; Carousel Test Condition flag's bit#

cBUTMSK		equ	b'11111100'		; Mask to reset Button Press Event flags

; I/O port bit constants

bINDEXH		equ	0			; Index Hole input's bit# (PORTB)
bBUTTON		equ	1			; Control Button input's bit# (PORTB)
bINISR		equ	2			; In ISR output's bit# (PORTB)
b1224H		equ	3			; 12/24-hour Selector input's bit# (PORTB)
bBEEPER		equ	4			; Beeper output's bit# (PORTB)
cBPMSK		equ	1<<bBEEPER		; Beeper output's bit mask


;==== Variables ========================================================================

; Fundamental system variables

vDspMod		equ	0x0C			; Display Mode
vSetPtr		equ	0x0D			; Pointer to Clock var being set
vFlags		equ	0x0E			; System flags

; Notes:
;
; vDspMod: Determines the Display Mode ("Mode" for short)
;
;   0-Scrolling Mode, 255-Stationary Mode
;
; vSetPtr: Determines the Operating State ("State" for short)
;
;   0-Running State, Non0-Setting State [address of clock variable being set]
;
; vFlags:
;
;   Bits: 7 6 5 4 3 2 1 0
;         - - C W F X G T
;
;         C: Carousel Test Condition flag
;         W: Firmware Info Condition flag
;         F: Frozen Clock Condition flag
;         X: Cancel Short Button Press Event flag
;         G: Long Button Press Event flag
;         T: Short Button Press Event flag


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


; Temporary registers for Interrupt Handler

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
vCorTck		equ	0x31			; Second Tick Correction counter
vButTck		equ	0x32			; Button Hold Tick Counter (1 byte!)
vLpCtr		equ	0x33			; Loop counter for 1 point (PI/1000)
vMagCtr		equ	0x34			; Time Magnifier counter (for debug)
vPntCtr		equ	0x35			; Delay counter [point]
vGenCtr		equ	0x36			; Generic loop counter
vBpCtr		equ	0x37			; Beeper half-period counter [iter]
vBpWid		equ	0x38			; Beeper half-period width [iter]
vBpOCtr		equ	0x39			; Beeper octave counter
vMsType		equ	0x40			; Music type (0-Random, 1-JetSet)
vMsTPtr		equ	0x41			; Music current tune pointer
						; - Chirpie: Display Buffer
						; - Tune: Tune table
vMsTCtr		equ	0x42			; Music current tune length counter


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
		
;---- Days Per Month lookup ------------------------------------------------------------

; Note: Calculated GOTO table must not span a 256-word boundary, so this subroutine
; better be kept here at the beginning of the code!

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
		
;---- Digit to Sound Half-Period Width lookup ------------------------------------------

; Note: Calculated GOTO table must not span a 256-word boundary, so this subroutine
; better be kept here at the beginning of the code!

; Input:  W = Digit value
; Output: W = Number of half-period iterations (not considering octave downshift) [iter]

SoundLut	addwf	PCL,F 			; Add offset to PC for computed GOTO
		retlw	0			; 0: C =! 256
		retlw	228			; 1: D
		retlw	203			; 2: E
		retlw	171			; 3: G
		retlw	152			; 4: A
		retlw	128			; 5: C
		retlw	114			; 6: D
		retlw	102			; 7: E
		retlw	85			; 8: G
		retlw	76			; 9: A


;==== Main code ========================================================================

; HW configuration errands

Start		bsf	STATUS,RP0		; SWITCH TO BANK 1
		errorlevel -302			; Disable msg 302 ("Not in bank 0")
		clrf	TRISA			; PortA: All output
		Movlf	b'11111011',TRISB	; PortB: Bit 2: output, all other: input
		bcf	OPTION_REG,NOT_RBPU	; Turn on PortB's weak pullups
		bcf	OPTION_REG,PSA		; Prescaler assigned to Timer0
		bsf	OPTION_REG,PS2		; Prescaler: 1:256
		bsf	OPTION_REG,PS1		; #### Note: Must reflect cTMRPSC!
		bsf	OPTION_REG,PS0
		bcf	OPTION_REG,T0CS		; Start Timer0
		errorlevel +302			; Re-enable msg 302 ("Not in bank 0")
		bcf	STATUS,RP0		; Switch back to Bank 0

		Movlf	cSPACE,PORTA		; Blank the Nixie
		clrf	PORTB			; Clear Port B (that 1 output... :-) )

		Movlf	cTMRRLD,TMR0		; Load Timer0 (Super-nitpicky ;-) )
		Point	10			; Short delay to get the IR LED ready

; Initialize variables

		clrf	vDspMod			; Display Mode = Scrolling
		clrf	vSetPtr			; Operating State = Running
		clrf	vFlags			; Reset all flags

		Movlf	cTCKPS,vSecTck		; Second Tick Counter
		Movlf	cTCKCOR,vCorTck		; Tick Correction
		clrf	vButTck			; Button Hold Tick Counter

		Movlf	pDspBuf,vBpDPtr		; Display Buffer beeping pointer
		Movlf	cBPOCT,vBpOCtr		; Beeper octave downshift

		Jclr	PORTB,bBUTTON,ShowFirm	; HIJACK boot if button pressed
		
; Normal boot

NormBoot	call	PreloadClk		; Preload Clock Memory w/ a bogus time
		clrf	vFshCtr			; Reset the Flashing Character Counter
;		bsf	vFlags,bFROZEN		; Freeze the clock [it became "Dizzy"]
		bsf	INTCON,GIE		; Enable Global Interrupts  
		bsf	INTCON,T0IE		; Enable Timer0 Interrupt

; The Main Loop

MainLoop	call	IsScroll		; Display is scrollong?
		Jz	SkipIdxH		; Yepp! Skip waiting for the Index Hole
WaitIdxH	Jset	PORTB,bINDEXH,WaitIdxH	; Spinning loop: wait for the Index Hole
SkipIdxH	call	PrintTime		; Time Memory -> Display Buffer
		call	OutputBuff		; Display Buffer -> Nixie
		goto	MainLoop		; Main Loop done

; Note: In this very simple case, there is no need to hook up the detection of the Index
; Hole [i.e., the passing of the IR LED] to an interrupt.

; The "hijacked" main program to start the Firmware Info Condition

ShowFirm	call	PreloadFirm		; Preload Clock memory w/ firmware info
		bsf	vFlags,bFIRMWR		; Indicate Firmware Info Condition
		skipset	PORTB,bINDEXH		; Is the IR LED also being seen?
		bsf	vFlags,bCARTST		; Yepp! Special Carousel Test Condition
		
; Firmaware Display Main Loop (Borrow the bSHORTB flag)

FirmLoop	Jset	vFlags,bSHORTB,OrigRls	; Original button already released?
		skipclr	PORTB,bBUTTON		; Nope! Button is still being pressed?
		bsf	vFlags,bSHORTB		; Nope! Indicate first release
		goto	DoneOrig		; End of "original button still pressed"
OrigRls		Jclr	PORTB,bBUTTON,QuitLoop	; New button pressed - get ready to quit
DoneOrig	call	PrintTime		; Firmware info -> Display Buffer
		call	OutputBuff		; Display Buffer -> Nixie
		goto	FirmLoop		; Firmware Loop done
QuitLoop	Jclr	PORTB,bBUTTON,QuitLoop	; New button still being pressed - stay
		bcf	vFlags,bFIRMWR		; Cancel Firmware Info Condition
		Point	10			; Short delay to kill any button bounce
		goto	NormBoot		; Button released - back to normal boot


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

	
;------ Preload the Clock Memory with firmware information

PreloadFirm	Movlf	3,vHour			; Version# [major.minor.subminor]
		Movlf	0,vMin
		Movlf	0,vSec
		Movlf	4,vMonth		; Release date
		Movlf	8,vDay
		Movlf	13,vYear
		return

	
;------ Determine if the display is scrolling

; Output: Z=0 (NZ): Not scrolling, Z=1 (Z): Scrolling

IsScroll	movf	vDspMod,W		; Display Mode: Stationary?
		iorwf	vSetPtr,W		; Operation State: Setting?
		Retnz				; If either of the above, not scrolling
		skipclr	vFlags,bFROZEN		; Clock is in Frozen Condition?
		bcf	STATUS,Z		; Yepp! Not scrolling
		return				; Nope! Scrolling


;---- Display --------------------------------------------------------------------------

;------ Infamy #1: Print the contents of the Clock Memory into the Display Buffer

PrintTime	incf	vFshCtr,F		; Increment the Flashing Chr Counter
; 1. Print the contents
		Movlf	pClkMem,vClkPtr		; From: Clock Memory
		Movlf	pDspBuf,vDspPtr		; To: Display Buffer
		Movlf	6,vGenCtr		; Initialize the loop countdown
PrintLoop	call	PrintNum		; Print the value
		Djnz	vGenCtr,PrintLoop	; Loop until done

; 2 Remaining chores
		bsf	pDspHr+1,bDP		; Decimal point after hours
		bsf	pDspMin+1,bDP		; Decimal point after minutes
		Jclr	vFlags,bFIRMWR,NoFirm	; 1. Firmware Info Condition
		bsf	pDspHr,bSUPZ		; "Time" values leading 0 suppress
		bsf	pDspMin,bSUPZ
		bsf	pDspSec,bSUPZ
NoFirm		bsf	pDspMon,bSUPZ		; Month value leading 0 suppressed
		bsf	pDspDay,bSUPZ		; Day  value leading 0 suppressed
		Jclr	PORTB,b1224H,Done12	; 2. The 12-hour notation
		bsf	pDspHr,bSUPZ		; Hour value leading 0 suppressed
		Cmpfl	vHour,12		; Hour<12 (i.e., AM)?
		Jlt	Done12			; Yepp! Do nothing
		Jset	vFshCtr,bFSHBIT,Done12	; Flashing bit set: DP's ON this time
		bcf	pDspHr+1,bDP		; Turn off decimal point after hours
		bcf	pDspMin+1,bDP		; Turn off decimal point after minutes
Done12		return


;------ Print number into the Display Buffer

; Input:  vClkPtr = Current position in the Clock Memory to read from
;         vDspPtr = Current position in the Display Buffer to write into
; Output: vClkPtr & vDspPtr point to the next position

PrintNum	Movff	vClkPtr,FSR		; Load the number
		Movff	INDF,vCurNum		; Save the number
		Cmpfl	vClkPtr,vHour		; Hours are being printed?
		Jnz	H24			; Nope! Do nothing
		Jclr	PORTB,b1224H,H24	; 12-hour notation selected?
		movlw	12			; Yepp! Preload 12 to W
		tst	vCurNum			; Hour=0?
		Jnz	NonZero			; Nope! Move on
		addwf	vCurNum,F		; Make 12 out of 0
		goto	H24			; Done!
NonZero		cmpfw	vCurNum			; Compare hour to 12
		Jz	H24			; =12: Do nothing
		Jlt	H24			; <12: Do nothing
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

; Note: Terminology: the clock is DIZZY after quitting the Setting State, in which the
; seconds have been changed, therefore the clock is in Frozen condition. A single button
; press snaps the clock out of dizziness, and a brand new full second is started.

PrintDig	Movff	vDspPtr,FSR
		Movff	vCurTen,INDF		; *vDspPtr = vCurTen
		incf	vDspPtr,F		; Advance pointer in the Display Buffer
		Cmpff	vClkPtr,vSetPtr		; Current clock variable being set?
		skipnz				; Nope! Do nothing
		bsf	INDF,bFLASH		; Yepp! Make digit flash
		tst	vSetPtr			; Determine if Dizzy - In Setting State?
		Retnz				; Yepp! Definitely not Dizzy
		skipclr	vFlags,bFROZEN		; Not Frozen -> not Dizzy either!
		bsf	INDF,bFLASH		; Dizzy -> make digit flash
		return


;------ Infamy #2: Output the Display Buffer's content to the Nixie

OutputBuff	Movlf	pDspBuf,vDspPtr		; vDspPtr = &pDspBuf; Who to print 1st?
		tst	vSetPtr			; Setting State?
		Jz	NoSet			; Nope! The bit more complicated case
		Cmpfl	vSetPtr,pClkMem+3	; Yepp! Second half is being set?
		Jlt	DoneRev			; Nope! Keep first half in front
		Movlf	pDspBuf+6,vDspPtr	; Yepp! Put second half to front
		goto	DoneRev			; Done calculating display reversal
NoSet		Jset	vFlags,bFROZEN,DoneRev	; No set: Time first if 1) clock Frozen
		tst	vDspMod			; 2) Scrolling Mode
		Jz	DoneRev
		incf	vSec,W			; Increment: put 59->00 transit to front
		andlw	0x02			; Find the appropriate bit
		Jz	DoneRev			; 3) desired 2-second interval is on
		Movlf	pDspBuf+6,vDspPtr	; Yepp! Put second half to front
DoneRev		call	IsScroll		; Display is scrolling?
		Jz	SkipPrxCorr		; Yepp! Skip the LED Parallax Correction
		Point	cPRXCOR			; Issue the LED Parallax Correction
SkipPrxCorr	call	OutputSide		; Output Front Side
		Point	cISP			; Inter-Side Pause
		Cmpfl	vDspPtr,pDspBuf+12	; Display Buffer wrap-around?
		Jnz	NoWrap			; Nope! Do nothing
		Movlf	pDspBuf,vDspPtr		; Reset the Display Buffer pointer
NoWrap		call	OutputSide		; Output Back Side
		call	IsScroll		; Display is scrolling?
		Retnz				; Nope! Skip Post-String Pause & da rest
		Jset	vFlags,bFIRMWR,TwoISP	; Firmware Info: 2 ISP's
		Jset	vFlags,bCARTST,OneISP	; Carousel Test: 1 ISP
		return				; Otherwise: 0 ISP's
TwoISP		Point	cISP			; 2 ISP's: BACKWARD scroll (Firmware C.)
OneISP		Point	cISP+cFUDGE		; 1 ISP: NO scroll (Quasi-stationary)
		return				; 0 ISP's: FORWARD scroll (Normal)


;------ Output Side

; Input:  vDspPtr = Beginning of current side in the Display Buffer
; Output: vDspPtr points to the position beyond current side
;
; Note: Also "sound" digits in the Display Buffer one-by-one during the Pre-String Pause

OutputSide	Cmpfl	vMsType,cMUSCHP		; Music is Chirpie?
		Jz	PlayChirpie		; Yepp! Play it
		Cmpfl	vMsType,cMUSJSW		; Music is Jet Set Willie?
		Jz	PlayJetSet		; Yepp! Play it
		goto	NoMusic			; Music is off
PlayChirpie	Movff	vMsTPtr,FSR		; Find the digit that's up for sounding
		movf	INDF,W			; Access the digit
		andlw	cDIGMSK			; Cut all the attributes
		call	SoundLut		; Look up the digit's sound's width
		movwf	vBpWid			; Apply it to the current sound
		incf	vMsTPtr,F		; Advance to the next digit for sounding
		Cmpfl	vMsTPtr,pDspBuf+12	; Reached the end of the Display Buffer?
		Jnz	SoundTune		; Nope! Don't reset the beeper pointer
		Movlf	pDspBuf,vMsTPtr		; Yepp! Back to the start of the Display
		goto	SoundTune		; Sound that tune
PlayJetSet	
SoundTune	bsf	STATUS,RP0		; SWITCH TO BANK 1
		errorlevel -302			; Disable msg 302 ("Not in bank 0")
		bcf	TRISB,bBEEPER		; Enable the beeper for this pause			
		bcf	STATUS,RP0		; Switch back to Bank 0
		Point	cPRESP			; Pre-String Pause
;		bsf	STATUS,RP0		; SWITCH TO BANK 1
;		bsf	TRISB,bBEEPER		; Disable beeper
;		errorlevel +302			; Re-enable msg 302 ("Not in bank 0")
;		bcf	STATUS,RP0		; Switch back to Bank 0
NoMusic		call	OutputSup		; Pre-String Suppressed Digits Pause		
		Movff	vDspPtr,FSR		; Reset pointer to the Display Buffer
		call	OutputNum		; 1st number
		Point	cINP			; Inter-Number Pause
		call	OutputNum		; 2nd number
		Point	cINP			; Inter-Number Pause
		call	OutputNum		; 3rd number
		Movff	FSR,vDspPtr		; Save current Display Buffer pointer
		call	OutputSup		; Post-String Suppressed Digits Pause
		bsf	STATUS,RP0		; SWITCH TO BANK 1
		bsf	TRISB,bBEEPER		; Disable beeper
		errorlevel +302			; Re-enable msg 302 ("Not in bank 0")
		bcf	STATUS,RP0		; Switch back to Bank 0
		Point	cPOSTSP			; Post-String Pause
;		bsf	STATUS,RP0		; SWITCH TO BANK 1
;		bsf	TRISB,bBEEPER		; Disable beeper
;		errorlevel +302			; Re-enable msg 302 ("Not in bank 0")
;		bcf	STATUS,RP0		; Switch back to Bank 0
		return


;------ Output Suppressed Digits Pause

; Input:  vDspPtr = Beginning of current side in the Display Buffer
; Output: FSR points to the position beyond current side

; Note: It is assumed that Suppress If Zero & Decimal Point are mutually exclusive!

OutputSup	Movff	vDspPtr,FSR		; Start of the side's Display Buffer
		Movlf	6,vGenCtr		; Initialize the loop countdown
SupLoop		movf	INDF,W			; Access the current digit
		andlw	cXDMSK			; Cut the Flashing attribute
		xorlw	cSUPMSK			; Reverse the Suppress If Zero attibute
		Jnz	NoSup			; Digit is suppressed?
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
CharOff		Point	cDIGLTP			; Digit Light Pause
		Movlf	cSPACE,PORTA		; Unlight the Nixie
		Point	cDIGWP			; Digit Width Pause
DigDone		incf	FSR,F			; Advance the pointer in Display Buffer
		return				; Done; YIPPEE!
 

;------ Generate delay for desired carousel revolution

; Input: W = Number of points (PI/1000) of carousel revolution to delay

PtDelay		movwf	vPntCtr			; Load number of points
OuterLoop	Movlf	cMAGCNT,vMagCtr		; Load the Time Magnifier (for debug)
MagniLoop	Movlf	cLPCNT,vLpCtr		; Load the delay for 1 point
InnerLoop	decfsz	vBpCtr,F		; Beeper half-period done yet?
		goto	NoToggle		; Nope! Move on
		Movff	vBpWid,vBpCtr		; Reload the beeper half-period counter
		decfsz	vBpOCtr,F		; Beeper octave downshift done yet?
		goto	NoToggle		; Nope! Move on
		Movlf	cBPOCT,vBpOCtr		; Reload the beeper octave downshift ctr
		movlw	cBPMSK			; Toggle the beeper output!
		xorwf	PORTB,F
NoToggle	decfsz	vLpCtr,F		; 1 point passed yet?		
		goto	InnerLoop		; Nope! Stay in loop
		decfsz	vMagCtr,F		; Magnification done yet?
		goto	MagniLoop		; Nope! Stay in loop
		decfsz	vPntCtr,F		; Point delay passed yet?
		goto	OuterLoop		; Nope! Stay in loop
		return


;==== Interrupt Handler ================================================================

IntHdl		Jclr	INTCON,T0IF,CritErr	; Not a Timer0 IT -> OOPS!
		
;---- Timer0 interrupt -----------------------------------------------------------------

		bsf	PORTB,bINISR		; Set the In ISR bit
		movwf	vWTmp			; Save W
		Movff	STATUS,vStsTmp		; Save STATUS
		Movff	FSR,vFsrTmp		; Save FSR (not needed; just in case)

		movlw	cBUTMSK			; Reset the Button Press Event flags
		andwf	vFlags,F
		call	AdvClock		; Advance the clock
		call	ReadButton		; Read button status & generate events
		call	ProcButton		; Process the button events

		bcf	INTCON,T0IF		; Clear the Timer0 IT flag
		Movff	vFsrTmp,FSR		; Restore FSR
		Movff	vStsTmp,STATUS		; Restore STATUS
		swapf	vWTmp,F			; Restore W (Tricky solution needed:
		swapf	vWTmp,W			;   "movf vwTmp,W" affects the Z flag!)
		bcf	PORTB,bINISR		; Clear the In ISR bit

		retfie

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
		
AdvClock	Retset	vFlags,bFROZEN		; Don't advance clock if it is Frozen
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
		bsf	vFlags,bFROZEN		;   Yepp! Freeze the clock
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

; Note: Generates Short & Long Button events for use by ProcButton; however, takes care
; of unfreezing the clock & resetting the Ticks Per Sec counter "in house".

ReadButton	Jset	PORTB,bBUTTON,NoPress	; Jump if button not pressed [grounded]

; 1. Button pressed
		tst	vButTck			; Start of button press?
		Jnz	CntPress		; Nope! Keep counting press duration
		tst	vSetPtr			; In Setting State right now?
		Jnz	CntPress		; Yepp! Start of press meaningless
		Jclr	vFlags,bFROZEN,CntPress	; If clock is not Frozen, -"-
		Movlf	cTCKPS,vSecTck		; Reset the Ticks Per Sec counter
		bcf	vFlags,bFROZEN		; Unfreeze the clock
		bsf	vFlags,bCANSHT		; Cancel Short Button event
CntPress	Cmpfl	vButTck,cLNGTCK		; Long enough for Long Button event?
		Jnz	NoLong			; Nope! Move on
		bsf	vFlags,bLONGB		; Yepp! Set the event's flag
		bsf	vFlags,bCANSHT		; Cancel Short Button event
NoLong		Cmpfl	vButTck,255		; About to max out on Button Tick?
		skipz				; Yepp! Do not increment Button Tick
		incf	vButTck,F		; Nope! Increment Button Tick
		return				; Done

; 2. Button not pressed
NoPress		tst	vButTck			; End of a button press?
		Retz				; Nope! Do nothing
		clrf	vButTck			; Yepp! Reset the Button Tick Counter
		skipset	vFlags,bCANSHT		; Short Button Event needs cancel?
		bsf	vFlags,bSHORTB		; Nope! Generate the event
		bcf	vFlags,bCANSHT		; Clear the Short Butt Event Cancel flag
		return				; Done


;------ Infamy #3: The button processing state machine

; Interprets the Short & Long Button events generated by ReadButton.

; Note: The Short & Long Button events are mutually exclusive [per definition]!

ProcButton	tst	vSetPtr			; Setting State?
		Jnz	InSetting		; Yepp! The nastier case...
		
; 1. Running State
		Jclr	vFlags,bSHORTB,RunLong	; 1.1 Short Button event
		comf	vDspMod,F		; Toggle the Display Mode
		return				; Done
		
RunLong		Retclr	vFlags,bLONGB		; 1.2 Long Button event
		Movlf	pClkMem,vSetPtr		; Setting State (vSetPrt=Clk Mem start)
		return				; Done
		
; 2. Setting State
InSetting	Jclr	vFlags,bSHORTB,SetLong	; 2.1 Short Button event
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

SetLong		Retclr	vFlags,bLONGB		; 2.2 Long Button event
		Movlf	cFSHON,vFshCtr		; Set Flash Counter to blank number
		incf	vSetPtr,F		; Move on to the next value
		Cmpfl	vSetPtr,pClkMem+6	; Moved beyond last value to set?
		Retlt				; Nope! Done
		clrf	vSetPtr			; Back to Running State
		goto	AdjustDay		; Return through adjusting the day


;==== Stop that little runaway at Runaway Bay ==========================================

		org	0x3FF
		goto	CritErr			; Execution got to this point -> OOPS!


		end
