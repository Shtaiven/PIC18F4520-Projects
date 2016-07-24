;;;;;;; FIR for QwikFlash board ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; FIR Averaging Filter
;
;;;;;;; Program hierarchy ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Shift back previous values
; Perform an ADconv
; Store ADRESH:ADRESL into CURRENT:CURRENT+1
; Filter
; 	Add CURRENT+PREV1+PREV2+PREV3
; 	Divide result by 4
; Take 8 msb
; Perform a DAconv
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
		CURRENT:2					   ;Store current value
		PREV1:2						   ;Store previous three values
		PREV2:2
		PREV3:2
		OUTPUT:2					   ;Value to be output by DAconv
		COUNT						   ;General use counter
        endc

;;;;;;; Macro definitions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MOVLF   macro  literal,dest
        movlw  literal
        movwf  dest
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
		
L1	 		  
		 rcall ADconv
		 rcall DelayReg
		 rcall Filter
		 rcall EightMSB
	     rcall DAconv
        bra	L1

;;;;;;; Initial subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs all initializations of variables and registers.

Initial
		MOVLF  0x00,PREV1			   ;Initialize all PREV# registers to 0.
		MOVLF  0x00,PREV1+1
		MOVLF  0x00,PREV2
		MOVLF  0x00,PREV2+1
		MOVLF  0x00,PREV3
		MOVLF  0x00,PREV3+1

		MOVLF  B'11000000',SSPSTAT	   ;use rising clock edge for loading buffer bits into output
		MOVLF  B'00100000',SSPCON1	   ;Enable SPI and output at rate of Fosc/4 (0000)
		
		MOVLF  B'00011101',ADCON0      ;Convert analog input to digital from port E2
        MOVLF  B'10001110',ADCON1      ;Enable PORTA & PORTE digital I/O pins
		MOVLF  B'11000001',ADCON2	   ;ADRES right justified clock = Fosc/8 (001)

        MOVLF  B'11100001',TRISA       ;Set I/O for PORTA
        MOVLF  B'11011100',TRISB       ;Set I/O for PORTB
        MOVLF  B'11000000',TRISC       ;Set I/0 for PORTC
        MOVLF  B'00001111',TRISD       ;Set I/O for PORTD
        MOVLF  B'00000100',TRISE       ;Set I/O for PORTE
        MOVLF  B'00010000',PORTA       ;Turn off all four LEDs driven from PORTA

        return

;;;;;;; DAconv subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs digital/analog conversion.

DAconv
		  bcf PORTC,RC0
		  bcf PIR1,SSPIF	  
		  
		  MOVLF  0x22,SSPBUF           	   ;Output from DAC-A pin	  
		  DACloop1		  		  
		  btfss  PIR1,SSPIF				   ;Check if serial transfer done
		  bra  DACloop1
		  bcf  PIR1,SSPIF				   ;Cleared after transfer done

		  movff  OUTPUT,SSPBUF             ;Move ADRESH to SSPBUF and initiate transfer to output pin
		  DACloop2		  		  
		  btfss  PIR1,SSPIF				   ;Check if serial transfer done
		  bra  DACloop2
		  bsf  PORTC,RC0
          btg PORTA,RA3					   ;Check if working

		return

;;;;;;; ADconv subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs analog/digital conversion.

ADconv		  		
		  bsf  ADCON0,1			   	    ;Start ADC
		  ADCloop
		  btfsc  ADCON0,1			 	;Check if ADC done
		  bra  ADCloop

		return

;;;;;;; DelayReg subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine stores the values of CURRENT into PREV1, PREV1 into PREV2, and PREV2 into PREV3.
; The value stored in PREV3 is lost and CURRENT:2 is populated by the most recent value in ADRESH:ADRESL.
; This doesn't use an FSR loop so that the locations of CURRENT and PREV# variables can be modified without worry.

DelayReg
		movff  PREV2+1,PREV3+1
		movff  PREV2,PREV3
		movff  PREV1+1,PREV2+1
		movff  PREV1,PREV2
		movff  CURRENT+1,PREV1+1
		movff  CURRENT,PREV1		
		movff  ADRESL,CURRENT+1
		movff  ADRESH,CURRENT

		return

;;;;;;; Filter subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Perform averaging filter operations and place result in OUTPUT.

Filter
		;adding previous four values
		movf  PREV3+1,W
		addwf  PREV2+1,W
		movwf  OUTPUT+1
		movf  PREV3,W
		addwfc  PREV2,W
		movwf  OUTPUT

		movf  OUTPUT+1,W
		addwf  PREV1+1,W
		movwf  OUTPUT+1
		movf  OUTPUT,W
		addwfc  PREV1,W
		movwf  OUTPUT

		movf  OUTPUT+1,W
		addwf  CURRENT+1,W
		movwf  OUTPUT+1
		movf  OUTPUT,W
		addwfc  CURRENT,W
		movwf  OUTPUT

		;divide by 4
		bcf STATUS,C			;clear carry bit
		rrcf  OUTPUT,F
		rrcf  OUTPUT+1,F
		bcf STATUS,C
		rrcf  OUTPUT,F
		rrcf  OUTPUT+1,F
		
		return

;;;;;;; EightMSB subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Stores the 8 most significant bits of OUTPUT:OUTPUT+1 into OUTPUT by shifting left 6 times.

EightMSB
		bcf  STATUS,C			;clear carry bit
		MOVLF  6,COUNT
ShiftLoop
		rlcf  OUTPUT+1,F
		rlcf  OUTPUT,F
		decf  COUNT
		bnz ShiftLoop
		
		return

end