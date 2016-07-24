;;;;;;; Part3 for QwikFlash board ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
		TWOBITS
		TOPBITS:4					   ;Display string for top 2 bits of LCD
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
        rcall ADconv
	    rcall DAconv
        ;ENDLOOP_
        bra	L1
PL1

;;;;;;; Initial subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs all initializations of variables and registers.

Initial
		MOVLF  B'11000000',SSPSTAT	   ;use rising clock edge for loading buffer bits into output
		MOVLF  B'00100000',SSPCON1	   ;Enable SPI and output at rate of Fosc/4 (0000)

		
		MOVLF  B'00011101',ADCON0      ;Convert analog input to digital from port E2
        MOVLF  B'10001110',ADCON1      ;Enable PORTA & PORTE digital I/O pins
		MOVLF  B'01000100',ADCON2	   ;ADRES left justified clock = Fosc/4 (100)

        MOVLF  B'11100001',TRISA       ;Set I/O for PORTA
        MOVLF  B'11011100',TRISB       ;Set I/O for PORTB
        MOVLF  B'11000000',TRISC       ;Set I/0 for PORTC
        MOVLF  B'00001111',TRISD       ;Set I/O for PORTD
        MOVLF  B'00000100',TRISE       ;Set I/O for PORTE
        MOVLF  B'10001000',T0CON       ;Set up Timer0 for a looptime of 10 ms
        MOVLF  B'00010000',PORTA       ;Turn off all four LEDs driven from PORTA
        return

DAconv
		  bcf PORTC,RC0
		  bcf PIR1,SSPIF	  
		  
		  MOVLF  0x21,SSPBUF           	   ;Output from DAC-A pin	  
		  DACloop1		  		  
		  btfss  PIR1,SSPIF				   ;Check if serial transfer done
		  bra  DACloop1
		  bcf  PIR1,SSPIF				   ;Cleared after transfer done

		  movff  ADRESH,SSPBUF             ;Move ADRESH to SSPBUF and initiate transfer to output pin
		  DACloop2		  		  
		  btfss  PIR1,SSPIF				   ;Check if serial transfer done
		  bra  DACloop2
		  bsf  PORTC,RC0
         btg PORTA,RA3					   ;Check if working

		return

ADconv		  		
		  bsf  ADCON0,1			   ;Start ADC
		  ADCloop
		  btfsc  ADCON0,1			   ;Check if ADC done
		  bra  ADCloop
		return

end