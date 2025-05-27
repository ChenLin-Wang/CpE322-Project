CODE SEGMENT
DATA SEGMENT
	; Ports for 8255 Cons
	PORT_CONS LABEL WORD
		DW 0CH				; 0000 0000 1100
		DW 430H				; 0100 0011 0000
	
	; Init paras for 8255s
	PORT_CON_PARAS LABEL BYTE		
		; set conntrol bits for 8255A_1
		; PA[0..7] OUT	7-SEG 1
		; PB[0..7] IN	ADC-Sensors
		; PC[0..3] IN	ADC-EOC
		; 10001010
		DB 8AH
		; set conntrol bits for 8255A_2
		; PA[0..7] OUT	7-SEG 2
		; PB[0..7] OUT	7-SEG 3
		; PC[0..7] OUT	7-SEG 4
		; 10000000
		DB 80H

	; 4 Sensor ADC Ports
	SENSOR_PORTS LABEL BYTE
		DB 4H				; 0000 0100 LM35 		Temperature Sensor
		DB 44H				; 0100 0100 SEN0106 	PH Sensor
		DB 84H				; 1000 0100 SEN0189 	Turbidity Sensor
		DB 0C4H				; 1100 0100 SEN0237 	Dissolved Oxygen Sensor

	; 4 7-SEG Ports, pair sensors one by one
	LED7SEG_PORTS LABEL WORD
		DW 410H				; 0100 0001 0000	7-SEG 1
		DW 450H				; 0100 0101 0000	7-SEG 2
		DW 4A0H				; 0100 1010 0000	7-SEG 3
		DW 4E0H				; 0100 1110 0000	7-SEG 4

	; 4 EOC sign for sensors
	EOC_PORTS LABEL BYTE
		DB 8H 				; 0000 1000		EOC for Temperature Sensor
		DB 48H				; 0100 1000		EOC for PH Sensor
		DB 88H				; 1000 1000		EOC for Turbidity Sensor
		DB 0C8H				; 1100 1000		EOC for Dissolved Oxygen Sensor

	LED_RESULT DB 4 DUP(0)
	ALERT_RESULT DB 0H
	
	; 7219 Initialize Paras
	INIT_PARAS_7219 LABEL WORD
		DW 09FFH			; 7219 Display testing
		DW 0A0FH			; 7129 Bright adjust
		DW 0B07H			; 7219 Scan limit
		DW 0C01H			; 7219 Exit shutdown mode, ready for display
		DW 0F00H			; 7219 Exit display testing

	; For 7219 Bit masks
	DINMASK EQU 1B
	LOADMASK EQU 10B
	CLKMASK EQU 100B

	ALERT_PORTS LABEL WORD
		DW 400H				; 0100 0000 0000	Temperature Alert
		DW 440H				; 0100 0100 0000	PH Alert
		DW 480H				; 0100 1000 0000	Turbidity Alert
		DW 4C0H				; 0100 1100 0000	Dissolved Oxygen Alert

DATA ENDS

MAIN PROC FAR
	; assign code and data segments
	ASSUME CS:CODE, DS:DATA
START:
	; init data segment address
    MOV AX, DATA
    MOV DS, AX

	Initialize8255:
		; Init 8255_1
		MOV BX, 0H
		PUSH BX
		CALL Init8255
		ADD SP, 2
		
		; Init 8255_2
		MOV BX, 1H
		PUSH BX
		CALL Init8255
		ADD SP, 2
	
	InitializeLEDs:
		CALL Init7219
	
	MOV CX, 0H
	SensorRead:
		MOV DX, 0H
		MOV AL, 0FFH
		OUT DX, AL
		
		PUSH CX
		CALL ReadSensor
		ADD SP, 2

		MOV AH, CL
		PUSH AX
		CALL ValueParse

		MOV AL, [ALERT_RESULT]
		MOV DX, 400H
		OUT DX, AL

		MOV BX, CX
		SHL BX, 1
		MOV DX, [SI + BX]
		
		PUSH BX
		MOV BX, 0H
		ResultCollect:
			MOV SI, OFFSET LED_RESULT
			MOV AL, [SI + BX]
			MOV AH, BL
			
			INC AH
			
			TEST CX, 01H
			JNZ	Plus4
			JZ Continue
				
			Plus4:
				ADD AH, 4

			Continue:
			CMP BX, 2
			JE AddPD
			JNE Continue2
			
			AddPD:
				OR AL, 80H

			Continue2:
			PUSH AX
			PUSH CX
			Call SendTo7219
			ADD SP, 4

			INC BX
			CMP BX, 4
		JL ResultCollect
		POP BX
		CALL Delay_2ms
		ADD SP, 2
		INC CX
		CMP CX, 4
	JL SensorRead
	
	MOV CX, 0H
	JMP SensorRead

MAIN ENDP

; Function used to write parameters into 8255s for initialize
Init8255 PROC NEAR
	PUSH BP
	MOV BP, SP
	; -------------------
	MOV AL, [BP + 4]	; Parameter AL: 0 for 8255_1, 1 for 8255_2
	MOV BL, AL
	XOR BH, BH

	MOV SI, OFFSET PORT_CON_PARAS
	MOV AL, [SI + BX]

	MOV SI, OFFSET PORT_CONS
	SHL BX, 1
	MOV DX, [SI + BX]

	OUT DX, AL
	; -------------------
	MOV SP, BP
	POP BP
	RET
Init8255 ENDP

; Function used to read data from sensors
ReadSensor PROC NEAR
	PUSH BP
	MOV BP, SP
	; -------------------
	PUSH SI

	MOV AL, [BP + 4]		; Parameter AL: 0~3. means read data from xth sensor
	MOV BL, AL
	XOR BH, BH

	MOV SI, OFFSET SENSOR_PORTS
	MOV DL, [SI + BX]
	XOR DH, DH
	MOV AL, 0H
	OUT DX, AL
	
	; wait for a while
	;CALL Delay_2ms

	MOV SI, OFFSET EOC_PORTS
	MOV DL, [SI + BX]
	XOR DH, DH

	WaitEOC:
		IN AL, DX
		TEST AL, 1H
	JZ WaitEOC
	
	MOV SI, OFFSET SENSOR_PORTS
	MOV DL, [SI + BX]
	XOR DH, DH

    IN AL, DX

	POP SI
	; -------------------
	MOV SP, BP
	POP BP
	RET
ReadSensor ENDP

; Display the number in 7-Seg, the format will depends on sensor
ValueParse PROC NEAR
	PUSH BP
	MOV BP, SP
	; -------------------
	PUSH CX
	PUSH BX
	PUSH AX
	PUSH SI
	PUSH DX
	MOV AX, [BP + 4]		; Parameter AL: The voltage(Unconverted Bytes) of the sensor read
	MOV BL, AH				; Parameter BL: The 7-Seg LED want to display
	MOV BH, 0
	MOV DX, 0
	
	MOV AH, 0
	MOV CX, 5000
	MUL CX
	MOV CX, 255
	DIV CX					; AX is voltage now (mV)
	
	CMP BL, 0
	JE LED1
	CMP BL, 1
	JE LED2
	CMP BL, 2
	JE LED3
	CMP BL, 3
	JE LED4
	
	LED1:
		MOV AH, 0			; AX is temperature (C)
	
		MOV BX, 1B
		PUSH BX
		MOV BX, AX
		PUSH BX
		MOV BX, 350
		PUSH BX
		MOV BX, 150
		PUSH BX
		CALL RangeCompare	; Range Check
		ADD SP, 8
		
		JMP ParseNums
	LED2:
		MOV CX, 14
		MUL CX
		MOV CX, 500
		DIV CX				; AX is PH
		MOV AH, 0

		MOV BX, 10B
		PUSH BX
		MOV BX, AX
		PUSH BX
		MOV BX, 85
		PUSH BX
		MOV BX, 65
		PUSH BX
		CALL RangeCompare	; Range Check
		ADD SP, 8

		JMP ParseNums
	LED3:
		MOV BX, 4500
		SUB BX, AX
		MOV CX, 1000
		MUL CX
		MOV CX, 450
		DIV CX				; AX is Turbidity (NTU)

		MOV BX, 100B
		PUSH BX
		MOV BX, AX
		PUSH BX
		MOV BX, 500
		PUSH BX
		MOV BX, 0
		PUSH BX
		CALL RangeCompare	; Range Check
		ADD SP, 8

		JMP ParseNums
	LED4:
		MOV CX, 20
		MUL CX
		MOV CX, 500
		DIV CX          	; AX = Dissolved Oxygen (mg/L)
		MOV AH, 0

		MOV BX, 1000B
		PUSH BX
		MOV BX, AX
		PUSH BX
		MOV BX, 1000
		PUSH BX
		MOV BX, 50
		PUSH BX
		CALL RangeCompare	; Range Check
		ADD SP, 8

		JMP ParseNums
	
	ParseNums:
		MOV DX, 0
		MOV BX, 3
		MOV SI, OFFSET LED_RESULT
		MOV CX, 10
		ParseDigital:
			DIV CX
			MOV [SI + BX], DL
			MOV DL, 0
			CMP BX, 0
		JZ FUNCEND
			SUB BX, 1
			CMP AX, 0
		JNZ ParseDigital
		JZ CLEAN

	CLEAN:
		MOV AH, 0
		MOV [SI + BX], AH
		CMP BX, 0
		JZ FUNCEND
		SUB BX, 1
		JMP CLEAN

	FUNCEND:
		POP DX
		POP SI
		POP AX
		POP BX
		POP CX
	; -------------------
	MOV SP, BP
	POP BP
	RET
ValueParse ENDP

Init7219 PROC NEAR
	PUSH BP
	MOV BP, SP
	; ---------------
	PUSH CX
	PUSH SI
	PUSH BX

	MOV SI, OFFSET INIT_PARAS_7219

	MOV CX, 0
	RunCmds:
		MOV BX, CX
		SHL BX, 1
		MOV DX, [SI + BX]
		
		; init first 7219
		MOV AX, 0H
		PUSH DX
		PUSH AX
		CALL SendTo7219
		ADD SP, 2
		
		; init second 7219
		MOV AX, 2H
		PUSH DX
		PUSH AX
		CALL SendTo7219
		ADD SP, 2
	
		INC CX
		CMP CX, 4
	JL RunCmds
	
	POP BX
	POP SI
	POP CX
	; ---------------
	MOV SP, BP
	POP BP
	RET
Init7219 ENDP

SendTo7219 PROC NEAR
	PUSH BP
	MOV BP, SP
	; ---------------
	PUSH BX
	PUSH SI
	PUSH DX

	MOV BX, [BP + 4]	; The index of LED, 0~3
	MOV SI, OFFSET LED7SEG_PORTS
	SHL BX, 1
	MOV DX, [SI + BX]
	MOV BX, [BP + 6]	; The data want send

	MOV AL, 0H
	OUT DX, AL			; Put Load to low
		
	MOV AL, BH			; Write high bits
	MOV AH, 0
	PUSH AX
	PUSH DX
	CALL WriteDataTo7219
	ADD SP, 4

	MOV AL, BL			; Write low bits
	MOV AH, 0
	PUSH AX
	PUSH DX
	CALL WriteDataTo7219
	ADD SP, 4

	MOV AL, LOADMASK
	OUT DX, AL
	
	POP DX
	POP SI
	POP BX
	; ---------------
	MOV SP, BP
	POP BP
	RET
SendTo7219 ENDP

WriteDataTo7219 PROC NEAR
	PUSH BP
	MOV BP, SP
	; ---------------
	PUSH BX
	PUSH DX
	PUSH CX
	MOV DX, [BP + 4]	; 7219 Address
	MOV BL, [BP + 6]	; Data want send

	MOV CX, 8
	SENDBIT:
		; Set Clk to 0
		MOV AL, 0H
		OUT DX, AL
		
		SHL BL, 1
		JC SEND1
		JNC SEND0
	SEND1:
		; Send data bit 1
		MOV AL, DINMASK
		JMP DONE
	SEND0:
		; Send data bit 0
		MOV AL, 0H
		JMP DONE
	DONE:
		; Send bit data with high Clk
		OR AL, CLKMASK
		OUT DX, AL

	LOOP SENDBIT
	POP CX
	POP DX
	POP BX
	; ---------------
	MOV SP, BP
	POP BP
	RET
WriteDataTo7219 ENDP

RangeCompare PROC NEAR
	PUSH BP
	MOV BP, SP
	; ---------------
	PUSH AX
	PUSH BX
	PUSH CX
	PUSH DX
	MOV DX, [BP + 4]	; Lower Bound
	MOV BX, [BP + 6]	; Upper Bound
	MOV CX, [BP + 8]	; The Number
	MOV AX, [BP + 10]	; The Bitmask
	
	CMP CX, BX
	JG OutBounded
	CMP CX, DX
	JL OutBounded
	MOV DX, 0
	
	MOV BL, [ALERT_RESULT]
	NOT AL
	AND BL, AL
	MOV [ALERT_RESULT], BL

	JMP Done
	
	OutBounded:
		MOV BL, [ALERT_RESULT]
		OR BL, AL
		MOV [ALERT_RESULT], BL

	Done:
	POP DX
	POP CX
	POP BX
	POP AX
	; ---------------
	MOV SP, BP
	POP BP
	RET
RangeCompare ENDP

Delay_2ms PROC NEAR
	PUSH BX
	MOV BX, 01FFH
	LP2:
		PUSHF
		POPF
		DEC BX
	JNZ LP2
	POP BX
	RET
Delay_2ms ENDP

CODE ENDS
END MAIN