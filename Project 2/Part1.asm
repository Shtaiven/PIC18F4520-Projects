;;;;;;; Part1 for QwikFlash board ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Use 10 MHz crystal frequency.
; Use Timer0 for ten millisecond looptime.
; Blink "Alive" LED every two and a half seconds.
; Display PORTD as a binary number.
; Toggle C2 output every ten milliseconds for measuring looptime precisely.
;
;;;;;;; Program hierarchy ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Mainline
;   Initial
;     InitLCD
;       LoopTime
;   BlinkAlive
;   ByteDisplay (DISPF macro)
;     DisplayC
;       T40
;     DisplayV
;       T40
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

        cblock  0x000                  ;Beginning of Access RAM
        TMR0LCOPY                      ;Copy of sixteen-bit Timer0 used by LoopTime
        TMR0HCOPY
        INTCONCOPY                     ;Copy of INTCON for LoopTime subroutine
        COUNT                          ;Counter available as local to subroutines
        ALIVECNT                       ;Counter for blinking "Alive" LED
        BYTE                           ;Eight-bit byte to be displayed
        BYTESTR:10                     ;Display string for binary version of BYTE
        endc

;;;;;;; Macro definitions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MOVLF   macro  literal,dest
        movlw  literal
        movwf  dest
        endm

POINT   macro  stringname
        MOVLF  high stringname, TBLPTRH
        MOVLF  low stringname, TBLPTRL
        endm

DISPF	macro  register
        movff  register,BYTE		
        call  ByteDisplay
        endm

DISPL   macro literal
		MOVLF literal,BYTE
		call ByteDisplay
		endm

;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        org  0x0000                    ;Reset vector
        nop 
        goto  Mainline

        org  0x0008                    ;High priority interrupt vector
        goto  $                        ;Trap

        org  0x0018                    ;Low priority interrupt vector
        goto  $                        ;Trap

;;;;;;; Mainline program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Mainline
        rcall  Initial                 ;Initialize everything
        ;LOOP_
L1
		  rcall ADconv    			  ;Convert analog input from port E2
          DISPF  ADRESH               ;Display PORTD as a binary number
        ;ENDLOOP_
        bra	L1
PL1

;;;;;;; Initial subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs all initializations of variables and registers.

Initial
		MOVLF  B'00011111',ADCON0
        MOVLF  B'10001110',ADCON1      ;Enable PORTA & PORTE digital I/O pins
		MOVLF  B'01000111',ADCON2

        MOVLF  B'11100001',TRISA       ;Set I/O for PORTA
        MOVLF  B'11011100',TRISB       ;Set I/O for PORTB
        MOVLF  B'11010000',TRISC       ;Set I/0 for PORTC
        MOVLF  B'00001111',TRISD       ;Set I/O for PORTD
        MOVLF  B'00000100',TRISE       ;Set I/O for PORTE
        MOVLF  B'10001000',T0CON       ;Set up Timer0 for a looptime of 10 ms
        MOVLF  B'00010000',PORTA       ;Turn off all four LEDs driven from PORTA
        rcall  InitLCD
        return

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

;;;;;;; BlinkAlive subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine briefly blinks the LED next to the PIC every two-and-a-half
; seconds.

BlinkAlive
        bsf  PORTA,RA4                 ;Turn off LED
        decf  ALIVECNT,F               ;Decrement loop counter and return if not zero
        ;IF_  .Z.
        bnz	L8
          MOVLF  250,ALIVECNT          ;Reinitialize BLNKCNT
          bcf  PORTA,RA4               ;Turn on LED for ten milliseconds every 2.5 sec
        ;ENDIF_
L8
        return

;;;;;;; LoopTime subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine waits for Timer0 to complete its ten millisecond count
; sequence. It does so by waiting for sixteen-bit Timer0 to roll over. To obtain
; a period of precisely 10000/0.4 = 25000 clock periods, it needs to remove
; 65536-25000 or 40536 counts from the sixteen-bit count sequence.  The
; algorithm below first copies Timer0 to RAM, adds "Bignum" to the copy ,and
; then writes the result back to Timer0. It actually needs to add somewhat more
; counts to Timer0 than 40536.  The extra number of 12+2 counts added into
; "Bignum" makes the precise correction.

Bignum  equ     65536-25000+12+2

LoopTime
        ;REPEAT_
L9
        ;UNTIL_  INTCON,TMR0IF == 1    ;Wait until ten milliseconds are up
        btfss INTCON,TMR0IF
        bra	L9
RL9
        movff  INTCON,INTCONCOPY       ;Disable all interrupts to CPU
        bcf  INTCON,GIEH
        movff  TMR0L,TMR0LCOPY         ;Read 16-bit counter at this moment
        movff  TMR0H,TMR0HCOPY
        movlw  low  Bignum
        addwf  TMR0LCOPY,F
        movlw  high  Bignum
        addwfc  TMR0HCOPY,F
        movff  TMR0HCOPY,TMR0H
        movff  TMR0LCOPY,TMR0L         ;Write 16-bit counter at this moment
        movf  INTCONCOPY,W             ;Restore GIEH interrupt enable bit
        andlw  B'10000000'
        iorwf  INTCON,F
        bcf  INTCON,TMR0IF             ;Clear Timer0 flag
        return

;;;;;;; ByteDisplay subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Display whatever is in BYTE as a binary number.

ByteDisplay
        POINT  BYTE_1                  ;Display "BYTE="
        rcall  DisplayC
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

;AD conversion code
ADconv		  		
		  bsf  ADCON0,1			   ;Start ADC
		  ADCloop
		  btfsc  ADCON0,1			   ;Check if ADC done
		  bra  ADCloop
		return

;;;;;;; Constant strings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

LCDstr  db  0x33,0x32,0x28,0x01,0x0c,0x06,0x00  ;Initialization string for LCD
BYTE_1  db  "\x80BYTE=   \x00"         ;Write "BYTE=" to first line of LCD
BarChars                               ;Bargraph user-defined characters
        db  0x00,0x48                  ;CGRAM-positioning code
        db  0x90,0x90,0x90,0x90,0x90,0x90,0x90,0x90  ;Column 1
        db  0x98,0x98,0x98,0x98,0x98,0x98,0x98,0x98  ;Columns 1,2
        db  0x9c,0x9c,0x9c,0x9c,0x9c,0x9c,0x9c,0x9c  ;Columns 1,2,3
        db  0x9e,0x9e,0x9e,0x9e,0x9e,0x9e,0x9e,0x9e  ;Columns 1,2,3,4
        db  0x9f,0x9f,0x9f,0x9f,0x9f,0x9f,0x9f,0x9f  ;Column 1,2,3,4,5
        db  0x00                       ;End-of-string terminator

        end
