; npclock.asm
;
; NPClock v1.2.0
; PIC16F84A Assembly Code for the World's First Nixie Propeller Clock
; (C) CV Computers, 2002 - Written by Peter Csaszar (Nebulus)

; Nixie Propeller Clock went on-line for the first time:
; 6/27/2002 (Thu), 00:30:52 CDT


;***************************************************************************
; Hardware configuration
;***************************************************************************

; Watchdog Timer:  Off
; Power On Timer:  Off
; Code Protection: Off
; Oscillator Type: HS

; I/O ports:
;
; PORTA 0 (O): Digit A (LSB)
; PORTA 1 (O): Digit B
; PORTA 2 (O): Digit C
; PORTA 3 (O): Digit D (MSB)
; PORTA 4 (O): Decimal point
;
; PORTB 0 (I): IR LED
; PORTB 1 (I): Button
; PORTB 2 (I): <Unused>
; PORTB 3 (I): <Unused>
; PORTB 4 (I): <Unused>
; PORTB 5 (I): <Unused>
; PORTB 6 (I): <Unused>
; PORTB 7 (O): Fake Cathode



;***************************************************************************
; Environment directives
;***************************************************************************

	processor 16f84a
	radix dec			; More convenient @ constant calcs
	#include <p16f84a.inc>
	errorlevel -302			; Disable msg 302 ("Not in bank 0")


;***************************************************************************
; Definitions
;***************************************************************************

;==== Constants ============================================================

; Time Magnifier (for DEBUG reasons)

cMAGCNT	equ	1			; Normal-1, Debug-64 (0.5 sec/digit)

; Customization constants

cFCLK	equ	16000000		; Clock frequency [Hz]
cFROT	equ	360			; Carousel rotation speed [RPM]
cFSCR	equ	4			; Display scroll speed [RPM]

; Geometrical constants

cRMIN	equ	50			; Innermost digit from center [mm]
cRAVG	equ	54			; Middle digit from center [mm]
cDIGWID	equ	8			; Digit width [mm]

; Timing configuration & adjustment constants

cTCKCOR	equ	24			; Second Tick correction
cTCKCO2	equ	32			; Tick Sec minor correction

cTMRPSC	equ	256			; Timer0 prescaler (Also see "####"!)
cTMRCNT	equ	256			; Timer0 required count (Just max out)
cLPCOR	equ	3			; Loop count code overhd correction
cPRXCOR	equ	70			; LED parallax correction [point]

; Calculated system constants

cTMRRLD	equ	256-cTMRCNT		; Timer0 reload value (Now unused!)
cTCKSEC	equ	cFCLK/4/cTMRPSC/cTMRCNT	; # of Ticks per sec (A little less)
cLPCNT	equ	cFCLK/400/cFROT-cLPCOR	; # of loop counts per point
cSCRGAP	equ	2000*cFSCR/cFROT	; Angle gap causing scroll [point]
cDIGWAN	equ	51			; Max angle of digit width [point]
					; 2*arctg(cDIGWID/(2*cRMIN))*1000/pi
; Point delay constants

cDIGWP	equ	cDIGWAN			; Digit Width Pause
cDIGLTN	equ	15			; Digit Light Normal
cDIGLTB	equ	25			; Digit Light Boldface
cNBP	equ	(cDIGLTB-cDIGLTN)/2	; Non-Boldface Pause
cDIGIT	equ	cDIGWP+cDIGLTB		; Total Digit width
cIDP	equ	6			; Inter-Digit Pause
cHDIGP	equ	cDIGIT/2		; Half Digit Pause
cNUMBER	equ	2*cDIGIT+cIDP		; Total Number width
cINP	equ	36			; Inter-Number Pause
cSTRING	equ	3*cNUMBER+2*cINP	; Total String width
cPRESP	equ	(1000-cSTRING)/2	; Pre-String Pause
cISP	equ	cSCRGAP			; Inter-Side Pause
cPSTSP	equ	cPRESP-cISP		; Post-String Pause
cSIDE	equ	cPRESP+cSTRING+cPSTSP	; Total Side width
cPIPTS	equ	cSIDE+cISP		; Points for pi (Should be 1000!)

; Character constants

cSPACE	equ	10			; SPACE character
bDP	equ	4			; Decimal Point Bit's #
bFLASH	equ	5			; Flashing Bit's #
bBOLD	equ	6			; Boldface Bit's #
bSKIPZ	equ	7			; Skip If Zero Bit's #

; Flag bit constants

bBRISE	equ	0			; Button Rising Edge Flag's bit#
bBFALL	equ	1			; Button Falling Edge Flag's bit#
bLED	equ	2			; IR LED Passed Flag's bit#
bSEC	equ	3			; Second Passed Flag's bit#


;==== Variables ============================================================

; Fundamental system variables

vDspMod	equ	0x0C			; Display Mode
vFlags	equ	0x0D			; System flags
vSetPtr	equ	0x0E			; Pointer to Clock var being set

; Notes:
;
; vDspMod:
;
;   0=Scrolling, 255=Stationary
;
; vFlags:
;
;   Bits: 7 6 5 4 3 2 1 0
;         - - - - S L F R
;
;         S: Second Passed Flag
;         L: IR LED Passed Flag
;         F: Button Falling Edge Flag
;         R: Button Rising Edge Flag
;
; vSetPtr:
;
;   0=Not in Set Mode, vHour..vYear=Set Mode, Clock variable being set


; Clock Memory (In display order)

vHour	equ	0x10			; Hour (00..23 [currently])
vMin	equ	0x11			; Minute (00..59)
vSec	equ	0x12			; Second (00..59)	
vMon	equ	0x13			; Month (1..12)
vDay	equ	0x14			; Day (1..)
vYear	equ	0x15			; Year (00..99) [CurrYear-2000]


; Display Buffer

; Note: MUST begin at an 8-segment

vDispl	equ	0x20			; Display Buffer (2x(1+6) bytes)

; Note:
;
; Contents: <Skipped Digits Count+1> <Digit1> ... <Digit6>
;
; Interpretation of the content of Digit<n>:
;
; Bits: 7 6 5 4 3 2 1 0
;       S B F D <-num->
;
;             S: Skip If Zero Bit
;             B: Boldface Bit
;             F: Flashing Bit
;             D: Decimal Point Bit
;       <-num->:    0-9: Number to be displayed
;                cSPACE: Space


; The Days per Month Lookup Table

vDpmLut	equ	0x30			; Largest day in month+1 (12 bytes)


; Temporary W & STATUS registers for during IT

vWTmp	equ 	0x3C
vStsTmp	equ	0x3D


; Misc. system variables

vFshSts	equ	0x40			; Char Flash Status (0-Off, 1-On)

vSecTck	equ	0x41			; Second Tick Counter (1 byte!)
vCorTck	equ	0x42			; Second Tick Correction counter
vCoTck2	equ	0x43			; Second Tick Correction counter #2
vButTck	equ	0x44			; Button Hold Tick Counter (1 byte!)
					; Note: Tick = Timer0 IT
vLpCtr	equ	0x45			; Loop counter for 1 point (pi/1000)
vMagCtr	equ	0x46			; Time Magnifier counter (for debug)
vPntCtr	equ	0x47			; Delay counter [point]


; Display-related variables

vClkPtr	equ	0x48			; Current Clock Memory pointer
vDspPtr	equ	0x49			; Current Display Buffer pointer
vCurNum	equ	0x4A			; Current number to be printed
vCurTen	equ	0x4B			; Result of division by 10
vRevDsp	equ	0x4C			; To front: Time (0) vs. Date (8)
vNixChr	equ	0x4D			; Character to be sent to the Nixie



;***************************************************************************
; Macros
;***************************************************************************

;==== Compare group ========================================================

;---- Compare register with register ----------------------------------------

; Parameters: Register1, Register2

; Compares <Register2> with <Register1>.
; Resulting flags: R1>R2:C, R1=R2:ZC, R1<R2:-

Cmpff	macro	mvReg1, mvReg2
	movf	mvReg2, W
	subwf	mvReg1, W
	endm

;---- Compare literal with register ----------------------------------------

; Parameters: Register, Literal

; Compares <Literal> with <Register>.
; Resulting flags: R>L:C, R=L:ZC, R<L:-

Cmplf	macro	mvReg, mcLit
	movlw	mcLit
	subwf	mvReg, W
	endm

;---- Compare literal with register, skip on condition ---------------------

; Parameters: Register, Literal

; Compares <Literal> with <Register>, skips next instruction on condition

Cmplfsz	macro	mvReg, mcLit		; Skip if R=L
	Cmplf	mvReg, mcLit
	btfss	STATUS, Z
	endm

Cmplfsn	macro	mvReg, mcLit		; Skip if R<>L
	Cmplf	mvReg, mcLit
	btfsc	STATUS, Z
	endm

Cmplfsl	macro	mvReg, mcLit		; Skip if R<L
	Cmplf	mvReg, mcLit
	btfsc	STATUS, C
	endm

Cmplfsg	macro	mvReg, mcLit		; Skip if R>=L
	Cmplf	mvReg, mcLit
	btfss	STATUS, C
	endm


;==== Smart incf ===========================================================

; Parameters: Register, Radix, Reset
;
; Increments <Register>; If it hasn't reached <Radix>, RETURNS from
; subroutine! Otherwise loads <Reset> into <Register> & stays in subroutine.
;

SmIncf	macro	mvReg, mcRadix, mcReset
	incf	mvReg, F		; Increment register
	Cmplfsz	mvReg, mcRadix		; Reached radix?
	return				; Nope!
	movlw	mcReset
	movwf	mvReg			; Reset register
	endm



;***************************************************************************
; The Code!
;***************************************************************************

;==== Reset vector =========================================================

	org	0x00
	goto	Start
Firmware
	data	"120"			; Firmware version in 3 bytes (Fun!)

;==== Interrupt vector =====================================================

	org	0x04
	goto	IntHdl

;==== Main code ============================================================

; HW configuration errands

Start
	bsf	STATUS, RP0
	clrf	TRISA			; Set PortA as output
	movlw	0x7f
	movwf	TRISB			; Set PortB: 0-6: input, 7: Output!
	bcf	OPTION_REG, NOT_RBPU	; Turn on PortB's weak pullups
	bcf	OPTION_REG, INTEDG	; IT on falling edge of RB0/INT
	bcf	OPTION_REG, PSA		; Prescaler to Timer0
	bsf	OPTION_REG, PS2		; Prescaler: 1:256
	bsf	OPTION_REG, PS1		; #### Note: Must reflect cTMRPSC!
	bsf	OPTION_REG, PS0
	bcf	OPTION_REG, T0CS	; Start Timer0
	bcf	STATUS, RP0

	movlw	cSPACE
	movwf	PORTA			; Blank the Nixie
	bsf	PORTB, 7		; Turn on the Fake Cathode

	movlw	cTMRRLD
	movwf	TMR0			; Load Timer0 (Super-nitpicky ;-) )

	bsf	INTCON, GIE		; Enable Global Interrupts  
	bsf	INTCON, T0IE		; Enable Timer0 Interrupt
	bsf	INTCON, INTE		; Enable RB0/INT (LED) Interrupt

; Initialize variables

	clrf	vDspMod			; Mode = Scrolling
	clrf	vFlags			; Reset all flags
	clrf	vSetPtr			; Set Mode is off

	clrf	vFshSts			; Reset the Flash Status
	movlw	cTCKSEC
	movwf	vSecTck			; Second Tick Counter
	movlw	cTCKCOR
	movwf	vCorTck			; Tick Correction
	clrf	vButTck			; Button Hold Tick Counter

	call	PreloadClk		; Preload the Clock Memory
	call	FillDpmLut		; Fill Days per Month Lookup Table

; The Main Loop

MainLoop
	btfss   vFlags, bSEC		; 1 second passed?
	goto    TestButt		; Nope!
	call	IncSec			; Increment seconds!
	bcf	vFlags, bSEC		; Event handled
TestButt
	btfss   vFlags, bBRISE		; Button pressed?
	goto    TestLed			; Nope!
	comf	vDspMod, F		; Invert Mode!
	bcf	vFlags, bBRISE		; Event handled
TestLed
	movf	vDspMod, W		; Display Mode (0 vs. 255)
	iorwf	vSetPtr, W		; Set Mode (0 vs. <255)
	btfsc	STATUS, Z		; Scrolling possible? (Not inv Z?!!)
	goto	NoLedWait		; Yepp! Don't wait for the LED
	btfss	vFlags, bLED		; LED passed?
	goto	MainLoop		; Nope!
NoLedWait
	call	ShowTime		; Show the time!
	bcf	vFlags, bLED		; Event handled
	goto	MainLoop

; Note: Resetting the event flag AFTER the corresponding action has been
;   completed is PARTICULARLY important for the LED interrupt, this way
;   mitigating the double firing problem.


;==== Subroutines ==========================================================

;---- Initialization -------------------------------------------------------

; Preload the Clock Memory

PreloadClk
	movlw	02
	movwf	vYear
	movlw	8
	movwf	vMon
	movlw	15
	movwf	vDay
	movlw	23
	movwf	vHour
	movlw	59
	movwf	vMin
	movlw	50
	movwf	vSec
	return


; Fill out the Days per Month Lookup Table

FillDpmLut
	movlw	29			; 28 days
	movwf	vDpmLut+1		;   February
	movlw	31			; 30 days
	movwf	vDpmLut+3		;   April
	movwf	vDpmLut+5		;   June
	movwf	vDpmLut+8		;   September
	movwf	vDpmLut+10		;   November
	movlw	32			; 31 days
	movwf	vDpmLut+0		;   January
	movwf	vDpmLut+2		;   March
	movwf	vDpmLut+4		;   May
	movwf	vDpmLut+6		;   July
	movwf	vDpmLut+7		;   August
	movwf	vDpmLut+9		;   October
	movwf	vDpmLut+11		;   December
	return


;---- Clock movement -------------------------------------------------------

; Increment second

IncSec
	SmIncf	vSec, 60, 0		; Increment second
	SmIncf	vMin, 60, 0		; Increment minute
	SmIncf	vHour, 24, 0		; Increment hour

	call	IncDay			; Increment day (This is NASTY!!!)
	btfss	STATUS, Z		;   Reached radix?
	return				;   Nope!
	movlw	1
	movwf	vDay			;   Reset register

	SmIncf	vMon, 13, 1		; Increment month
	incf	vYear, F		; Increment year (This one is easy!)
	return
	

; Increment day

; NOTE! Returns Z flag set upon day rollover

IncDay
	incf	vDay, F			; Increment day
	call	ChkLeapDay		; Check Leap Day
	btfsc	STATUS, Z		; Is it?
	return				; Yepp! Wow...! ;-)
	movlw	vDpmLut-1		; Lookup Table base
	addwf	vMon, W			; Displacement
	movwf	FSR			; Prepare pointer
	movf	INDF, W			; Access Days per Month LUT
	subwf	vDay, W			; Reached the limit???
	return


; Check for Leap Day

; NOTE! Returns Z flag set upon day rollover

ChkLeapDay
	movlw	0x03			; Mask 0000 0011
	andwf	vYear, W
	btfss	STATUS, Z		; Leap Year?
	return				; Nope!
	Cmplfsz	vMon, 2			; Was it february?
	return
	Cmplf	vDay, 30		; Was it the 29th?
	return
	
	
;---- Display --------------------------------------------------------------

; Show the time on the display

ShowTime
	call PrintTime
	call OutputBuff
	return


; Infamy #1: Print the contents of the Time Memory into the Display Buffer

PrintTime
					; Print the time
	movlw	vHour
	movwf	vClkPtr			; From: Time Clock Memory
	movlw	vDispl+1
	movwf	vDspPtr			; To: Time Display Buffer
	call	PrintNum
	call	PrintNum
	call	PrintNum
					; Remaining chores
	bsf	vDispl+2, bDP		; Decimal point
	bsf	vDispl+4, bDP		; Decimal point
	clrf	vDispl			; Time: Definitely no skipped digits
	incf	vDispl, F		; Inc: Needed because of dumb DECF!
	
					; Print the date
	movlw	vMon
	movwf	vClkPtr			; From: Date Clock Memory
	movlw	vDispl+9
	movwf	vDspPtr			; To: Date Display Buffer
	call	PrintNum
	call	PrintNum
	call	PrintNum
					; Remaining chores
	bsf	vDispl+9, bSKIPZ	; Mark month as Skip If Zero
	bsf	vDispl+11, bSKIPZ	; Mark day as Skip If Zero
	clrf	vDispl+8		; Date: Reset skipped digit counter
	incf	vDispl+8, F		; Inc: Needed because of dumb DECF!
	movlw	0xF
	andwf	vDispl+9, W
	btfsc	STATUS, Z		; Digit zero?
	incf	vDispl+8, F		; Yepp! Increment # of Skip If Zeros
	movlw	0xF
	andwf	vDispl+11, W
	btfsc	STATUS, Z		; Digit zero?
	incf	vDispl+8, F		; Yepp! Increment # of Skip If Zeros
	return


; Print number into the Display Buffer

; Input params: vClkPtr: Current position in the Clock Memory
;               vDspPtr: Current position in the Display Buffer
; Upon exit vClkPtr & vDspPtr point to the next position

PrintNum
	movf	vClkPtr, W		; Load the number
	movwf	FSR
	movf	INDF, W
	movwf	vCurNum			; Save the number
	clrf	vCurTen			; Reset the # of tens
	movlw	10			; Prepare to divide by 10
TenLoop
	subwf	vCurNum, F
	btfss	STATUS, C		; Still positive -> stay!
	goto	DoneDiv
	incf	vCurTen, F
	goto	TenLoop
DoneDiv
	addwf	vCurNum, F		; Tens->vCurTen, Ones->vCurNum
	movf	vDspPtr, W		; Print the tens
	movwf	FSR
	movf	vCurTen, W
	movwf	INDF
	Cmpff	vClkPtr, vSetPtr	; Clock value being set?
	btfsc	STATUS, Z		; Nope!
	bsf	INDF, bFLASH		; Make digit flash
	incf	vDspPtr, F
	movf	vDspPtr, W		; Print the ones
	movwf	FSR
	movf	vCurNum, W
	movwf	INDF
	Cmpff	vClkPtr, vSetPtr	; Clock value being set?
	btfsc	STATUS, Z		; Nope!
	bsf	INDF, bFLASH		; Make digit flash
	incf	vDspPtr, F
	incf	vClkPtr, F		; Next Clock variable, please!
	return


; Infamy #2: Output the Display Buffer's content to the Nixie

OutputBuff
	comf	vFshSts, F		; First, invert the Flash Flag
	clrf	vRevDsp			; Determine Reverse Display
	movf	vSetPtr, F
	btfsc	STATUS, Z		; Set Mode?
	goto	NoSet			; Nope! Determine via Display Mode
	Cmplfsg	vSetPtr, vMon		; Month or above being set?
	goto	DoneRev			; Nope! Leave display unreversed
	movlw	8
	movwf	vRevDsp			; Reverse display
	goto	DoneRev			; Done!
NoSet
;	btfss	vDspMod, 0		; Stationary Display Mode? @@@@@
	goto	DoneRev			; Nope! Leave display unreversed
	incf	vSec, W			; Increment: put 59->00 to front
	andlw	0x02			; Find the appropriate bit
	addwf	vRevDsp, F
	rlf	vRevDsp, F
	rlf	vRevDsp, F		; vRevDsp = 0 vs. 8
DoneRev
	btfss	vDspMod, 0		; Stationary Display Mode?
	goto	NoPrxCorr		; Nope! Skip 
	movlw	cPRXCOR			; LED Parallax Correction
	call	PtDelay
NoPrxCorr
	movlw	vDispl
	xorwf	vRevDsp, W		
	movwf	vDspPtr			; Point to the Front Side content
	call	OutputSide		; Output Front Side
	movlw	cPSTSP			; Post-String Pause
	call	PtDelay			; (Here because next may be skipd)
	movlw	cISP			; Inter-Side Pause
	call	PtDelay
	movlw	vDispl+8
	xorwf	vRevDsp, W		
	movwf	vDspPtr			; Point to the Back Side content
	call	OutputSide		; Output Back Side
	btfsc	vDspMod, 0		; Scrolling Display Mode?
	goto	NoPSPause		; Nope! Skip Post-String Pause
	movlw	cPSTSP			; Post-String Pause
	call	PtDelay
NoPSPause
	return


; Output Side (sans optional Post-String Pause)

OutputSide
	movlw	cPRESP			; Pre-String Pause
	call	PtDelay
	movf	vDspPtr, W		; Pre-String Skipped Digits Pause
	movwf	FSR			; Access the Skipped Digits Count
	movf	INDF, W			; Reuse vCurNum & vCurTen variables
	movwf	vCurTen			; Save for Post-String
	movwf	vCurNum			; Skipped digits counter
	incf	vDspPtr, F
SkipLoop1
	decf	vCurNum, F
	btfsc	STATUS, Z		; More skips?
	goto	DoneSkips1		; Nope!
	movlw	cHDIGP			; Half Digit Pause
	call	PtDelay
	goto	SkipLoop1
DoneSkips1
	call	OutputNum		; 1st number
	movlw	cINP			; Inter-Number Pause
	call	PtDelay
	call	OutputNum		; 2nd number
	movlw	cINP			; Inter-Number Pause
	call	PtDelay
	call	OutputNum		; 3rd number
	movf	vCurTen, W		; Post-String Skipped Digits Pause
	movwf	vCurNum			; Skipped digits counter
SkipLoop2
	decf	vCurNum, F
	btfsc	STATUS, Z		; More skips?
	goto	DoneSkips2		; Nope!
	movlw	cHDIGP			; Half Digit Pause
	call	PtDelay
	goto	SkipLoop2
DoneSkips2
	return


; Output Number

OutputNum
	call	OutputDig		; 1st digit
	movlw	cIDP			; Inter-Digit Pause
	call	PtDelay
	call	OutputDig		; 2nd digit
	return


; Output Digit (NASTY!!!)
	
OutputDig
	movf	vDspPtr, W		; Access the digit!
	movwf	FSR
	incf	vDspPtr, F
	btfss	INDF, bSKIPZ		; #1: Skip If Zero active?
	goto	NoSkipZero		; Nope!
	movlw	0x0F			; Digit mask
	andwf	INDF, W
	btfsc	STATUS, Z		; Digit is nonzero?
	return				; Nope! I'm all done here!
NoSkipZero
	movf	INDF, W
	andlw	0x1F
	movwf	vNixChr			; Copy lower 5 bits to Nixie Chr
	btfss	INDF, bFLASH		; #2: Character flashing?
	goto	CharOn			; Nope! Regular lighting routine
	btfsc	vFshSts, 0		; Flash Status is "Off"?
	goto 	CharOn			; Nope! Regular lighting routine
	movlw	cNBP			; Non-Boldface Pause
	call	PtDelay
	goto	SkipLite		; Skip lighting!
CharOn
	btfss	INDF, bBOLD		; #3: Boldface?
	goto	NoBold			; Nope! Wait with lighting
	movf	vNixChr, W
	movwf	PORTA			; Light the Nixie (Boldface)!
	bcf	PORTB, 7		; Turn off the Fake Cathode
NoBold
	movlw	cNBP			; Non-Boldface Pause
	call	PtDelay

	movf	vNixChr, W
	movwf	PORTA			; Light the Nixie (non-Boldface)!
	bcf	PORTB, 7		; Turn off the Fake Cathode
SkipLite
	movlw	cDIGLTN			; Digit Light Normal
	call	PtDelay

	btfsc	INDF, bBOLD		; #3: Boldface?
	goto	YesBold			; Yepp! Wait with unlighting
	movlw	cSPACE
	movwf	PORTA			; Unlight the Nixie!
	bsf	PORTB, 7		; Turn on the Fake Cathode
YesBold
	movlw	cNBP			; Non-Boldface Pause
	call	PtDelay

	movlw	cSPACE
	movwf	PORTA			; Unlight the Nixie (Boldface)!
	bsf	PORTB, 7		; Turn on the Fake Cathode
	movlw	cDIGWP			; Digit Width Pause
	call	PtDelay
	
	return				; Done! YIPPEE!


; Generate delay corresponding to <Point> points (Pi/1000) of carousel
; revolution

; Input param: W: Number of points to delay

PtDelay
	movwf	vPntCtr			; Load number of points
OuterLoop
	movlw	cMAGCNT			; Load the Time Magnifier (Debug)
	movwf	vMagCtr
MagniLoop
	movlw	cLPCNT
	movwf	vLpCtr			; Load the delay for 1 point
InnerLoop
	decfsz	vLpCtr, F		; 1 point passed yet?
	goto	InnerLoop		; Nope!
	decfsz	vMagCtr, F		; Magnification done yet?
	goto	MagniLoop		; Nope!
	decfsz	vPntCtr, F		; Point delay passed yet?
	goto	OuterLoop		; Nope!
	return


;==== Interrupt Handler ====================================================

IntHdl
	btfss	INTCON, INTF		; Is it an RB0/INT (LED) IT?
	goto	TimerInt		; Nope!
	bsf	vFlags, bLED		; LED passed!
	bcf	INTCON, INTF		; Clear the LED IT flag
	retfie

TimerInt
	btfss	INTCON, T0IF		; Is it a Timer0 IT?
	retfie				; No other ITs expected
	movwf	vWTmp			; Save W & STATUS
	movf	STATUS, W
	movwf	vStsTmp
;	movlw	cTMRRLD			; Reload Timer0 w/ appropriate value
;	movwf	TMR0			; (Uncomment if cTMRRLD is not 0!)
;	decfsz	vCorTck, F		; Correction triggers? @@@@@
;	goto	KeepTick		; Nope! Go for the Tick
;	movlw	cTCKCOR
;	movwf	vCorTck			; Reload the Tick Correction value
;	goto	ChkButt			; Drop the Tick
;KeepTick
	decfsz	vSecTck, F		; Reached zero?
	goto	ChkButt			; Nope!
	bsf	vFlags, bSEC		; Second passed!
	movlw	cTCKSEC
	movwf	vSecTck			; Reload the Ticks per sec value
	decfsz	vCorTck, F		; Is it gonna be a "leap second?"
	goto	ChkButt			; Nope! Move on
	incf	vSecTck, F		; Leap the second (uncomment one)
;;;	decf	vSecTck, F		; De-Leap the second (uncomment one)
	movlw	cTCKCOR
	movwf	vCorTck			; Reload the Tick Correction value
ChkButt					; Also handle the button here
	btfsc	PORTB, 1		; Is the button pressed [grounded]?
	goto	NoPress			; Nope!
	movf	vButTck, F
	btfsc	STATUS, Z		; Beginning of button press?
	bsf	vFlags, bBRISE		; Yepp! Indicate button rising edge
	Cmplfsz	vButTck, 255		; About to max out on Button Tick?
	incf	vButTck, F		; Nope! Increment Button Tick
	goto	DoneTmInt		; Timer0 IT done!
NoPress
	movf	vButTck, F
	btfss	STATUS, Z		; End of button press?
	bsf	vFlags, bBFALL		; Yepp! Indicate button falling edge
	clrf	vButTck			; Reset Button Tick 
DoneTmInt
	bcf	INTCON, T0IF		; Clear the Timer0 IT flag
	movf	vStsTmp, W		; Restore W & STATUS
	movwf	STATUS
	movf	vWTmp, W
	retfie

	end

