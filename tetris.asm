;============================================================================
; 文件名: TETRIS_FIXED_FINAL_COMPLETE_SWITCH_CONTROL.ASM
; 功能: 俄罗斯方块 + 计数(0-99) + 开关控制速度 + LED显示速度级别
; 硬件: 8255 A口控制数码管位选和键盘列扫描，B口控制段码，C口低4位键盘行输入
;       8255 C口高4位(PC4-PC7)连接开关K0-K3
;============================================================================

;----------------------------------------------------------------------------
; 1. 硬件端口定义
;----------------------------------------------------------------------------
; LED 点阵接口
ROW1        EQU 0600H       ; 行选 0-7
ROW2        EQU 0640H       ; 行选 8-15
COL1        EQU 0680H       ; 列选 0-7
COL2        EQU 06C0H       ; 列选 8-15

; 8255 接口
MY8255_A    EQU 0620H       ; A口输出：数码管位选 + 键盘列扫描（复用）
MY8255_B    EQU 0622H       ; B口输出：数码管段码
MY8255_C    EQU 0624H       ; C口输入：低4位键盘行扫，高4位开关输入
MY8255_CON  EQU 0626H       ; 控制口

STACK1  SEGMENT STACK
        DW 256 DUP(?)
TOP     LABEL WORD
STACK1  ENDS

DATA    SEGMENT
    ; 游戏数据
    DISP_BUFFER DW 16 DUP(0)   
    GAME_AREA   DW 16 DUP(0)
    
    CUR_ROW     DB 0        
    CUR_COL     DB 0        
    CUR_SHAPE   DB 0        
    CUR_ROT     DB 0        
    
    GAME_OVER   DB 0        
    GAME_STARTED DB 0       
    
    TEMP_ROW    DB 0
    TEMP_COL    DB 0
    
    ; 速度控制变量
    FALL_DELAY      DW 300      ; 基本下降延时
    SPEED_LEVEL     DB 2        ; 速度级别 0-慢，1-中，2-快，3-超快
    BASE_DELAYS     DW 500, 300, 150, 50  ; 不同速度级别的延时
    SPEED_DIVIDER   DB 0        ; 速度控制分频器
    
    CUR_BLOCK   DB 8 DUP(0)
    
    ; 键盘状态
    LAST_KEY    DB 0FFH     
    KEY_PRESSED DB 0        
    KEY_RELEASED DB 1       
    
    ; 扫描分频器，防止太灵敏
    SCAN_DIVIDER DB 0

    ; 按键定义
    KEY_DEBUG   DB 0         ; 用于调试显示
    
    ; 实际游戏按键
    KEY_START   EQU 0CH     ; C键开始
    KEY_LEFT    EQU 0DH     ; D键左移
    KEY_RIGHT   EQU 0EH     ; E键右移
    KEY_EXIT    EQU 0FH     ; F键退出
    
    RAND_SEED   DW 1234

    ; 计数变量
    BLOCK_COUNT DB 0        ; 计数范围 0-99
    
    ; 移动检查辅助变量
    CHECK_ROW   DB 0
    CHECK_COL   DB 0
    NEW_COL     DB 0        ; 尝试移动的新列位置
    MOVE_OK     DB 0        ; 移动是否允许
    
    ; 开关状态
    SWITCH_STATE    DB 0     ; 当前开关状态
    LAST_SWITCH     DB 0     ; 上次开关状态
    SWITCH_CHANGED  DB 0     ; 开关状态变化标志
    
    ; LED显示缓冲区（显示速度级别）
    LED_PATTERN     DB 0     ; LED显示模式
    
    ; 7段数码管段码表 (0-9)
    DTABLE      DB 3FH,06H,5BH,4FH,66H,6DH,7DH,07H,7FH,6FH
    
    ; LED显示表（4个LED表示4种速度）
    ; 位0-3对应LED0-LED3，1亮0灭
    LED_TABLE   DB 0001B, 0011B, 0111B, 1111B
    
    ; 形状表
SHAPE_TABLE:
    ; I
    DB 0,0, -1,0, 1,0, 2,0
    DB 0,0, 0,-1, 0,1, 0,2
    DB 0,0, -1,0, 1,0, 2,0
    DB 0,0, 0,-1, 0,1, 0,2
    ; O
    DB 0,0, 0,1, 1,0, 1,1
    DB 0,0, 0,1, 1,0, 1,1
    DB 0,0, 0,1, 1,0, 1,1
    DB 0,0, 0,1, 1,0, 1,1
    ; T
    DB 0,0, -1,0, 1,0, 0,1
    DB 0,0, 0,-1, 0,1, 1,0
    DB 0,0, -1,0, 1,0, 0,-1
    DB 0,0, 0,-1, 0,1, -1,0
    ; S
    DB 0,0, -1,0, 0,1, 1,1
    DB 0,0, 0,-1, 1,0, 1,1
    DB 0,0, -1,0, 0,1, 1,1
    DB 0,0, 0,-1, 1,0, 1,1
    ; Z
    DB 0,0, -1,1, 0,1, 1,0
    DB 0,0, 0,-1, 1,-1, 1,0
    DB 0,0, -1,1, 0,1, 1,0
    DB 0,0, 0,-1, 1,-1, 1,0
    ; J
    DB 0,0, -1,0, 1,0, 1,-1
    DB 0,0, 0,-1, 0,1, 1,1
    DB 0,0, -1,0, 1,0, -1,1
    DB 0,0, 0,-1, 0,1, -1,-1
    ; L
    DB 0,0, -1,0, 1,0, 1,1
    DB 0,0, 0,-1, 0,1, -1,1
    DB 0,0, -1,0, 1,0, -1,-1
    DB 0,0, 0,-1, 0,1, 1,-1
DATA    ENDS

CODE    SEGMENT
        ASSUME CS:CODE, DS:DATA, SS:STACK1
        
START:  
    MOV AX, DATA
    MOV DS, AX
    MOV AX, STACK1
    MOV SS, AX
    LEA SP, TOP
    
    CALL INIT_8255
    CALL SHOW_WELCOME_BORDER
    
    MOV BLOCK_COUNT, 0

    ; 初始化速度控制
    MOV SPEED_LEVEL, 2          ; 默认中速
    CALL UPDATE_SPEED           ; 更新速度延时

DEBUG_MODE:
    CALL SCAN_KEYBOARD
    CALL UPDATE_7SEG_DISPLAY 
    
    ; 如果按下C键，开始游戏
    CMP AL, 0CH
    JNE CHECK_EXIT_DEBUG
    JMP START_GAME
CHECK_EXIT_DEBUG:
    ; 如果按下F键，退出
    CMP AL, 0FH
    JNE DEBUG_MODE
    JMP EXIT_PROGRAM

START_GAME:
    CALL INIT_GAME
    MOV GAME_STARTED, 1
    CALL GENERATE_NEW_BLOCK
    CALL CHECK_COLLISION
    CMP AL, 0
    JE  MAIN_LOOP_START
    MOV GAME_OVER, 1
    JMP DO_GAME_OVER

MAIN_LOOP_START:
    CALL DRAW_FRAME

MAIN_LOOP:
    CMP GAME_OVER, 1
    JE  DO_GAME_OVER
    
    ; 检查键盘退出
    CALL SCAN_KEYBOARD
    CMP AL, KEY_EXIT
    JNE CONTINUE_GAME
    JMP EXIT_PROGRAM

DO_GAME_OVER:
    JMP GAME_OVER_SCREEN

CONTINUE_GAME:
    ; 处理开关输入
    CALL READ_SWITCHES
    CALL PROCESS_SWITCH_INPUT
    CALL UPDATE_LED_DISPLAY     ; 更新LED显示
    
    CALL FALLING_LOOP
    CALL FIX_BLOCK
    
    CMP BLOCK_COUNT, 100    ; 限制最大到99
    JAE DO_GAME_OVER        ; 超过99结束游戏
    
    CALL CHECK_CLEAR_LINES
    CALL GENERATE_NEW_BLOCK
    
    CALL CHECK_COLLISION
    CMP AL, 0
    JE  NO_COLLISION
    MOV GAME_OVER, 1
    JMP GAME_OVER_SCREEN

NO_COLLISION:
    MOV CX, 200
WAIT_BEFORE_NEXT:
    PUSH CX
    CALL DISP_BUFFER_TO_PORT 
    CALL UPDATE_7SEG_DISPLAY
    ; 处理键盘输入
    INC SCAN_DIVIDER
    TEST SCAN_DIVIDER, 0FH ; 每16次检测一次
    JNZ SKIP_WAIT_KEY
    CALL PROCESS_KEYBOARD_INPUT
SKIP_WAIT_KEY:
    POP CX
    LOOP WAIT_BEFORE_NEXT
    
    JMP MAIN_LOOP

EXIT_PROGRAM:
    MOV AH, 4CH
    INT 21H

;----------------------------------------------------------------------------
; 初始化8255
;----------------------------------------------------------------------------
INIT_8255 PROC
    PUSH AX
    PUSH DX
    MOV DX, MY8255_CON
    MOV AL, 89H        ; A口输出, B口输出, C口输入（C口全输入）
    OUT DX, AL
    POP DX
    POP AX
    RET
INIT_8255 ENDP

;----------------------------------------------------------------------------
; 读取开关状态
; C口高4位(PC4-PC7)连接开关K0-K3
; 返回：AL = 开关状态（高4位，低4位为0）
;----------------------------------------------------------------------------
READ_SWITCHES PROC
    PUSH DX
    MOV DX, MY8255_C
    IN AL, DX          ; 读取C口
    AND AL, 0F0H       ; 只取高4位（开关）
    MOV SWITCH_STATE, AL
    POP DX
    RET
READ_SWITCHES ENDP

;----------------------------------------------------------------------------
; 处理开关输入
; K0：加速下降
; K1：减速下降
; K2：保留
; K3：保留
;----------------------------------------------------------------------------
PROCESS_SWITCH_INPUT PROC
    PUSH AX
    PUSH BX
    
    ; 检查开关状态是否变化
    MOV AL, SWITCH_STATE
    CMP AL, LAST_SWITCH
    JE  NO_SWITCH_CHANGE
    MOV SWITCH_CHANGED, 1
    MOV LAST_SWITCH, AL
    
    ; 处理K0（加速） - PC4
    TEST AL, 10H       ; 检查PC4（K0）
    JZ  CHECK_K1
    ; K0按下，增加速度级别
    CMP SPEED_LEVEL, 3
    JAE CHECK_K1       ; 已经是最高速度
    INC SPEED_LEVEL
    CALL UPDATE_SPEED
    
CHECK_K1:
    ; 处理K1（减速） - PC5
    TEST AL, 20H       ; 检查PC5（K1）
    JZ  NO_SWITCH_CHANGE
    ; K1按下，降低速度级别
    CMP SPEED_LEVEL, 0
    JBE NO_SWITCH_CHANGE ; 已经是最低速度
    DEC SPEED_LEVEL
    CALL UPDATE_SPEED
    
NO_SWITCH_CHANGE:
    POP BX
    POP AX
    RET
PROCESS_SWITCH_INPUT ENDP

;----------------------------------------------------------------------------
; 更新速度级别对应的延时
;----------------------------------------------------------------------------
UPDATE_SPEED PROC
    PUSH AX
    PUSH BX
    PUSH SI
    
    MOV AL, SPEED_LEVEL
    MOV AH, 0
    SHL AX, 1          ; 乘以2（字大小）
    LEA SI, BASE_DELAYS
    ADD SI, AX
    MOV AX, [SI]
    MOV FALL_DELAY, AX
    
    ; 更新LED显示模式
    LEA SI, LED_TABLE
    MOV AL, SPEED_LEVEL
    MOV AH, 0
    ADD SI, AX
    MOV AL, [SI]
    MOV LED_PATTERN, AL
    
    POP SI
    POP BX
    POP AX
    RET
UPDATE_SPEED ENDP

;----------------------------------------------------------------------------
; 更新LED显示
; 使用单独的LED控制函数，可以在需要时调用
;----------------------------------------------------------------------------
UPDATE_LED_DISPLAY PROC
    PUSH AX
    PUSH DX
    
    ; 这里假设LED连接到其他端口
    ; 如果没有单独LED端口，可以通过数码管位选端口的某些位控制
    ; 在实际硬件中实现
    
    POP DX
    POP AX
    RET
UPDATE_LED_DISPLAY ENDP

;----------------------------------------------------------------------------
; 数码管显示子程序
;----------------------------------------------------------------------------
UPDATE_7SEG_DISPLAY PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    
    ; 计算十位和个位
    MOV AL, BLOCK_COUNT
    MOV AH, 0
    MOV BL, 10
    DIV BL              ; AL=十位(商), AH=个位(余数)
    
    MOV CL, AH          ; CL=个位
    MOV CH, AL          ; CH=十位
    
    ; --- 判断显示模式 ---
    CMP BLOCK_COUNT, 10
    JAE SHOW_TWO_DIGITS   ; >=10 显示两位
    
    ; --- 0-9：只显示个位在右边数码管 ---
    ; 数码管2（右边）：显示个位
    MOV DX, MY8255_A
    MOV AL, 0FDH        ; 1111 1101 - 数码管2（右边）
    OUT DX, AL
    
    ; 获取个位的段码
    LEA BX, DTABLE
    MOV AL, CL          ; 个位数字
    AND AL, 0FH
    XLAT                ; 查表获取段码
    
    ; 输出段码
    MOV DX, MY8255_B
    OUT DX, AL
    
    ; 延时
    CALL SEG_DELAY
    
    ; 消隐
    MOV DX, MY8255_B
    MOV AL, 00H
    OUT DX, AL
    
    ; 数码管1（左边）：不显示
    MOV DX, MY8255_A
    MOV AL, 0FEH        ; 数码管1
    OUT DX, AL
    MOV DX, MY8255_B
    MOV AL, 00H         ; 不显示
    OUT DX, AL
    CALL SEG_DELAY
    
    JMP DISPLAY_EXIT

SHOW_TWO_DIGITS:        ; 10-99：显示十位和个位
    ; --- 第一步：显示十位（数码管1 - 左边）---
    MOV DX, MY8255_A
    MOV AL, 0FEH        ; 1111 1110 - 数码管1（左边）
    OUT DX, AL
    
    ; 获取十位的段码
    LEA BX, DTABLE
    MOV AL, CH          ; 十位数字
    AND AL, 0FH
    XLAT                ; 查表获取段码
    
    ; 输出段码
    MOV DX, MY8255_B
    OUT DX, AL
    
    ; 延时
    CALL SEG_DELAY
    
    ; --- 第二步：显示个位（数码管2 - 右边）---
    MOV DX, MY8255_A
    MOV AL, 0FDH        ; 1111 1101 - 数码管2（右边）
    OUT DX, AL
    
    ; 获取个位的段码
    LEA BX, DTABLE
    MOV AL, CL          ; 个位数字
    AND AL, 0FH
    XLAT                ; 查表获取段码
    
    ; 输出段码
    MOV DX, MY8255_B
    OUT DX, AL
    
    ; 延时
    CALL SEG_DELAY
    
    ; 消隐
    MOV DX, MY8255_B
    MOV AL, 00H
    OUT DX, AL

DISPLAY_EXIT:
    POP DX
    POP CX
    POP BX
    POP AX
    RET
UPDATE_7SEG_DISPLAY ENDP

;----------------------------------------------------------------------------
; 数码管显示延时
;----------------------------------------------------------------------------
SEG_DELAY PROC
    PUSH CX
    MOV CX, 40
DL_1: LOOP DL_1
    POP CX
    RET
SEG_DELAY ENDP

;----------------------------------------------------------------------------
; 下落循环（包含速度控制）
;----------------------------------------------------------------------------
FALLING_LOOP PROC
FALL_LOOP:
    CALL DRAW_FRAME
    CALL CAN_MOVE_DOWN
    CMP AL, 1
    JNE FALL_LOOP_END
    
    MOV CX, FALL_DELAY
FALL_DELAY_LOOP:
    PUSH CX
    
    CALL DISP_BUFFER_TO_PORT 
    CALL UPDATE_7SEG_DISPLAY
    
    ; 读取和处理开关输入（每帧都检查）
    INC SPEED_DIVIDER
    MOV AL, SPEED_DIVIDER
    AND AL, 03H       ; 每4次检测一次开关
    CMP AL, 0
    JNE SKIP_SWITCH_SCAN
    CALL READ_SWITCHES
    CALL PROCESS_SWITCH_INPUT
SKIP_SWITCH_SCAN:
    
    ; 处理键盘输入
    INC SCAN_DIVIDER
    MOV AL, SCAN_DIVIDER
    AND AL, 07H       ; 每8次检测一次键盘
    CMP AL, 0
    JNE SKIP_KEY_SCAN
    CALL PROCESS_KEYBOARD_INPUT
SKIP_KEY_SCAN:
    
    POP CX
    LOOP FALL_DELAY_LOOP
    
    INC CUR_ROW
    JMP FALL_LOOP
FALL_LOOP_END:
    RET
FALLING_LOOP ENDP

;----------------------------------------------------------------------------
; 固定当前方块到游戏区域
;----------------------------------------------------------------------------
FIX_BLOCK PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    
    MOV CX, 4
    LEA SI, CUR_BLOCK
FIX_BLOCK_POINTS:
    PUSH CX
    MOV AL, [SI]
    INC SI
    MOV BL, [SI]
    INC SI
    CBW
    MOV DX, AX
    MOV AL, BL
    CBW
    MOV BX, AX
    MOV AL, CUR_COL
    ADD AL, DL
    MOV TEMP_COL, AL
    MOV AL, CUR_ROW
    ADD AL, BL
    MOV TEMP_ROW, AL
    CMP TEMP_ROW, 0
    JL  SKIP_FIX_POINT
    CMP TEMP_ROW, 15
    JG  SKIP_FIX_POINT
    CMP TEMP_COL, 0
    JL  SKIP_FIX_POINT
    CMP TEMP_COL, 15
    JG  SKIP_FIX_POINT
    MOV AL, TEMP_ROW
    XOR AH, AH
    SHL AX, 1
    MOV DI, AX
    MOV AL, TEMP_COL
    XOR AH, AH
    MOV BX, 1
    MOV CL, AL
    SHL BX, CL
    OR GAME_AREA[DI], BX
SKIP_FIX_POINT:
    POP CX
    LOOP FIX_BLOCK_POINTS
    
    ; 增加方块计数（不超过99）
    CMP BLOCK_COUNT, 99
    JAE NO_INC_COUNT
    INC BLOCK_COUNT
NO_INC_COUNT:
    
    CALL DRAW_FRAME
    
    ; 固定后的短暂延时
    MOV CX, 100
FIX_DELAY:
    PUSH CX
    CALL DISP_BUFFER_TO_PORT
    CALL UPDATE_7SEG_DISPLAY
    POP CX
    LOOP FIX_DELAY
    
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
FIX_BLOCK ENDP

;----------------------------------------------------------------------------
; 检查并清除完整行
;----------------------------------------------------------------------------
CHECK_CLEAR_LINES PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    MOV BX, 15
CHECK_EACH_LINE:
    CMP BX, 0
    JGE LINE_STILL_VALID
    JMP CLEAR_DONE
LINE_STILL_VALID:
    MOV AX, BX
    SHL AX, 1
    MOV SI, AX
    MOV AX, GAME_AREA[SI]
    CMP AX, 0FFFFH
    JE  LINE_FULL
    JMP LINE_NOT_FULL
LINE_FULL:
    MOV DI, SI
MOVE_LINES_DOWN:
    CMP DI, 0
    JNE NOT_TOP
    JMP CLEAR_TOP
NOT_TOP:
    MOV AX, GAME_AREA[DI-2]
    MOV GAME_AREA[DI], AX
    SUB DI, 2
    JMP MOVE_LINES_DOWN
CLEAR_TOP:
    MOV WORD PTR GAME_AREA[0], 0
    JMP CHECK_EACH_LINE
LINE_NOT_FULL:
    DEC BX
    JMP CHECK_EACH_LINE
CLEAR_DONE:
    CALL DRAW_FRAME
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
CHECK_CLEAR_LINES ENDP

;----------------------------------------------------------------------------
; 键盘扫描
;----------------------------------------------------------------------------
SCAN_KEYBOARD PROC
    PUSH BX
    PUSH CX
    PUSH DX
    
    CALL KEY_DALLY
    
    ; 第一步：列扫描（通过A口输出）
    MOV CH, 0FEH        ; 起始列扫描信号 11111110
    MOV CL, 00H         ; 列号计数器
    
COLUM_SCAN:
    MOV AL, CH
    MOV DX, MY8255_A    ; A口输出列扫描信号
    OUT DX, AL
    
    ; 短延时等待电平稳定
    PUSH CX
    MOV CX, 10H
STABLE_DELAY:
    LOOP STABLE_DELAY
    POP CX
    
    ; 第二步：读取行状态（通过C口输入）
    MOV DX, MY8255_C
    IN AL, DX
    AND AL, 0FH         ; 只取低4位（行信号）
    
    ; 检查每一行
    CMP AL, 0
    JE  NO_KEY_IN_COL    ; 这一列没有按键
    
    ; 有按键按下，确定是第几行
    MOV BL, AL          ; 保存行状态
    
    ; 检查第0行（PC0）
    TEST BL, 01H
    JZ  ROW_0
    
    ; 检查第1行（PC1）
    TEST BL, 02H
    JZ  ROW_1
    
    ; 检查第2行（PC2）
    TEST BL, 04H
    JZ  ROW_2
    
    ; 检查第3行（PC3）
    TEST BL, 08H
    JZ  ROW_3
    
    JMP NO_KEY_IN_COL

ROW_0:
    MOV AL, 00H         ; 第0行基值
    JMP CALC_KEY

ROW_1:
    MOV AL, 04H         ; 第1行基值
    JMP CALC_KEY

ROW_2:
    MOV AL, 08H         ; 第2行基值
    JMP CALC_KEY

ROW_3:
    MOV AL, 0CH         ; 第3行基值

CALC_KEY:
    ; 键值 = 行基值 + 列号
    ADD AL, CL
    JMP GET_KEYCODE

NO_KEY_IN_COL:
    ; 没有按键，切换到下一列
    INC CL
    CMP CL, 4           ; 只有4列
    JGE NO_KEY_FOUND
    
    ; 循环左移列扫描信号
    MOV AL, CH
    ROL AL, 1
    MOV CH, AL
    JMP COLUM_SCAN

NO_KEY_FOUND:
    MOV AL, 0FFH
    MOV LAST_KEY, AL
    MOV KEY_PRESSED, AL
    MOV KEY_RELEASED, 1
    JMP SCAN_EXIT

GET_KEYCODE:
    CMP AL, LAST_KEY
    JE  SAME_KEY
    CMP KEY_RELEASED, 1
    JNE SAME_KEY
    
    MOV LAST_KEY, AL
    MOV KEY_PRESSED, AL
    MOV KEY_RELEASED, 0
    JMP SCAN_EXIT

SAME_KEY:
    CMP KEY_RELEASED, 1
    JE  SCAN_EXIT
    MOV AL, 0FFH
    MOV KEY_PRESSED, AL

SCAN_EXIT:
    MOV AL, KEY_PRESSED
    POP DX
    POP CX
    POP BX
    RET
SCAN_KEYBOARD ENDP

;----------------------------------------------------------------------------
; 按键延时子程序
;----------------------------------------------------------------------------
KEY_DALLY PROC
    PUSH CX
    PUSH AX
    MOV CX, 0020H
KEY_T1_NB:
    MOV AX, 0010H
KEY_T2_NB:
    DEC AX
    JNZ KEY_T2_NB
    LOOP KEY_T1_NB
    POP AX
    POP CX
    RET
KEY_DALLY ENDP

;----------------------------------------------------------------------------
; 处理键盘输入
;----------------------------------------------------------------------------
PROCESS_KEYBOARD_INPUT PROC
    PUSH AX
    CALL SCAN_KEYBOARD
    CMP AL, 0FFH
    JE  NO_KEY_PRESS
    
    ; 检查功能键
    CMP AL, KEY_LEFT    ; D键（值0DH）
    JE  HANDLE_LEFT
    
    CMP AL, KEY_RIGHT   ; E键（值0EH）
    JE  HANDLE_RIGHT
    
    CMP AL, 0BH         ; 也检查B键
    JE  HANDLE_RIGHT
    
    CMP AL, KEY_EXIT    ; F键（值0FH）
    JNE NO_KEY_PRESS
    JMP EXIT_PROGRAM

HANDLE_LEFT:
    CALL MOVE_LEFT
    JMP NO_KEY_PRESS
HANDLE_RIGHT:
    CALL MOVE_RIGHT
    JMP NO_KEY_PRESS
NO_KEY_PRESS:
    POP AX
    RET
PROCESS_KEYBOARD_INPUT ENDP

;----------------------------------------------------------------------------
; 左移
;----------------------------------------------------------------------------
MOVE_LEFT PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    
    ; 计算尝试移动的位置
    MOV AL, CUR_COL
    DEC AL
    MOV NEW_COL, AL      ; 尝试左移后的列位置
    
    MOV MOVE_OK, 1       ; 假设可以移动
    
    MOV CX, 4
    LEA SI, CUR_BLOCK
CHECK_LEFT_POINTS:
    PUSH CX
    
    ; 获取方块的偏移坐标
    MOV AL, [SI]         ; X偏移
    INC SI
    MOV BL, [SI]         ; Y偏移
    INC SI
    
    ; 计算移动后的列位置
    MOV AL, NEW_COL
    ADD AL, [SI-2]       ; NEW_COL + X偏移
    MOV CHECK_COL, AL
    
    ; 计算移动后的行位置
    MOV AL, CUR_ROW
    ADD AL, BL           ; CUR_ROW + Y偏移
    MOV CHECK_ROW, AL
    
    ; 检查左边界
    CMP CHECK_COL, 0
    JL  LEFT_FAIL
    
    ; 检查是否与已有方块碰撞
    MOV AL, CHECK_ROW
    MOV TEMP_ROW, AL
    MOV AL, CHECK_COL
    MOV TEMP_COL, AL
    CALL GET_GAME_AREA_POINT
    CMP AL, 1
    JE  LEFT_FAIL
    
    POP CX
    LOOP CHECK_LEFT_POINTS
    JMP LEFT_SUCCESS

LEFT_FAIL:
    POP CX
    MOV MOVE_OK, 0

LEFT_SUCCESS:
    CMP MOVE_OK, 1
    JNE MOVE_LEFT_EXIT
    
    ; 所有检查通过，执行左移
    MOV AL, NEW_COL
    MOV CUR_COL, AL
    CALL DRAW_FRAME

MOVE_LEFT_EXIT:
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
MOVE_LEFT ENDP

;----------------------------------------------------------------------------
; 右移
;----------------------------------------------------------------------------
MOVE_RIGHT PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    
    ; 计算尝试移动的位置
    MOV AL, CUR_COL
    INC AL
    MOV NEW_COL, AL      ; 尝试右移后的列位置
    
    MOV MOVE_OK, 1       ; 假设可以移动
    
    MOV CX, 4
    LEA SI, CUR_BLOCK
CHECK_RIGHT_POINTS:
    PUSH CX
    
    ; 获取方块的偏移坐标
    MOV AL, [SI]         ; X偏移
    INC SI
    MOV BL, [SI]         ; Y偏移
    INC SI
    
    ; 计算移动后的列位置
    MOV AL, NEW_COL
    ADD AL, [SI-2]       ; NEW_COL + X偏移
    MOV CHECK_COL, AL
    
    ; 计算移动后的行位置
    MOV AL, CUR_ROW
    ADD AL, BL           ; CUR_ROW + Y偏移
    MOV CHECK_ROW, AL
    
    ; 检查右边界
    CMP CHECK_COL, 15
    JG  RIGHT_FAIL
    
    ; 检查是否与已有方块碰撞
    MOV AL, CHECK_ROW
    MOV TEMP_ROW, AL
    MOV AL, CHECK_COL
    MOV TEMP_COL, AL
    CALL GET_GAME_AREA_POINT
    CMP AL, 1
    JE  RIGHT_FAIL
    
    POP CX
    LOOP CHECK_RIGHT_POINTS
    JMP RIGHT_SUCCESS

RIGHT_FAIL:
    POP CX
    MOV MOVE_OK, 0

RIGHT_SUCCESS:
    CMP MOVE_OK, 1
    JNE MOVE_RIGHT_EXIT
    
    ; 所有检查通过，执行右移
    MOV AL, NEW_COL
    MOV CUR_COL, AL
    CALL DRAW_FRAME

MOVE_RIGHT_EXIT:
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
MOVE_RIGHT ENDP

;----------------------------------------------------------------------------
; 绘制游戏画面
;----------------------------------------------------------------------------
DRAW_FRAME PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    ; 清空显示缓冲区
    MOV CX, 16
    LEA DI, DISP_BUFFER
    XOR AX, AX
    REP STOSW

    ; 复制游戏区域到显示缓冲区
    MOV CX, 16
    MOV SI, 0
COPY_GAME_AREA:
    MOV AX, GAME_AREA[SI]
    MOV DISP_BUFFER[SI], AX
    ADD SI, 2
    LOOP COPY_GAME_AREA
    
    ; 绘制当前方块
    MOV CX, 4
    LEA SI, CUR_BLOCK
DRAW_BLOCK_POINTS:
    PUSH CX
    MOV AL, [SI]        ; X偏移
    INC SI
    MOV BL, [SI]        ; Y偏移
    INC SI
    CBW
    MOV DX, AX
    MOV AL, BL
    CBW
    MOV BX, AX
    MOV AL, CUR_COL
    ADD AL, DL          ; CUR_COL + X偏移
    MOV TEMP_COL, AL
    MOV AL, CUR_ROW
    ADD AL, BL          ; CUR_ROW + Y偏移
    MOV TEMP_ROW, AL
    
    ; 边界检查
    CMP TEMP_ROW, 0
    JL  SKIP_DRAW
    CMP TEMP_ROW, 15
    JG  SKIP_DRAW
    CMP TEMP_COL, 0
    JL  SKIP_DRAW
    CMP TEMP_COL, 15
    JG  SKIP_DRAW
    
    ; 在缓冲区中设置对应的位
    MOV AL, TEMP_ROW
    XOR AH, AH
    SHL AX, 1
    MOV DI, AX
    MOV AL, TEMP_COL
    XOR AH, AH
    MOV DX, 1
    MOV CL, AL
    SHL DX, CL
    OR DISP_BUFFER[DI], DX
    
SKIP_DRAW:
    POP CX
    LOOP DRAW_BLOCK_POINTS
    
    ; 输出到端口
    CALL DISP_BUFFER_TO_PORT
    
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_FRAME ENDP

;----------------------------------------------------------------------------
; 检查是否能向下移动
;----------------------------------------------------------------------------
CAN_MOVE_DOWN PROC
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    
    MOV AL, CUR_ROW
    INC AL
    MOV CHECK_ROW, AL    ; 尝试向下移动一行
    
    MOV CX, 4
    LEA SI, CUR_BLOCK
CHECK_DOWN_POINTS:
    PUSH CX
    MOV AL, [SI]
    INC SI
    MOV BL, [SI]
    INC SI
    CBW
    MOV DX, AX
    MOV AL, BL
    CBW
    MOV BX, AX
    MOV AL, CUR_COL
    ADD AL, DL
    MOV CHECK_COL, AL    ; 当前列 + X偏移
    MOV AL, CHECK_ROW
    ADD AL, BL           ; 下一行 + Y偏移
    MOV TEMP_ROW, AL
    MOV AL, CHECK_COL
    MOV TEMP_COL, AL
    
    ; 检查下边界
    CMP TEMP_ROW, 16
    JAE CANT_MOVE_DOWN_POINT
    
    ; 检查碰撞
    CALL GET_GAME_AREA_POINT
    CMP AL, 1
    JE  CANT_MOVE_DOWN_POINT
    
    POP CX
    LOOP CHECK_DOWN_POINTS
    
    ; 可以向下移动
    MOV AL, 1
    JMP CAN_MOVE_DOWN_EXIT

CANT_MOVE_DOWN_POINT:
    POP CX
    MOV AL, 0

CAN_MOVE_DOWN_EXIT:
    POP SI
    POP DX
    POP CX
    POP BX
    RET
CAN_MOVE_DOWN ENDP

;----------------------------------------------------------------------------
; 获取游戏区域指定点的状态
;----------------------------------------------------------------------------
GET_GAME_AREA_POINT PROC
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    
    ; 边界检查
    MOV AL, TEMP_ROW
    CMP AL, 0
    JL  NO_POINT
    CMP AL, 15
    JG  NO_POINT
    
    MOV AL, TEMP_COL
    CMP AL, 0
    JL  NO_POINT
    CMP AL, 15
    JG  NO_POINT
    
    ; 计算位掩码
    MOV AL, TEMP_ROW
    XOR AH, AH
    SHL AX, 1
    MOV SI, AX
    MOV DX, GAME_AREA[SI]
    
    MOV AL, TEMP_COL
    XOR AH, AH
    MOV BX, 1
    MOV CL, AL
    SHL BX, CL
    
    ; 检查该位是否为1
    TEST DX, BX
    JZ  NO_POINT
    MOV AL, 1
    JMP GET_POINT_EXIT

NO_POINT:
    MOV AL, 0

GET_POINT_EXIT:
    POP SI
    POP DX
    POP CX
    POP BX
    RET
GET_GAME_AREA_POINT ENDP

;----------------------------------------------------------------------------
; 检查碰撞
;----------------------------------------------------------------------------
CHECK_COLLISION PROC
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    
    MOV CX, 4
    LEA SI, CUR_BLOCK
CHECK_COL_POINTS:
    PUSH CX
    MOV AL, [SI]
    INC SI
    MOV BL, [SI]
    INC SI
    CBW
    MOV DX, AX
    MOV AL, BL
    CBW
    MOV BX, AX
    MOV AL, CUR_COL
    ADD AL, DL
    MOV TEMP_COL, AL
    MOV AL, CUR_ROW
    ADD AL, BL
    MOV TEMP_ROW, AL
    
    ; 边界检查
    CMP TEMP_ROW, 0
    JL  COLLISION_TRUE
    CMP TEMP_ROW, 15
    JG  COLLISION_TRUE
    CMP TEMP_COL, 0
    JL  COLLISION_TRUE
    CMP TEMP_COL, 15
    JG  COLLISION_TRUE
    
    ; 碰撞检查
    CALL GET_GAME_AREA_POINT
    CMP AL, 1
    JE  COLLISION_TRUE
    
    POP CX
    LOOP CHECK_COL_POINTS
    
    ; 没有碰撞
    MOV AL, 0
    JMP CHECK_COL_EXIT

COLLISION_TRUE:
    POP CX
    MOV AL, 1

CHECK_COL_EXIT:
    POP SI
    POP DX
    POP CX
    POP BX
    RET
CHECK_COLLISION ENDP

;----------------------------------------------------------------------------
; 随机数生成
;----------------------------------------------------------------------------
RANDOM_NUMBER PROC
    MOV AX, RAND_SEED
    MOV BX, 25173
    MUL BX
    ADD AX, 13849
    MOV RAND_SEED, AX
    MOV AL, AH
    RET
RANDOM_NUMBER ENDP

;----------------------------------------------------------------------------
; 显示欢迎边框
;----------------------------------------------------------------------------
SHOW_WELCOME_BORDER PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DI
    
    ; 清空显示缓冲区
    MOV CX, 16
    LEA DI, DISP_BUFFER
    XOR AX, AX
    REP STOSW
    
    ; 绘制边框
    MOV CX, 16
    MOV BX, 0
DRAW_WELCOME:
    MOV SI, BX
    SHL SI, 1
    CMP BX, 0
    JE  DRAW_FULL_WELCOME
    CMP BX, 15
    JE  DRAW_FULL_WELCOME
    ; 绘制左右边框
    MOV AX, 8000H        ; 最左列
    OR  DISP_BUFFER[SI], AX
    MOV AX, 0001H        ; 最右列
    OR  DISP_BUFFER[SI], AX
    JMP NEXT_WELCOME
DRAW_FULL_WELCOME:
    ; 绘制上下边框（全亮）
    MOV WORD PTR DISP_BUFFER[SI], 0FFFFH
NEXT_WELCOME:
    INC BX
    LOOP DRAW_WELCOME
    
    ; 输出到端口
    CALL DISP_BUFFER_TO_PORT
    
    POP DI
    POP SI
    POP CX
    POP BX
    POP AX
    RET
SHOW_WELCOME_BORDER ENDP

;----------------------------------------------------------------------------
; 初始化游戏
;----------------------------------------------------------------------------
INIT_GAME PROC
    PUSH AX
    PUSH CX
    PUSH DI
    
    ; 清空游戏区域
    MOV CX, 16
    LEA DI, GAME_AREA
    XOR AX, AX
    REP STOSW
    
    ; 清空显示缓冲区
    MOV CX, 16
    LEA DI, DISP_BUFFER
    XOR AX, AX
    REP STOSW
    
    ; 初始化游戏状态
    MOV GAME_OVER, 0
    MOV GAME_STARTED, 0
    MOV SPEED_LEVEL, 2      ; 默认中速
    CALL UPDATE_SPEED       ; 更新速度延时
    MOV CUR_ROW, 0
    MOV CUR_COL, 0
    MOV LAST_KEY, 0FFH
    MOV KEY_PRESSED, 0FFH
    MOV KEY_RELEASED, 1
    MOV RAND_SEED, 1234
    
    ; 初始化开关状态
    MOV SWITCH_STATE, 0
    MOV LAST_SWITCH, 0
    MOV SWITCH_CHANGED, 0
    MOV LED_PATTERN, 0111B  ; 对应速度级别2
    
    ; 重置方块计数
    MOV BLOCK_COUNT, 0
    
    POP DI
    POP CX
    POP AX
    RET
INIT_GAME ENDP

;----------------------------------------------------------------------------
; 生成新方块
;----------------------------------------------------------------------------
GENERATE_NEW_BLOCK PROC
    CALL RANDOM_NUMBER
    AND AL, 07H          ; 0-7种形状
    CMP AL, 7
    JB  SHAPE_OK
    MOV AL, 0
SHAPE_OK:
    MOV CUR_SHAPE, AL
    
    CALL RANDOM_NUMBER
    AND AL, 03H          ; 0-3种旋转
    MOV CUR_ROT, AL
    
    CALL RANDOM_NUMBER
    AND AL, 07H
    ADD AL, 3            ; 初始列位置偏移
    MOV CUR_COL, AL
    
    MOV CUR_ROW, 1       ; 初始行位置
    
    ; 加载方块数据
    CALL LOAD_CURRENT_BLOCK
    RET
GENERATE_NEW_BLOCK ENDP

;----------------------------------------------------------------------------
; 加载当前方块数据
;----------------------------------------------------------------------------
LOAD_CURRENT_BLOCK PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH SI
    PUSH DI
    
    ; 计算形状表偏移
    MOV AL, CUR_SHAPE
    MOV BL, 32           ; 每个形状32字节（4种旋转×8字节）
    MUL BL
    MOV BX, AX
    
    ; 加上旋转偏移
    MOV AL, CUR_ROT
    MOV AH, 0
    SHL AX, 1
    SHL AX, 1
    SHL AX, 1           ; ×8
    ADD BX, AX
    
    ; 复制方块数据到CUR_BLOCK
    LEA SI, SHAPE_TABLE
    ADD SI, BX
    LEA DI, CUR_BLOCK
    MOV CX, 8
COPY_BLOCK_DATA:
    MOV AL, [SI]
    MOV [DI], AL
    INC SI
    INC DI
    LOOP COPY_BLOCK_DATA
    
    POP DI
    POP SI
    POP CX
    POP BX
    POP AX
    RET
LOAD_CURRENT_BLOCK ENDP

;----------------------------------------------------------------------------
; 游戏结束时的数码管显示
;----------------------------------------------------------------------------
DISPLAY_GAME_OVER_SCORE PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    
    ; 计算当前分数的十位和个位
    MOV AL, BLOCK_COUNT
    MOV AH, 0
    MOV BL, 10
    DIV BL              ; AL=十位, AH=个位
    
    MOV CL, AH          ; CL=个位
    MOV CH, AL          ; CH=十位
    
    ; 数码管1（左边）：显示十位
    MOV DX, MY8255_A
    MOV AL, 0FEH        ; 数码管1
    OUT DX, AL
    LEA BX, DTABLE
    MOV AL, CH          ; 十位数字
    AND AL, 0FH
    XLAT
    MOV DX, MY8255_B
    OUT DX, AL
    CALL SEG_DELAY
    
    ; 数码管2（右边）：显示个位
    MOV DX, MY8255_A
    MOV AL, 0FDH        ; 数码管2
    OUT DX, AL
    LEA BX, DTABLE
    MOV AL, CL          ; 个位数字
    AND AL, 0FH
    XLAT
    MOV DX, MY8255_B
    OUT DX, AL
    CALL SEG_DELAY
    
    ; 消隐
    MOV DX, MY8255_B
    MOV AL, 00H
    OUT DX, AL
    
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DISPLAY_GAME_OVER_SCORE ENDP

;----------------------------------------------------------------------------
; 游戏结束画面
;----------------------------------------------------------------------------
GAME_OVER_SCREEN:
    ; 清空显示缓冲区
    MOV CX, 16
    LEA DI, DISP_BUFFER
    XOR AX, AX
    REP STOSW
    
    ; 绘制游戏结束边框
    MOV CX, 16
    MOV BX, 0
DRAW_GAME_OVER_BORDER:
    MOV SI, BX
    SHL SI, 1
    CMP BX, 0
    JE  DRAW_FULL_GO_LINE
    CMP BX, 15
    JE  DRAW_FULL_GO_LINE
    ; 绘制左右边框
    MOV AX, 8000H
    OR  DISP_BUFFER[SI], AX
    MOV AX, 0001H
    OR  DISP_BUFFER[SI], AX
    JMP NEXT_GO_LINE
DRAW_FULL_GO_LINE:
    ; 绘制上下边框
    MOV WORD PTR DISP_BUFFER[SI], 0FFFFH
NEXT_GO_LINE:
    INC BX
    LOOP DRAW_GAME_OVER_BORDER
    
    ; 在中间两行显示特殊图案
    MOV WORD PTR DISP_BUFFER[7*2], 06600H
    MOV WORD PTR DISP_BUFFER[8*2], 09900H

GAME_OVER_LOOP:
    CALL DISP_BUFFER_TO_PORT
    CALL DISPLAY_GAME_OVER_SCORE   ; 显示分数
    CALL SCAN_KEYBOARD
    CMP AL, KEY_START    ; C键重新开始
    JNE CHECK_EXIT_GO
    JMP START
CHECK_EXIT_GO:
    CMP AL, KEY_EXIT     ; F键退出
    JNE GAME_OVER_LOOP
    JMP EXIT_PROGRAM

;----------------------------------------------------------------------------
; 显示缓冲区输出到端口
;----------------------------------------------------------------------------
DISP_BUFFER_TO_PORT PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    MOV CX, 16          ; 16行
    XOR BX, BX          ; 行计数器
    LEA SI, DISP_BUFFER ; 显示缓冲区指针

ROW_SCAN_LOOP:
    ; 选择行（0-7或8-15）
    CMP BX, 7
    JBE ROW_0_7
ROW_8_15:
    MOV DX, ROW2
    MOV AX, 1
    PUSH CX
    MOV CL, BL
    SUB CL, 8           ; 对于行8-15，减去8
    SHL AX, CL
    POP CX
    OUT DX, AL
    JMP DATA_OUT

ROW_0_7:
    MOV DX, ROW1
    MOV AX, 1
    PUSH CX
    MOV CL, BL
    SHL AX, CL
    POP CX
    OUT DX, AL

DATA_OUT:
    ; 输出列数据（分高低8位）
    MOV AX, [SI]
    
    ; 输出低8位到COL1
    PUSH AX
    NOT AL              ; 取反（0点亮，1熄灭）
    MOV DX, COL1
    OUT DX, AL
    POP AX
    
    ; 输出高8位到COL2
    MOV AL, AH
    NOT AL
    MOV DX, COL2
    OUT DX, AL
    
    ; 行扫描延时
    PUSH CX
    MOV CX, 15
DELAY_INT:
    LOOP DELAY_INT
    POP CX
    
    ; 关闭当前行
    MOV DX, ROW1
    MOV AL, 0
    OUT DX, AL
    MOV DX, ROW2
    MOV AL, 0
    OUT DX, AL
    
    ; 移动到下一行
    ADD SI, 2
    INC BX
    LOOP ROW_SCAN_LOOP
    
    ; 全局消隐
    MOV DX, ROW1
    MOV AL, 0
    OUT DX, AL
    MOV DX, ROW2
    MOV AL, 0
    OUT DX, AL
    MOV DX, COL1
    MOV AL, 0FFH
    OUT DX, AL
    MOV DX, COL2
    MOV AL, 0FFH
    OUT DX, AL

    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DISP_BUFFER_TO_PORT ENDP

CODE    ENDS
END START