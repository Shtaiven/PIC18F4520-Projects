;;;;;;; IntTest for QwikFlash board ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Generate a 41ms half cycle wave (E2).
; Run an LED counting sequence on low priority interrupt (INT1/B1).
; Display a lock on the LCD on a high priority interrupt (INT2/B2).
;
;;;;;;; Program hierarchy ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Mainline
;   Initial
;   LoopTime
;
;;;;;;; Assembler directives ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        list  P=PIC18F4520, F=INHX32, C=160, N=0, ST=OFF, MM=OFF, R=DEC, X=ON
        #include <P18F4520.inc>
        __CONFIG  _CONFIG1H, _OSC_HS_1H  ;HS oscillator
        __CONFIG  _CONFIG2L, _PWRT_ON_2L & _BOREN_ON_2L & _BORV_2_2L  ;Reset
        __CONFIG  _CONFIG2H, _WDT_OFF_2H  ;Watchdog timer disabled
        __CONFIG  _CONFIG3H, _CCP2MX_PORTC_3H  ;CCP2 to RC1 (rather than to RB3)
        __CONFIG  _CONFIG4L, _LVP_OFF_4L & _XINST_OFF_4L  ;RB5 enabled for I/O
        errorlevel -314, -315          ;Ignore lfsr messages

;;;;;;; Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        cblock  0x000           ;Beginning of Access RAM
        TMR0LCOPY               ;Copy of sixteen-bit Timer0 used by LoopTime
        TMR0HCOPY
        INTCONCOPY              ;Copy of INTCON for LoopTime subroutine
		WREGCOPY				;Copies of registers used by different parts of the program
		STATUSCOPY
		PORTACOPY
		PORTDCOPY
		ADCON0COPY
		TIMECOUNT				;Used to count timer iterations in Delay1s
		COUNT					;Used to count timer iterations in InitLCD
		BYTE                    ;Eight-bit byte to be displayed
        BYTESTR:10              ;Display string for binary version of BYTE
        endc

;;;;;;; Macro definitions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MOVLF   macro  literal,dest
        movlw  literal			;move literal value to WREG
        movwf  dest				;move WREG to f= dest, which is specified by user
        endm

POINT   macro  stringname
        MOVLF  high stringname, TBLPTRH
        MOVLF  low stringname, TBLPTRL
        endm

DISPLAY	macro  register
        movff  register,BYTE		
        call  ByteDisplay
        endm

;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        org  0x0000             ;Reset vector, READ Section 5.7
        nop
        goto  Mainline			;goes to Mainline; thus skipping the interrupts below

        org  0x0008             ;High priority interrupt vector
        goto  HPaction          

        org  0x0018             ;Low priority interrupt vector
        goto  LPaction

;;;;;;; Mainline program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Mainline
        rcall  Initial          ;Initialize everything
Loop
		btg  PORTE,RE2			;Toggle port to measure 41ms
        rcall  LoopTime         ;Make looptime be ten milliseconds
		rcall  LoopTime
        bra  Loop

;;;;;;; Initial subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs all initializations of variables and registers.

Initial

		bsf RCON,IPEN				   ;Enable HP/LP interrupt structure		
		bsf  INTCON2,INTEDG1
		bsf  INTCON2,INTEDG2
		MOVLF  B'10011000',INTCON3	   ;Enable INT1 and INT2 and set as low and high priority respectively
		bsf  INTCON,GIEH			   ;Enable high priority interrupts
		bsf  INTCON,GIEL			   ;Enable low priority interrupts

		MOVLF  B'00010001',ADCON0      ;Convert analog input to digital from POT1
        MOVLF  B'10001110',ADCON1      ;Enable PORTA & PORTE digital I/O pins
		MOVLF  B'01000100',ADCON2	   ;ADRES left justified clock = Fosc/4 (100)

        MOVLF  B'11100001',TRISA 	   ;Set I/O for PORTA 0 = output, 1 = input
        MOVLF  B'11011111',TRISB 	   ;Set I/O for PORTB (B0, B1, B2 must be input for interrupts)
        MOVLF  B'11010000',TRISC 	   ;Set I/O for PORTC
        MOVLF  B'00001011',TRISD 	   ;Set I/O for PORTD
        MOVLF  B'00000000',TRISE 	   ;Set I/O for PORTE
        MOVLF  B'10001000',T0CON 	   ;Set up Timer0 for a looptime of 10 ms;  bit7=1 enables timer; bit3=1 bypass prescaler
        MOVLF  B'00010000',PORTA 	   ;Turn off all four LEDs driven from PORTA ; See pin diagrams of Page 5 in DataSheet
		MOVLF  B'00000000',PORTB
		rcall InitLCD        
		return	

;;;;;;; LoopTime subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine waits for Timer0 to complete its ten millisecond count
; sequence. It does so by waiting for sixteen-bit Timer0 to roll over. To obtain
; a period of precisely 20500/0.4 = 51250 clock periods, it needs to remove
; 65536-51250 or 14286 counts from the sixteen-bit count sequence.  The
; algorithm below first copies Timer0 to RAM, adds "Bignum" to the copy ,and
; then writes the result back to Timer0. It actually needs to add somewhat more
; counts to Timer0 than 14286.  The extra number of 12+2 counts added into
; "Bignum" makes the precise correction.

Bignum  equ     65536-51250+12+2

LoopTime
        btfss  INTCON,TMR0IF    ;Wait until ten milliseconds are up OR check if bit TMR0IF of INTCON == 1, skip next line if true
        bra  LoopTime
        movff  INTCON,INTCONCOPY  ;Disable all interrupts to CPU
        bcf  INTCON,GIEH
        movff  TMR0L,TMR0LCOPY  ;Read 16-bit counter at this moment
        movff  TMR0H,TMR0HCOPY
        movlw  low  Bignum
        addwf  TMR0LCOPY,F
        movlw  high  Bignum
        addwfc  TMR0HCOPY,F
        movff  TMR0HCOPY,TMR0H
        movff  TMR0LCOPY,TMR0L  ;Write 16-bit counter at this moment
        movf  INTCONCOPY,W      ;Restore GIEH interrupt enable bit
        andlw  B'10000000'
        iorwf  INTCON,F
        bcf  INTCON,TMR0IF      ;Clear Timer0 flag
        return

;;;;;;; Delay10ms subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Delay for 10 milliseconds. Works similarly to LoopTime.

Bignum2  equ     65536-25000+12+2

Delay10ms
        btfss  INTCON,TMR0IF    ;Wait until ten milliseconds are up OR check if bit TMR0IF of INTCON == 1, skip next line if true
        bra  Delay10ms
        movff  INTCON,INTCONCOPY  ;Disable all interrupts to CPU
        bcf  INTCON,GIEH
        movff  TMR0L,TMR0LCOPY  ;Read 16-bit counter at this moment
        movff  TMR0H,TMR0HCOPY
        movlw  low  Bignum2
        addwf  TMR0LCOPY,F
        movlw  high  Bignum2
        addwfc  TMR0HCOPY,F
        movff  TMR0HCOPY,TMR0H
        movff  TMR0LCOPY,TMR0L  ;Write 16-bit counter at this moment
        movf  INTCONCOPY,W      ;Restore GIEH interrupt enable bit
        andlw  B'10000000'
        iorwf  INTCON,F
        bcf  INTCON,TMR0IF      ;Clear Timer0 flag
        return

	Delay1s	
		MOVLF 100,TIMECOUNT
	DelayLoop		
		rcall  Delay10ms
		decf  TIMECOUNT
		bnz  DelayLoop
		return

;;;;;;; ADconv subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Convert Analog signal to Digital

ADconv		  		
		bsf  ADCON0,1			   ;Start ADC
		ADCloop
		btfsc  ADCON0,1			   ;Check if ADC done
		bra  ADCloop
		return

;;;;;;; Interrupt subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LPaction
	movff  WREG,WREGCOPY		;Save registers used by other parts of the program
	movff  STATUS,STATUSCOPY

	bcf  PORTE,RE2			    ;Stop pulse train

	bcf  PORTA,RA3
	bcf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bcf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bsf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bsf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bcf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bcf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bsf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bsf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bsf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bcf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bcf  PORTA,RA2
	bsf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bsf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bsf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bsf  PORTA,RA3
	bcf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	bcf  PORTA,RA3
	bcf  PORTA,RA2
	bcf  PORTA,RA1
	rcall Delay1s

	movff  WREGCOPY,WREG		;Restore registers used by other parts of the program
	movff  STATUSCOPY,STATUS
	
	bcf  INTCON3,INT1IF			;Allow INT1 interrupts to occur
	retfie

HPaction	
	movff  PORTA,PORTACOPY		;Save registers used by other parts of the program
	movff  ADCON0,ADCON0COPY
	

	bcf  PORTE,RE2				;Stop pulse train

	bcf  PORTA,RA3				;Turn all LEDs off
	bcf  PORTA,RA2
	bcf  PORTA,RA1

	POINT  TESTING				;Display "Testing:" on LCD
	rcall  DisplayC
HPloop
	rcall  ADconv				;Run AD conversion
	DISPLAY  ADRESH				;Output ADRESH to LCD	
	movlw  B'10101010'			;Check if unlocked
	cpfseq  ADRESH
	bra  HPloop					;Exit if unlocked

	POINT  UNLOCKED				;Display "UNLOCKED" on LCD
	rcall  DisplayC
	POINT  LCDclear2		
	rcall  DisplayC

	rcall  Delay1s				;Wait 3 seconds
	rcall  Delay1s
	rcall  Delay1s

	POINT  LCDclear1			;Clear the LCD		
	rcall  DisplayC	
	POINT  LCDclear2		
	rcall  DisplayC

	
	movff  PORTACOPY,PORTA		;Restore registers used by other parts of the program
	movff  ADCON0COPY,ADCON0

	bcf  INTCON3,INT2IF		  	;Allow INT2 interrupts to occur
	retfie FAST

;;;;;;; InitLCD subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Initialize the Optrex 8x2 character LCD.
; First wait for 0.1 second, to get past display's power-on reset time.

InitLCD
        MOVLF  10,COUNT                ;Wait 0.1 second
        ;REPEAT_
L2
          rcall  LoopTime              ;Call LoopTime 10 times
          decf  COUNT,F
        ;UNTIL_  .Z.
        bnz	L2
RL2

        bcf  PORTE,0                   ;RS=0 for command
        POINT  LCDstr                  ;Set up table pointer to initialization string
        tblrd*                         ;Get first byte from string into TABLAT
        ;REPEAT_
L3
          bsf  PORTE,1                 ;Drive E high
          movff  TABLAT,PORTD          ;Send upper nibble
          bcf  PORTE,1                 ;Drive E low so LCD will process input
          rcall  LoopTime              ;Wait ten milliseconds
          bsf  PORTE,1                 ;Drive E high
          swapf  TABLAT,W              ;Swap nibbles
          movwf  PORTD                 ;Send lower nibble
          bcf  PORTE,1                 ;Drive E low so LCD will process input
          rcall  LoopTime              ;Wait ten milliseconds
          tblrd+*                      ;Increment pointer and get next byte
          movf  TABLAT,F               ;Is it zero?
        ;UNTIL_  .Z.
        bnz	L3
RL3
        return

;;;;;;; T40 subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Pause for 40 microseconds  or 40/0.4 = 100 clock cycles.
; Assumes 10/4 = 2.5 MHz internal clock rate.

T40
        movlw  100/3                   ;Each REPEAT loop takes 3 cycles
        movwf  COUNT
        ;REPEAT_
L4
          decf  COUNT,F
        ;UNTIL_  .Z.
        bnz	L4
RL4
        return

;;;;;;;;DisplayC subroutine;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine is called with TBLPTR containing the address of a constant
; display string.  It sends the bytes of the string to the LCD.  The first
; byte sets the cursor position.  The remaining bytes are displayed, beginning
; at that position.
; This subroutine expects a normal one-byte cursor-positioning code, 0xhh, or
; an occasionally used two-byte cursor-positioning code of the form 0x00hh.

DisplayC
        bcf  PORTE,0                   ;Drive RS pin low for cursor-positioning code
        tblrd*                         ;Get byte from string into TABLAT
        movf  TABLAT,F                 ;Check for leading zero byte
        ;IF_  .Z.
        bnz	L5
          tblrd+*                      ;If zero, get next byte
        ;ENDIF_
L5
        ;REPEAT_
L6
          bsf  PORTE,1                 ;Drive E pin high
          movff  TABLAT,PORTD          ;Send upper nibble
          bcf  PORTE,1                 ;Drive E pin low so LCD will accept nibble
          bsf  PORTE,1                 ;Drive E pin high again
          swapf  TABLAT,W              ;Swap nibbles
          movwf  PORTD                 ;Write lower nibble
          bcf  PORTE,1                 ;Drive E pin low so LCD will process byte
          rcall  T40                   ;Wait 40 usec
          bsf  PORTE,0                 ;Drive RS pin high for displayable characters
          tblrd+*                      ;Increment pointer, then get next byte
          movf  TABLAT,F               ;Is it zero?
        ;UNTIL_  .Z.
        bnz	L6
RL6
        return

;;;;;;; DisplayV subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine is called with FSR0 containing the address of a variable
; display string.  It sends the bytes of the string to the LCD.  The first
; byte sets the cursor position.  The remaining bytes are displayed, beginning
; at that position.

DisplayV
        bcf  PORTE,0                   ;Drive RS pin low for cursor positioning code
        ;REPEAT_
L7
          bsf  PORTE,1                 ;Drive E pin high
          movff  INDF0,PORTD           ;Send upper nibble
          bcf  PORTE,1                 ;Drive E pin low so LCD will accept nibble
          bsf  PORTE,1                 ;Drive E pin high again
          swapf  INDF0,W               ;Swap nibbles
          movwf  PORTD                 ;Write lower nibble
          bcf  PORTE,1                 ;Drive E pin low so LCD will process byte
          rcall  T40                   ;Wait 40 usec
          bsf  PORTE,0                 ;Drive RS pin high for displayable characters
          movf  PREINC0,W              ;Increment pointer, then get next byte
        ;UNTIL_  .Z.                   ;Is it zero?
        bnz	L7
RL7
        return

;;;;;;; ByteDisplay subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Display whatever is in BYTE as a binary number.

ByteDisplay
        lfsr  0,BYTESTR+8
        ;REPEAT_
L10
          clrf  WREG
          rrcf  BYTE,F                 ;Move bit into carry
          rlcf  WREG,F                 ;and from there into WREG
          iorlw  0x30                  ;Convert to ASCII
          movwf  POSTDEC0              ; and move to string
          movf  FSR0L,W                ;Done?
          sublw  low BYTESTR
        ;UNTIL_  .Z.
        bnz	L10
RL10

        lfsr  0,BYTESTR                ;Set pointer to display string
        MOVLF  0xc0,BYTESTR            ;Add cursor-positioning code
        clrf  BYTESTR+9                ;and end-of-string terminator
        rcall  DisplayV

		return

;;;;;;; Constant strings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LCDstr   db  0x33,0x32,0x28,0x01,0x0c,0x06,0x00  ;Initialization string for LCD
TESTING  db  "\x80TESTING:\x00"         ;Write "TESTING:" to first line of LCD
UNLOCKED db  "\x80UNLOCKED\x00"			;Write "UNLOCKED" to first line of LCD
LCDclear1 db  "\x80        \x00"			;Write "        " to second line of LCD
LCDclear2 db  "\xc0        \x00"			;Write "        " to second line of LCD


end

