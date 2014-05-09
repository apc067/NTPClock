; MyPICMacros.inc
;
; Library of useful macros for the Microchip PIC [particularly PIC16*] microcontrollers
;
; (C) Peter Csaszar - http://www.nixiana.com


; Important note! Care must be taken when using macros after "btfs?" instructions (now
; represented as macros themselves under the name of "skip*"). These instructions skip
; the subsequent 1 instruction, which is a hotbed of extremely elusive bugs when macros
; are involved. The ONLY macros that can follow a "skip*" are the macros consisting of
; only a single instruction (essentially, simple aliasing macros). In this file, these
; particular macros are all lower-case; all other macros are capitalized.


;==== 1. Skip group ====================================================================

; These macros are nothing else than the different skip instructions in more edible form

;---- Skip on bit set / clear ----------------------------------------------------------

; Parameters: Register, Bit

skipset		macro	mvReg,mbBit
		btfss	mvReg,mbBit
		endm

skipclr		macro	mvReg,mbBit
		btfsc	mvReg,mbBit
		endm

;---- Skip on zero / non-zero / carry / no carry ---------------------------------------

; Parameters: None

skipz		macro
		skipset	STATUS,Z		; = btfss STATUS,Z
		endm
	
skipnz		macro	
		skipclr	STATUS,Z		; = btfsc STATUS,Z
		endm
	
skipc		macro
		skipset	STATUS,C		; = btfss STATUS,C
		endm
	
skipnc		macro
		skipclr	STATUS,C		; = btfsc STATUS,C
		endm
	
skiplt		macro				; Skip if less than
		skipnc
		endm

skipge		macro				; Skip if greater than or equal
		skipc
		endm


;==== 2. Conditional jump group ========================================================

;---- Jump on bit set / clear ----------------------------------------------------------

; Parameters: Register, Bit, Label

Jset		macro	mvReg,mbBit,mlLabel
		skipclr	mvReg,mbBit
		goto	mlLabel
		endm

Jclr		macro	mvReg,mbBit,mlLabel
		skipset	mvReg,mbBit
		goto	mlLabel
		endm

;---- Jump on zero / non-zero / carry / no carry ---------------------------------------

; Parameters: Label

Jz		macro	mlLabel
		skipnz
		goto	mlLabel
		endm

Jnz		macro	mlLabel
		skipz
		goto	mlLabel
		endm

Jc		macro	mlLabel
		skipnc
		goto	mlLabel
		endm

Jnc		macro	mlLabel
		skipc
		goto	mlLabel
		endm
	
Jlt		macro	mlLabel			; Jump if less than
		Jnc	mlLabel
		endm

Jge		macro	mlLabel			; Jump if greater than or equal
		Jc	mlLabel
		endm

;---- Decrement & jump on non-zero -----------------------------------------------------

; A good ole friend from the bygone Z80 days

; Parameters: Register, Label

Djnz		macro	mvReg,mlLabel
		decfsz	mvReg,F
		goto	mlLabel
		endm


;==== 3. Conditional return group ======================================================

;---- Return on bit set / clear --------------------------------------------------------

; Parameters: Register, Bit

Retset		macro	mvReg,mbBit
		skipclr	mvReg,mbBit
		return
		endm

Retclr		macro	mvReg,mbBit
		skipset	mvReg,mbBit
		return
		endm

;---- Return on zero / non-zero / carry / no carry -------------------------------------

; Parameters: None

Retz		macro
		skipnz
		return
		endm
	
Retnz		macro
		skipz
		return
		endm
	
Retc		macro
		skipnc
		return
		endm
	
Retnc		macro
		skipc
		return
		endm

Retlt		macro				; Return if less than
		Retnc
		endm

Retge		macro				; Return if greater than or equal
		Retc
		endm


;==== 4. Data transfer group ===========================================================

; ATTENTION! In these macros, the destination operand comes last, following the Motorola
; tradition, and also the convention suggested by most PIC mnemonics.
;
; WARNING: These macros destroy the W register

;---- Move register to register --------------------------------------------------------

; Parameters: Register1, Register2
;
; Operation: Reg2 = Reg1

Movff		macro	mvReg1,mvReg2
		movf	mvReg1,W
		movwf	mvReg2
		endm

;---- Move literal to register ---------------------------------------------------------

; Parameters: Literal, Register
;
; Operation: Reg = Lit

Movlf		macro	mcLit,mvReg
		movlw	mcLit
		movwf	mvReg
		endm


;==== 5. Compare group =================================================================

; ATTENTION! In these macros, the "destination" operand [i.e., the first operand of the
; equivalent subtraction] comes first, so that the order of operands matches that of
; the actual mathematical comparisons. (In this way it is MUCH less confusing.)
;
; WARNING: These macros (except tst) destroy the W register

;---- Compare register to W ------------------------------------------------------------

; Parameters: Register
;
; Operation: Reg ? W
;
; Resulting flags: C:Reg>=W, Z:Reg=W
; WARNING: Reverse Carry behavior for sub*

cmpfw		macro	mvReg
		subwf	mvReg,W
		endm
		
		
;---- Compare two registers ------------------------------------------------------------

; Parameters: Register1, Register2
;
; Operation: Reg1 ? Reg2
;
; Resulting flags: C:Reg1>=Reg2, Z:Reg1=Reg2
; WARNING: Reverse Carry behavior for sub*

Cmpff		macro	mvReg1,mvReg2
		movf	mvReg2,W
		cmpfw	mvReg1
		endm

;---- Compare register to literal ------------------------------------------------------

; Parameters: Register, Literal
;
; Operation: Reg ? Lit
;
; Resulting flags: C:Reg>=Lit, Z:Reg=Lit
; WARNING: Reverse Carry behavior for sub*

Cmpfl		macro	mvReg,mcLit
		movlw	mcLit
		cmpfw	mvReg
		endm

;---- Test if register is 0 ------------------------------------------------------------

; Parameters: Register
;
; Operation: Reg ? 0
;
; Resulting flags: Z:Reg=0
; Note: The C flag remains unaffected

tst		macro	mvReg
		movf	mvReg,F
		endm
