; 76E003 ADC test program: Reads channel 7 on P1.1, pin 14
$NOLIST
$MODN76E003
$LIST
; N76E003 pinout:
; -------
; PWM2/IC6/T0/AIN4/P0.5 -|1 20|- P0.4/AIN5/STADC/PWM3/IC3
; TXD/AIN3/P0.6 -|2 19|- P0.3/PWM5/IC5/AIN6
; RXD/AIN2/P0.7 -|3 18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
; RST/P2.0 -|4 17|- P0.1/PWM4/IC4/MISO
; INT0/OSCIN/AIN1/P3.0 -|5 16|- P0.0/PWM3/IC3/MOSI/T1
; INT1/AIN0/P1.7 -|6 15|- P1.0/PWM2/IC2/SPCLK
; GND -|7 14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8 13|- P1.2/PWM0/IC0
; VDD -|9 12|- P1.3/SCL/[STADC]
; PWM5/IC7/SS/P1.5 -|10 11|- P1.4/SDA/FB/PWM1
; -------
;

CLK EQU 16600000 ; Microcontroller system frequency in Hz
BAUD EQU 115200 ; Baud rate of UART in bps
TIMER0_RATE EQU 4096 ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU (0x10000-(CLK/1000))
TIMER1_RELOAD EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))

TIMER2_RATE EQU 100; 500z, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(16600000/1000)))

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector (not used in this code)
org 0x000B
	reti

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR
	
	
; 1234567890123456 <- This helps determine the location of the counter
test_message: db 'State: ', 0
time_message: db 'sec:', 0
temp_message: db 'tem:', 0
state0_init: db 'OFF    ', 0
state1_init: db 'SOAK   ', 0
state2_init: db 'PREHEAT', 0
state3_init: db 'PEAK   ', 0
state4_init: db 'REFLOW ', 0
state5_init: db 'COOLING', 0

; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3
PB6 equ P0.5
PWM_OUT    EQU P1.5
MODE_BUTTON equ P1.6
incbut equ P1.2
decbut equ P1.0
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
;$include(ADC_test.asm) 
$LIST

dseg at 0x30 ;Before the state machine!

Temp_abort: ds 1 ;(50)
Time_abort: ds 1 ;(60s)
Temp_soak: ds 1
Time_soak: ds 1
Temp_refl: ds 1
Time_refl: ds 1
Temp_cool: ds 1
Temp_0: ds 1

state: ds 1
FSM1_state: ds 1
bcd:          ds 5
x:			  ds 4
y:            ds 4
Count1ms:     ds 2 ; Used to determine when half second has passed
BCD_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
OC:           ds 1  ;oven control on/off
count1:       ds 1  ;10^-3 * 10 = 10^-2  counts up to 10
count2:       ds 1  ; 10^-2 * 100 = 10^-1  -----> 10 of these make a second
sec:          ds 1  ; counts up to 100
temp:         ds 1
;pwm:          ds 1  ;Oven power  1-100

pwm_counter:  ds 1 ; Free running counter 0, 1, 2, ..., 100, 0
pwm:          ds 1 ; pwm percentage
seconds:      ds 1 ; a seconds counter attached to Timer 2 ISR

MODE_SOAK_TEMP      equ 0  ; Mode to adjust soak temperature
MODE_SOAK_TIME      equ 1  ; Mode to adjust soak time
MODE_REFLOW_TEMP    equ 2  ; Mode to adjust reflow temperature
MODE_REFLOW_TIME    equ 3


current_mode:        ds   1  ; Variable to store the current mode
SoakMessage:      db 'Soak Settings:  ', 0
OvenDisplay:      db 't=   s tmp=    C', 0
ReflowMessage:	db 'Reflow Settings:', 0

bseg
half_seconds_flag: dbit 1
mf:                dbit 1
s_flag: dbit 1 ; set to 1 every time a second has passed

$NOLIST
$include(math32.inc) ; A library of LCD related functions and utility macros
;$include(ADC_test.asm) 
$LIST


begin:
    mov  a, #MODE_SOAK_TEMP   ; Start with soak temperature mode
    mov  current_mode, a      ; Store the current mode
    Set_Cursor(1, 1)
    Send_Constant_String(#SoakMessage)
    Set_Cursor(2,1)
    Send_Constant_String(#OvenDisplay)
    Set_Cursor(2,3)
    Display_BCD(Time_soak)
    Set_Cursor(2,12)
    Display_BCD(Temp_soak)
        
checkbutton:
    jb MODE_BUTTON, AdjustParameters 
    Wait_Milli_Seconds(#200)
    jb MODE_BUTTON, AdjustParameters
    jnb MODE_BUTTON,$    
Modeupdate:
    mov a, current_mode                 ; Load the current mode into accumulator
    inc a                      ; Increment the mode
    cjne a, #5, UpdateMode              ; Compare the new mode value with 5
    mov a, #0                           ; Reset to 0 if it reached 5
UpdateMode:
    mov current_mode, a                 ; Update the current mode with the new value
    Wait_Milli_Seconds(#200)              ; Wait for 200 milliseconds (assuming this is a function call)
    ljmp AdjustParameters               ; Jump to AdjustParameters
    
AdjustParameters:
   mov A, current_Mode       
   cjne A, #MODE_SOAK_TEMP, CheckSoakTime
   Set_Cursor(1, 1)
    Send_Constant_String(#SoakMessage)
    Set_Cursor(2,1)
    Send_Constant_String(#OvenDisplay)
    Set_Cursor(2,12)
    Display_BCD(Temp_soak)
    lcall AdjustSoakTemp
    ljmp checkbutton
        

CheckSoakTime:
    cjne A, #MODE_SOAK_TIME, CheckReflowTemp
    Set_Cursor(2,3)
    Display_BCD(Time_soak)
    lcall AdjustSoakTime
    ljmp checkbutton
    
CheckReflowTemp:
    cjne A, #MODE_REFLOW_TEMP, CheckReflowTime
    Set_Cursor(1, 1)
    Send_Constant_String(#ReflowMessage)
    Set_Cursor(2,1)
    Send_Constant_String(#OvenDisplay)
    Set_Cursor(2,12)
    Display_BCD(Temp_refl)
    lcall AdjustReflowTemp
    ljmp checkbutton
CheckReflowTime:
    cjne A, #MODE_REFLOW_TIME, checkstart
    Set_Cursor(2,3)
    Display_BCD(Time_refl)
    lcall AdjustReflowTime
    ljmp checkbutton
checkstart:
    jb PB6, State_select_label
    ljmp checkbutton
    
State_select_label:
    ljmp State_select      
    
    
Halfway:
    ljmp checkbutton
    
AdjustSoakTemp:
    jnb incbut, IncSoakTemp
    jnb decbut, DecSoakTemp
    ret

AdjustSoakTime:
    jnb incbut, IncSoakTime
    jnb decbut, DecSoakTime
    ret

AdjustReflowTemp:
    jnb incbut, Halfway2 
    jnb decbut, Halfway3
    ret

Halfway2:
    ljmp IncReflowRTemp

Halfway3:
    ljmp DecReflowTemp
    
AdjustReflowTime:
    jnb incbut, Halfway4
    jnb decbut, Halfway5
    ret

Halfway4:
    ljmp IncReflowTime
    
Halfway5:
    ljmp DecReflowTime    
IncSoakTemp:
    mov a, Temp_soak                    ; Load current soak temperature
    cjne a, #0xC8, ContinueIncreaseTemp ; If soak temp is not 200, continue to increase
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton                  ; Apply the settings

ContinueIncreaseTemp:
    add a, #0x05                        ; Increment soak temperature by 5
    mov Temp_soak, a                    ; Store new soak temperature
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton                 ; Apply the settings

DecSoakTemp:
    mov a, Temp_soak                    ; Load current soak temperature
    cjne a, #0x8C, ContinueDecreaseTemp ; If soak temp is not 140, continue to decrease
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton                  ; Apply the settings

ContinueDecreaseTemp:
    add a, #0xFB                        ; Decrement soak temperature by 5 (251 in decimal)
    mov Temp_soak, a                    ; Store new soak temperature
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton           

IncSoakTime:
    mov a, Time_soak                    ; Load current soak time
    cjne a, #0x5A, ContinueIncreaseTime ; If soak time is not 90, continue to increase
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton                 ; Apply the settings

ContinueIncreaseTime:
    add a, #0x05                        ; Increment soak time by 5
    mov Time_soak, a                    ; Store new soak time
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton

DecSoakTime:
    mov a, Time_soak                    ; Load current soak time
    cjne a, #0x3C, ContinueDecreaseTime ; If soak time is not 60, continue to decrease
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton               ; Apply the settings

ContinueDecreaseTime:
    add a, #0xFB                        ; Decrement soak time by 5 (251 in decimal)
    mov Time_soak, a                    ; Store new soak time
    Wait_Milli_Seconds(#200)            ; Delay for processing
    ljmp checkbutton

IncReflowRTemp:
    mov a, Temp_refl
    cjne a, #0xE6, ContinueIncreaseRTemp  ; Limit max reflow temperature
    Wait_Milli_Seconds(#200)
    ljmp checkbutton
    
ContinueIncreaseRTemp:
    add a, #0x05                         ; Increment temperature by 5
    mov Temp_refl, a
    Wait_Milli_Seconds(#200)
    ljmp checkbutton

DecReflowTemp:
    mov a, Temp_refl
    cjne a, #0xDC, ContinueDecreaseRTemp  ; Limit min reflow temperature
    Wait_Milli_Seconds(#200)
    ljmp checkbutton
ContinueDecreaseRTemp:
    add a, #0xFB                         ; Decrement temperature by 5
    mov Temp_refl, a
    Wait_Milli_Seconds(#200)
    ljmp checkbutton
IncReflowTime:
    mov a, Time_refl
    cjne a, #0x90, ContinueIncreaseRTime  ; Limit max reflow time
    Wait_Milli_Seconds(#200)
    ljmp checkbutton
ContinueIncreaseRTime:
    add a, #0x05                         ; Increment time by 5
    mov Time_refl, a
    Wait_Milli_Seconds(#200)
    ljmp checkbutton

DecReflowTime:
    mov a, Time_refl
    cjne a, #0x00, ContinueDecreaseRTime  ; Limit min reflow time
    Wait_Milli_Seconds(#200)
    ljmp checkbutton
ContinueDecreaseRTime:
    add a, #0xFB                         ; Decrement time by 5
    mov Time_refl, a
    Wait_Milli_Seconds(#200)
    ljmp checkbutton
    
;---------------------------------;
; Routine to initialize the ISR ;
; for timer 0 ;
;---------------------------------;
Timer0_Init:
orl CKCON, #0b00001000 ; Input for timer 0 is sysclk/1
mov a, TMOD
anl a, #0xf0 ; 11110000 Clear the bits for timer 0
orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
mov TMOD, a
mov TH0, #high(TIMER0_RELOAD)
mov TL0, #low(TIMER0_RELOAD)
; Enable the timer and interrupts
setb ET0 ; Enable timer 0 interrupt
setb TR0 ; Start timer 0
ret
;---------------------------------;
; ISR for timer 0. Set to execute;
; every 1/4096Hz to generate a ;
; 2048 Hz wave at pin SOUND_OUT ;
;---------------------------------;
Timer0_ISR:
;clr TF0 ; According to the data sheet this is done for us already.
; Timer 0 doesn't have 16-bit auto-reload, so
clr TR0
mov TH0, #high(TIMER0_RELOAD)
mov TL0, #low(TIMER0_RELOAD)
setb TR0
;cpl SOUND_OUT ; Connect speaker the pin assigned to 'SOUND_OUT'!
reti

;Timer2_Init:
;mov T2CON, #0 ; Stop timer/counter. Autoreload mode.
;mov TH2, #high(TIMER2_RELOAD)
;mov TL2, #low(TIMER2_RELOAD)
; Set the reload value
;orl T2MOD, #0x80 ; Enable timer 2 autoreload
;mov RCMP2H, #high(TIMER2_RELOAD)
;mov RCMP2L, #low(TIMER2_RELOAD)
; Init One millisecond interrupt counter. It is a 16-bit variable made with two 8-bit parts
;clr a
;mov Count1ms+0, a
;mov Count1ms+1, a
; Enable the timer and interrupts
;orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
;setb TR2 ; Enable timer 2
;ret


;---------------------------------;
; ISR for timer 2 ;
;---------------------------------;
Timer2_ISR:
clr TF2 ; Timer 2 doesn't clear TF2 automatically. Do it in the ISR. It is bit addressable.
cpl P0.4 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
; The two registers used in the ISR must be saved in the stack
push acc
push psw

	inc pwm_counter	
	
	
	mov a , count1
	add a, #0x01
	da a
	mov count1,a
	
	mov count1, a
	cjne a, #0x10, next1 ; 
	
	mov count1, #0	
	mov a, count2
	add a, #0x01
	da a
	mov count2, a
	
	cjne a, #0x05, next1 ;
	mov count2, #0
	
	
	next1:
	clr c
	mov a, pwm
	subb a, pwm_counter ; If pwm_counter <= pwm then c=1
	cpl c
	mov PWM_OUT, c
	
	mov a, pwm_counter
	cjne a, #60, Timer2_ISR_done
	mov pwm_counter, #0
	;inc sec ; It is super easy to keep a seconds count here
	mov a,  sec
	add a, #0x01
	da a
	mov sec, a
	
	setb s_flag

Timer2_ISR_done:
pop psw
pop acc
reti
; FSM2_state: ds 1
; FSM2_state: ds 1
; FSM2_state: ds 1

; init for temperature
; Init_All:
; 	; Configure all the pins for biderectional I/O
; 	mov	P3M1, #0x00
; 	mov	P3M2, #0x00
; 	mov	P1M1, #0x00
; 	mov	P1M2, #0x00
; 	mov	P0M1, #0x00
; 	mov	P0M2, #0x00
	
; 	orl	CKCON, #0x10 ; CLK is the input for timer 1
; 	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
; 	mov	SCON, #0x52
; 	anl	T3CON, #0b11011111
; 	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
; 	orl	TMOD, #0x20 ; Timer 1 Mode 2
; 	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
; 	setb TR1
	
; 	; Using timer 0 for delay functions.  Initialize here:
; 	clr	TR0 ; Stop timer 0
; 	orl	CKCON,#0x08 ; CLK is the input for timer 0
; 	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
; 	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
; 	; Initialize the pin used by the ADC (P1.1) as input.
; 	orl	P1M1, #0b00000010
; 	anl	P1M2, #0b11111101
	
; 	; Initialize and start the ADC:
; 	anl ADCCON0, #0xF0
; 	orl ADCCON0, #0x07 ; Select channel 7
; 	; AINDIDS select if some pins are analog inputs or digital I/O:
; 	mov AINDIDS, #0x00 ; Disable all analog inputs
; 	orl AINDIDS, #0b10000000 ; P1.1 is analog input
; 	orl ADCCON1, #0x01 ; Enable ADC
	
; 	ret
	
 wait_1ms:
 	clr	TR0 ; Stop timer 0
 	clr	TF0 ; Clear overflow flag
 	mov	TH0, #high(TIMER0_RELOAD_1MS)
 	mov	TL0,#low(TIMER0_RELOAD_1MS)
 	setb TR0
 	jnb	TF0, $ ; Wait for overflow
 	ret

; ; Wait the number of miliseconds in R2
waitms:
 	lcall wait_1ms
 	djnz R2, waitms
 	ret

; ; We can display a number any way we want.  In this case with
; ; four decimal places.
; Display_formated_BCD:
; 	Set_Cursor(2, 14)
; 	Display_BCD(bcd+2)
; 	Display_char(#'.')
; 	Display_BCD(bcd+1)
; 	Display_BCD(bcd+0)
; 	ret

Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1
	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
	; Initialize the pins used by the ADC (P1.1, P1.7) as input.
	orl	P1M1, #0b10000010
	anl	P1M2, #0b01111101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x07 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b10000001 ; Activate AIN0 and AIN7 analog inputs
	orl ADCCON1, #0x01 ; Enable ADC
	
		; Initialize timer 2 for periodic interrupts
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov T2MOD, #0b1010_0000 ; Enable timer 2 autoreload, and clock divider is 16
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	; Init the free running 10 ms counter to zero
	mov pwm_counter, #0
	; Enable the timer and interrupts
	orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
    setb TR2  ; Enable timer 2

	setb EA ; Enable global interrupts
	
	ret
	

; Wait the number of miliseconds in R2


; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	Set_Cursor(2, 7)
	;Display_BCD(bcd+4)
	;Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	;Display_char(#'.')
	;Display_BCD(bcd+1)
	;Display_BCD(bcd+0)
	;Set_Cursor(2, 10)
	;Display_char(#'=')
	ret	
	
	
Read_ADC:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRL
    anl a, #0x0f
    mov R0, a
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, R0
    mov R0, A
	ret

putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret

;---------------------------------;
; Send a BCD number to PuTTY      ;
;---------------------------------;
Send_BCD mac
push ar0
mov r0, %0
lcall ?Send_BCD
pop ar0
endmac
?Send_BCD:
push acc
; Write most significant digit
mov a, r0
swap a
anl a, #0fh
orl a, #30h
lcall putchar
; write least significant digit
mov a, r0
anl a, #0fh
orl a, #30h
lcall putchar
pop acc
ret

	
cseg
main:
    mov sp, #0x7f
    mov P0M1, #0x00
    mov P0M2, #0x00
    mov P1M1, #0x00
    mov P1M2, #0x00
    mov P3M2, #0x00
    mov P3M2, #0x00

    lcall Init_All
    lcall LCD_4BIT
    ;lcall Timer2_Init
    lcall Timer0_Init
    ;lcall Init_All
    setb EA   ; Enable Global interrupts

    mov Temp_abort, #50
    mov Time_abort, #0x60
    mov Temp_soak, #150 
    mov Time_soak, #0x80
    mov Temp_refl, #220
    mov Time_refl, #0x6
    mov Temp_cool, #60
    mov sec, #0
    mov pwm, #0
    
    ljmp begin
FSM2:

Set_Cursor(2,6)       
Display_BCD(sec)

;Set_Cursor(1,15)       
;Display_BCD(count2)

;Set_Cursor(2,15)       
;Display_BCD(count1)

;ljmp FSM2

;cjne a, #0x02, State_select_connect
sjmp Temp_measure

State_select_connect:
ljmp State_select

Temp_measure:
anl ADCCON0, #0xF0
orl ADCCON0, #0x07
lcall Read_ADC

; Convert to voltage
mov x+0, R0
mov x+1, R1
; Pad other bits with zero
mov x+2, #0
mov x+3, #0
	
Load_y(50900) ; The MEASURED LED voltage: 2.074V, with 4 decimal places
lcall mul32
load_y(4095)
lcall div32
    
Load_y(100)
lcall mul32
Load_y(375)
lcall div32
Load_y(41)
lcall div32
load_y(22)
lcall add32


mov a, count2
cjne a, #0x01, temp_skip
ljmp temp_read

temp_read:

lcall hex2bcd
Set_Cursor(2,13)
Display_BCD(bcd+1)
Set_Cursor(2,15)
Display_BCD(bcd+0)

Send_BCD(bcd+1)
Send_BCD(bcd+0)
mov a, #'\r'
lcall putchar
mov a, #'\n'
lcall putchar

temp_skip:

mov temp, x+0

Set_Cursor(2,9)
Send_Constant_String(#temp_message)

State_select:
mov a, FSM1_state
jb PB6, test_state0_0
jnb PB6, $ ; Wait for key release
  
cjne a, #0, test_state_0
mov FSM1_state, #0
mov sec, #0
    
test_state0_0:
mov a, FSM1_state
cjne a, #0, test_state_1
ljmp FSM1_state0

test_state_1:
cjne a, #1, test_state_2
mov pwm, #100
ljmp FSM1_state1

test_state_2:
cjne a, #2, test_state_3
ljmp FSM1_state2

test_state_3:
cjne a, #3, test_state_4
ljmp FSM1_state3

test_state_4:
cjne a, #4, test_state_5
ljmp FSM1_state4

test_state_5:
cjne a, #5, test_state_0
ljmp FSM1_state5
    
test_state_0:
ljmp FSM1


FSM1:
mov FSM1_state, #0
mov a, FSM1_state

FSM1_state0:
    Set_Cursor(1,1)
    Send_Constant_String(#test_message)
	Set_Cursor(2,1)
    Send_Constant_String(#time_message)
    Set_Cursor(2,9)
	Send_Constant_String(#temp_message)
	Set_Cursor(2,8)
	Display_char(#' ')
	Set_Cursor(1,15)
	Display_char(#' ')
	Set_Cursor(1,16)
	Display_char(#' ')
    cjne a, #0, FSM1_state1
    mov pwm, #0
    Set_Cursor(1,8)
    Send_Constant_String(#state0_init)
    jb PB6, FSM1_state0_done
    jnb PB6, $ ; Wait for key release
    mov sec, #0
    mov FSM1_state, #1

    FSM1_state0_done:
    ; mov sec, #0
    ljmp FSM2 

    FSM1_state1:
    cjne a, #1, FSM1_state2
    mov pwm, #100
    Set_Cursor(1,8)
    Send_Constant_String(#state1_init)
    Set_Cursor(2,6)
    Display_BCD(Sec)
    jb PB6, stateButton1
    jnb PB6, $ ; Wait for key release
    mov sec, #0
    mov FSM1_state, #0
    ljmp FSM2
    
    
    stateButton1:
    mov a, Time_abort
    subb a, sec ;if more than 60s has passed, test whether or not to abort
    
    jc Test_abort
    ljmp FSM1_state1_part2

    Test_abort:
    mov a, Temp_abort
    subb a, temp ;if temperature > 50 degrees, continue
    jc FSM1_state1_part2
    ; mov a, #0 ;change state to 0 before jump
    mov FSM1_state, #0
    ljmp FSM2 ;if not, go to state 0

    FSM1_state1_part2:
    mov a, Temp_soak
    clr c
    subb a, temp
    jnc FSM1_state1_done
    mov FSM1_state, #2

    FSM1_state1_done:
    ljmp FSM2

    FSM1_state2:
    Set_Cursor(2,6)
    Display_BCD(Sec)
    cjne a, #0x02, FSM1_state3
    mov pwm, #20
    Set_Cursor(1,8)
    Send_Constant_String(#state2_init)
    jb PB6, stateButton2
    jnb PB6, $ ; Wait for key release
    mov sec, #0
    mov FSM1_state, #0
    ljmp FSM2
    
    stateButton2:
    mov a, Time_soak
    clr c
    subb a, sec
    jnc FSM1_state2_done
    mov sec, #0
    mov FSM1_state, #3

    FSM1_state2_done:

    ljmp FSM2

    FSM1_state3:
    
    cjne a, #3, FSM1_state4
    mov pwm, #100
    Set_Cursor(1,8)
    Send_Constant_String(#state3_init)
    Set_Cursor(2,6)
    Display_BCD(Sec)
    jb PB6, stateButton3
    jnb PB6, $ ; Wait for key release
    mov sec, #0
    mov FSM1_state, #0
    ljmp FSM2
    
    
    stateButton3:
    mov a, Temp_refl
    clr c
    subb a, temp
    jnc FSM1_state3_done
    mov FSM1_state, #4

    FSM1_state3_done:
    ; mov sec, #0
    ljmp FSM2

    FSM1_state4:
    cjne a, #4, FSM1_state5
    mov pwm, #20
    Set_Cursor(2,6)
    Display_BCD(Sec)
    Set_Cursor(1,8)
    Send_Constant_String(#state4_init)
    jb PB6, stateButton4
    jnb PB6, $ ; Wait for key release
    mov sec, #0
    mov FSM1_state, #0
    ljmp FSM2
    
    
    stateButton4:
    mov a, Time_refl
    clr c
    subb a, sec 
    jnc FSM1_state4_done 
    mov FSM1_state, #5

    FSM1_state4_done:
    ljmp FSM2 

    FSM1_state5:
    cjne a, #5, FSM1_state0_connect
    mov pwm, #0
    Set_Cursor(2,6)
    Display_BCD(Sec)
    Set_Cursor(1,8)
    Send_Constant_String(#state5_init)
    jb PB6, stateButton5
    jnb PB6, $ ; Wait for key release
    mov sec, #0
    mov FSM1_state, #0
    ljmp FSM2
    
    
    stateButton5:
    mov a, Temp_cool
    clr c 
    subb a, temp
    jc FSM1_state5_done
    mov FSM1_state, #0

    FSM1_state5_done:
    ljmp FSM2

    FSM1_state0_connect:
    ljmp FSM1_state0
    

END
; pretend your temparature inside your oven is called temp_o
; then you can just do
;mov temp_0, #230
; when you check with fsm, this is the value it will compare with



;Button Code: Sidhant
; jb PB6, stateButton22
;     jnb PB6, $ ; Wait for key release
;     mov sec, #0
;     mov FSM1_state, #0
;     ljmp FSM2
    
    
;     stateButton2: