;;;;;;; 41ms for QwikFlash board ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Use 10 MHz crystal frequency.
; Use Timer0 for 20.5 millisecond looptime.
; Blink LED D5 every 41 milliseconds.
; Toggle C2 output every 41 milliseconds.
;
;;;;;;; Program hierarchy ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Mainline
;   Initial
;   BlinkAlive
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
	SKIPCOUNT		;Skip every other clock cycle
        endc

;;;;;;; Macro definitions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MOVLF   macro  literal,dest
        movlw  literal			;move literal value to WREG
        movwf  dest				;move WREG to f= dest, which is specified by user
        endm

;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        org  0x0000             ;Reset vector, READ Section 5.7
        nop
        goto  Mainline			;goes to Mainline; thus skipping the interrupts below

        org  0x0008             ;High priority interrupt vector
        goto  $                 ;Trap

        org  0x0018             ;Low priority interrupt vector
        goto  $                 ;Trap

;;;;;;; Mainline program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Mainline
        rcall  Initial          ;Initialize everything
Loop
        rcall  BlinkAlive       ;Blink "Alive" LED
        rcall  LoopTime         ;Make looptime be ten milliseconds
        bra  Loop

;;;;;;; Initial subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs all initializations of variables and registers.

Initial
        MOVLF  B'10001110',ADCON1 ;Enable PORTA & PORTE digital I/O pins
        MOVLF  B'11100001',TRISA  ;Set I/O for PORTA 0 = output, 1 = input
        MOVLF  B'11011100',TRISB  ;Set I/O for PORTB
        MOVLF  B'11010000',TRISC  ;Set I/0 for PORTC
        MOVLF  B'00001111',TRISD  ;Set I/O for PORTD
        MOVLF  B'00000000',TRISE  ;Set I/O for PORTE
        MOVLF  B'10001000',T0CON  ;Set up Timer0 for a looptime of 10 ms;  bit7=1 enables timer; bit3=1 bypass prescaler
        MOVLF  B'00010000',PORTA  ;Turn off all four LEDs driven from PORTA ; See pin diagrams of Page 5 in DataSheet
        return

;;;;;;; LoopTime subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine waits for Timer0 to complete its 20.5 millisecond count
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

;;;;;;; BlinkAlive subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine toggles pin C2 and LED D5 after every other LoopTime.

BlinkAlive
		decf SKIPCOUNT,F        ;Decrement SKIPCOUNT by 1
		bnz BAend               ;Return if SKIPCOUNT != 0
		MOVLF 2,SKIPCOUNT	;Reinitialize counter
                btg  PORTA,RA2          ;Turn on LED D5
		btg  PORTC,RC2          ;Toggle pin C2
BAend
		return

		end
