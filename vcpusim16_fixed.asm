; =============================================================================
; VCPU-16 SIMULATOR - Trinh Gia Lap CPU Ao 16-Bit
; =============================================================================
; Mon    : Kien Truc May Tinh
; De tai : Bai 1 - Trinh gia lap CPU don gian + tap lenh hop ngu
; Cong cu: emu8086 (x86 16-bit Assembly)
;
; MO TA:
;   Chuong trinh nay mo phong mot CPU ao ten "VCPU-16" chay ben trong
;   moi truong emu8086. VCPU-16 la CPU do nhom tu thiet ke voi:
;     - 4 thanh ghi da nang: R0, R1, R2, R3 (moi cai 16-bit)
;     - 3 thanh ghi dac biet: PC (Program Counter), IR (Instruction Register),
;                              FLAGS (co trang thai)
;     - Bo nho gia lap (Virtual RAM): 64 o, moi o 16-bit
;     - Tap lenh ISA rieng gom 10 lenh
;
; DINH DANG LENH (Instruction Format) - 16-bit:
;   [Bits 15-12] = OPCODE (4 bit) - ma thao tac
;   [Bits 11-10] = RD     (2 bit) - thanh ghi dich (destination)
;   [Bits  9- 8] = RS     (2 bit) - thanh ghi nguon (source)
;   [Bits  7- 0] = IMM8   (8 bit) - gia tri tuc thi hoac dia chi
;
; BANG TAP LENH (ISA - Instruction Set Architecture) cua VCPU-16:
;   Opcode | Ma hex | Ten lenh | Cu phap       | Mo ta
;   -------|--------|----------|---------------|----------------------------
;     0000 | 0x0    | HALT     | HALT          | Dung CPU
;     0001 | 0x1    | LOADI    | LOADI Rd, imm | Rd = imm (nap hang so)
;     0010 | 0x2    | LOAD     | LOAD  Rd, [a] | Rd = MEM[a] (doc bo nho)
;     0011 | 0x3    | STORE    | STORE [a], Rs | MEM[a] = Rs (ghi bo nho)
;     0100 | 0x4    | MOV      | MOV   Rd, Rs  | Rd = Rs (sao chep)
;     0101 | 0x5    | ADD      | ADD   Rd, Rs  | Rd = Rd + Rs
;     0110 | 0x6    | SUB      | SUB   Rd, Rs  | Rd = Rd - Rs
;     0111 | 0x7    | INC      | INC   Rd      | Rd = Rd + 1
;     1000 | 0x8    | DEC      | DEC   Rd      | Rd = Rd - 1
;     1001 | 0x9    | CMP      | CMP   Rd, Rs  | Cap nhat FLAGS (Rd-Rs)
;     1010 | 0xA    | JMP      | JMP   addr    | PC = addr (nhay vo dieu kien)
;     1011 | 0xB    | JZ       | JZ    addr    | Neu Z=1 thi PC = addr
;     1100 | 0xC    | JNZ      | JNZ   addr    | Neu Z=0 thi PC = addr
;     1101 | 0xD    | JN       | JN    addr    | Neu N=1 thi PC = addr (am)
;     1110 | 0xE    | PUSH     | PUSH  Rs      | Stack[SP--] = Rs
;     1111 | 0xF    | POP      | POP   Rd      | Rd = Stack[++SP]
;
; CO TRANG THAI (FLAGS):
;   Bit 0 = Z (Zero Flag)    : 1 neu ket qua = 0
;   Bit 1 = N (Negative Flag): 1 neu ket qua < 0
;   Bit 2 = C (Carry Flag)   : 1 neu co nho/muon
; =============================================================================

.MODEL SMALL
.STACK 200h

; =============================================================================
; DOAN DU LIEU (DATA SEGMENT)
; =============================================================================
.DATA

; --- Thanh ghi cua VCPU-16 ---
; Bon thanh ghi da nang, moi cai chiem 1 word (2 bytes) trong RAM x86
vcpu_R0     DW 0        ; Thanh ghi R0 (general purpose)
vcpu_R1     DW 0        ; Thanh ghi R1 (general purpose)
vcpu_R2     DW 0        ; Thanh ghi R2 (general purpose)
vcpu_R3     DW 0        ; Thanh ghi R3 (general purpose)

vcpu_PC     DW 0        ; Program Counter - dia chi lenh dang thuc thi
vcpu_IR     DW 0        ; Instruction Register - lenh dang chua (16-bit)
vcpu_FLAGS  DW 0        ; Thanh ghi co: bit0=Z, bit1=N, bit2=C
vcpu_SP     DW 15       ; Stack Pointer - tro vao dinh stack (ban dau = 15)

; --- Bo nho gia lap cua VCPU-16 ---
; 64 o nho (word), moi o 16-bit
; Vung [0..31]  = Code Segment (chua lenh chuong trinh)
; Vung [32..47] = Data Segment (chua bien, du lieu)
; Vung [48..63] = Stack Segment (LIFO, dung cho PUSH/POP)
vcpu_MEM    DW 64 DUP(0)   ; 64 words = 128 bytes bo nho ao

; --- Bien dieu khien gia lap ---
vcpu_running    DB 1    ; 1 = dang chay, 0 = da dung (HALT)
current_demo    DB 0    ; So thu tu demo dang chay (0,1,2,3)
step_count      DW 0    ; Dem so buoc FDE da thuc hien

; --- Mang con tro thanh ghi (dung de truy cap Rd/Rs theo so hieu) ---
; reg_table[0] = offset cua R0, [1] = R1, [2] = R2, [3] = R3
reg_table   DW vcpu_R0, vcpu_R1, vcpu_R2, vcpu_R3

; =============================================================================
; CAC CHUOI THONG BAO HIEN THI
; =============================================================================
msg_banner      DB '============================================', 13, 10
                DB '   VCPU-16 SIMULATOR - Tring Gia Lap CPU ao', 13, 10
                DB '   Mon: Kien Truc May Tinh - Bai 1         ', 13, 10
                DB '============================================', 13, 10, '$'

msg_menu        DB 13, 10
                DB '[MENU CHINH] Chon chuong trinh demo:', 13, 10
                DB '  1. Tinh tong: 1+2+3+4+5 = 15', 13, 10
                DB '  2. Tim gia tri lon nhat trong mang', 13, 10
                DB '  3. Dem nguoc tu 5 ve 0', 13, 10
                DB '  4. Tinh giai thua 5! = 120', 13, 10
                DB '  0. Thoat', 13, 10
                DB 'Lua chon: $'

msg_run_header  DB 13, 10, '--- VCPU-16 DANG THUC THI ---', 13, 10
                DB 'Buoc | PC | IR(hex) | R0    R1    R2    R3  | FLAGS', 13, 10
                DB '-----|----|---------|-----------------------|------', 13, 10, '$'

msg_halt        DB '--- CPU DUNG (HALT) ---', 13, 10, '$'
msg_result      DB 'KET QUA cuoi: R0=$'
msg_newline     DB 13, 10, '$'
msg_separator   DB '-------------------------------------------', 13, 10, '$'
msg_step_prefix DB 'B$'           ; Tien to "Buoc"
msg_pc_prefix   DB ' |$'
msg_space5      DB '     $'
msg_comma       DB ',$'
msg_zflag       DB ' Z=$'
msg_nflag       DB ' N=$'
msg_press_key   DB 13, 10, '[Nhan phim bat ky de chay buoc tiep (Q=thoat)]...', 13, 10, '$'
msg_demo_done   DB 13, 10, '=== HOAN THANH! Nhan phim de ve menu... ===', 13, 10, '$'
msg_goodbye     DB 13, 10, 'Tam biet! Da thoat VCPU-16 Simulator.', 13, 10, '$'
msg_invalid     DB 13, 10, 'Lua chon khong hop le, vui long thu lai!', 13, 10, '$'

; --- Ten opcode de hien thi ---
opcode_names    DB 'HALT  $'   ; 0x0
                DB 'LOADI $'   ; 0x1
                DB 'LOAD  $'   ; 0x2
                DB 'STORE $'   ; 0x3
                DB 'MOV   $'   ; 0x4
                DB 'ADD   $'   ; 0x5
                DB 'SUB   $'   ; 0x6
                DB 'INC   $'   ; 0x7
                DB 'DEC   $'   ; 0x8
                DB 'CMP   $'   ; 0x9
                DB 'JMP   $'   ; 0xA
                DB 'JZ    $'   ; 0xB
                DB 'JNZ   $'   ; 0xC
                DB 'JN    $'   ; 0xD
                DB 'PUSH  $'   ; 0xE
                DB 'POP   $'   ; 0xF

; Bo dem so tam thoi de in so
num_buf         DB 7 DUP(' '), '$'

; =============================================================================
; DOAN LENH (CODE SEGMENT)
; =============================================================================
.CODE
MAIN PROC
    ; --- Khoi tao Data Segment ---
    MOV  AX, @DATA
    MOV  DS, AX

    ; --- Hien thi banner chao mung ---
    LEA  DX, msg_banner
    CALL print_str
    ; =========================================================================
    ; VONG LAP MENU CHINH
    ; =========================================================================
main_loop:
    ; Hien thi menu chon demo
    LEA  DX, msg_menu
    CALL print_str

    ; Nhan phim nhan tu ban phim (INT 21h - AH=01h)
    MOV  AH, 01h
    INT  21h            ; Ket qua ky tu ASCII tra ve trong AL

    ; Kiem tra lua chon
    CMP  AL, '0'
    JE   exit_program   ; '0' = thoat

    CMP  AL, '1'
    JE   run_demo1      ; '1' = demo tong

    CMP  AL, '2'
    JE   run_demo2      ; '2' = demo tim max

    CMP  AL, '3'
    JE   run_demo3      ; '3' = demo dem nguoc

    CMP  AL, '4'
    JE   run_demo4      ; '4' = demo giai thua

    ; Lua chon khong hop le
    LEA  DX, msg_invalid
    CALL print_str
    JMP  main_loop

; =============================================================================
; NAP VA CHAY CAC CHUONG TRINH DEMO
; =============================================================================

; --- Demo 1: Tinh tong 1+2+3+4+5 = 15 ---
; Thuat toan: R0 = 0 (tong), R1 = 1 (bien dem), R2 = 5 (gioi han)
; Vong lap: R0 = R0 + R1; R1 = R1 + 1; neu R1 > R2 thi dung
;
; Chuong trinh VCPU-16 (ma may hex, moi lenh 16-bit = 1 word):
;   PC=0: LOADI R0, 0     -> 0x1000  (Opcode=1, Rd=00, imm=0)
;   PC=1: LOADI R1, 1     -> 0x1401  (Opcode=1, Rd=01, imm=1)
;   PC=2: LOADI R2, 5     -> 0x1805  (Opcode=1, Rd=10, imm=5)
;   PC=3: ADD   R0, R1    -> 0x5004  (Opcode=5, Rd=00, Rs=01)
;   PC=4: INC   R1        -> 0x7400  (Opcode=7, Rd=01)
;   PC=5: CMP   R1, R2    -> 0x9408  (Opcode=9, Rd=01, Rs=10)
;   PC=6: JNZ   3         -> 0xC003  (Opcode=C, addr=3; nhay neu R1!=R2)
;   PC=7: HALT            -> 0x0000  (Opcode=0)
;
; Giai thich ma hoa:
;   0x1000 = 0001 0000 0000 0000b -> Op=0001(LOADI), Rd=00(R0), imm=00000000(0)
;   0x1401 = 0001 0100 0000 0001b -> Op=0001(LOADI), Rd=01(R1), imm=00000001(1)
;   0x1805 = 0001 1000 0000 0101b -> Op=0001(LOADI), Rd=10(R2), imm=00000101(5)
;   0x5004 = 0101 0000 0000 0100b -> Op=0101(ADD),   Rd=00(R0), Rs=01(R1)
;   0x7400 = 0111 0100 0000 0000b -> Op=0111(INC),   Rd=01(R1)
;   0x9408 = 1001 0100 0000 1000b -> Op=1001(CMP),   Rd=01(R1), Rs=10(R2)
;   0xC003 = 1100 0000 0000 0011b -> Op=1100(JNZ),   addr=3
;   0x0000 = HALT
run_demo1:
    CALL reset_vcpu
    ; Nap ma may cua chuong trinh vao vcpu_MEM[0..7]
    LEA  BX, vcpu_MEM
    MOV  WORD PTR [BX + 0*2],  1000h   ; PC=0: LOADI R0, 0
    MOV  WORD PTR [BX + 1*2],  1401h   ; PC=1: LOADI R1, 1
    MOV  WORD PTR [BX + 2*2],  1805h   ; PC=2: LOADI R2, 5
    MOV  WORD PTR [BX + 3*2],  9408h   ; PC=3: ADD R0, R1
    MOV  WORD PTR [BX + 4*2], 0B009h   ; PC=4: INC R1
    MOV  WORD PTR [BX + 5*2], 5004h   ; PC=5: CMP R1, R2
    MOV  WORD PTR [BX + 6*2], 7400h
    MOV  WORD PTR [BX + 7*2], 0A003h   ; PC=7: ADD R0, R1
    MOV  WORD PTR [BX + 8*2], 0000h   ; PC=8: INC R1
    MOV  WORD PTR [BX + 9*2],  0000h; PC=9: JMP 3
    CALL run_vcpu
    JMP  main_loop

; --- Demo 2: Tim gia tri lon nhat trong mang [3,7,2,9,5] ---
; Thuat toan: R0 = MEM[32] (max), R1 = dem vong, R2 = MEM[dia chi hien tai]
; Mang duoc luu tai dia chi ao 32..36 trong vcpu_MEM
;
; Chuong trinh VCPU-16:
;   PC=0:  LOADI R0, 3     -> 0x1003  Nap phan tu dau tien lam max tam
;   PC=1:  LOADI R1, 1     -> 0x1401  R1 = chi so = 1 (bat dau tu phan tu 2)
;   PC=2:  LOAD  R2, [33]  -> 0x2821  R2 = MEM[33] = phan tu tiep theo (33=0x21)
;   PC=3:  CMP   R0, R2    -> 0x9002  So sanh max voi phan tu hien tai
;   PC=4:  JN    7         -> 0xD007  Neu R0<R2 (N=1) thi nhay toi PC=7 (cap nhat max)
;   PC=5:  INC   R1        -> 0x7400  R1++ (chuyen sang phan tu ke)
;   PC=6:  CMP   R1, ???   -> dung R3 lam gioi han
;   ... (don gian hoa: dung dem cung 4 buoc so sanh)
;
; Cach don gian hon (unroll loop): so sanh tuan tu 5 phan tu
;   MEM[32]=3, MEM[33]=7, MEM[34]=2, MEM[35]=9, MEM[36]=5
;   PC=0:  LOAD  R0, [32]  -> 0x2020  R0 = MEM[32] = 3 (max ban dau)
;   PC=1:  LOAD  R1, [33]  -> 0x2421  R1 = MEM[33] = 7
;   PC=2:  CMP   R0, R1    -> 0x9004  So sanh R0 voi R1
;   PC=3:  JN    6         -> 0xD006  Neu R0 < R1 (N=1): nhay den PC=6 (R0=R1)
;   PC=4:  JMP   7         -> 0xA007  Nguoc lai: bo qua, nhay toi PC=7
;   PC=5:  JMP   7         -> (du phong)
;   PC=6:  MOV   R0, R1    -> 0x4001  R0 = R1 (cap nhat max)
;   PC=7:  LOAD  R1, [34]  -> 0x2422  R1 = MEM[34] = 2
;   PC=8:  CMP   R0, R1    -> 0x9004
;   PC=9:  JN    12        -> 0xD00C
;   PC=10: JMP   13        -> 0xA00D
;   PC=11: JMP   13
;   PC=12: MOV   R0, R1    -> 0x4001
;   PC=13: LOAD  R1, [35]  -> 0x2423  R1 = MEM[35] = 9
;   PC=14: CMP   R0, R1    -> 0x9004
;   PC=15: JN    18        -> 0xD012
;   PC=16: JMP   19        -> 0xA013
;   PC=17: JMP   19
;   PC=18: MOV   R0, R1    -> 0x4001
;   PC=19: LOAD  R1, [36]  -> 0x2424  R1 = MEM[36] = 5
;   PC=20: CMP   R0, R1    -> 0x9004
;   PC=21: JN    24        -> 0xD018
;   PC=22: JMP   25        -> 0xA019
;   PC=23: JMP   25
;   PC=24: MOV   R0, R1    -> 0x4001
;   PC=25: HALT            -> 0x0000  Ket qua trong R0 = 9
run_demo2:
    CALL reset_vcpu
    LEA  BX, vcpu_MEM
    ; Nap du lieu mang vao vung Data Segment (dia chi ao 32..36)
    MOV  WORD PTR [BX + 32*2], 3   ; MEM[32] = 3
    MOV  WORD PTR [BX + 33*2], 7   ; MEM[33] = 7
    MOV  WORD PTR [BX + 34*2], 2   ; MEM[34] = 2
    MOV  WORD PTR [BX + 35*2], 9   ; MEM[35] = 9
    MOV  WORD PTR [BX + 36*2], 5   ; MEM[36] = 5
    ; Nap chuong trinh vao Code Segment (dia chi ao 0..25)
    MOV  WORD PTR [BX +  0*2], 2020h   ; PC=0:  LOAD R0,[32]
    MOV  WORD PTR [BX +  1*2], 2421h   ; PC=1:  LOAD R1,[33]
    MOV  WORD PTR [BX +  2*2], 9004h   ; PC=2:  CMP  R0,R1
    MOV  WORD PTR [BX +  3*2], 0D006h  ; PC=3:  JN 6
    MOV  WORD PTR [BX +  4*2], 0A007h  ; PC=4:  JMP 7
    MOV  WORD PTR [BX +  5*2], 0A007h  ; PC=5:  JMP 7 (du phong)
    MOV  WORD PTR [BX +  6*2], 4001h   ; PC=6:  MOV R0,R1
    MOV  WORD PTR [BX +  7*2], 2422h   ; PC=7:  LOAD R1,[34]
    MOV  WORD PTR [BX +  8*2], 9004h   ; PC=8:  CMP  R0,R1
    MOV  WORD PTR [BX +  9*2], 0D00Ch  ; PC=9:  JN 12
    MOV  WORD PTR [BX + 10*2], 0A00Dh  ; PC=10: JMP 13
    MOV  WORD PTR [BX + 11*2], 0A00Dh  ; PC=11: JMP 13
    MOV  WORD PTR [BX + 12*2], 4001h   ; PC=12: MOV R0,R1
    MOV  WORD PTR [BX + 13*2], 2423h   ; PC=13: LOAD R1,[35]
    MOV  WORD PTR [BX + 14*2], 9004h   ; PC=14: CMP  R0,R1
    MOV  WORD PTR [BX + 15*2], 0D012h  ; PC=15: JN 18
    MOV  WORD PTR [BX + 16*2], 0A013h  ; PC=16: JMP 19
    MOV  WORD PTR [BX + 17*2], 0A013h  ; PC=17: JMP 19
    MOV  WORD PTR [BX + 18*2], 4001h   ; PC=18: MOV R0,R1
    MOV  WORD PTR [BX + 19*2], 2424h   ; PC=19: LOAD R1,[36]
    MOV  WORD PTR [BX + 20*2], 9004h   ; PC=20: CMP  R0,R1
    MOV  WORD PTR [BX + 21*2], 0D018h  ; PC=21: JN 24
    MOV  WORD PTR [BX + 22*2], 0A019h  ; PC=22: JMP 25
    MOV  WORD PTR [BX + 23*2], 0A019h  ; PC=23: JMP 25
    MOV  WORD PTR [BX + 24*2], 4001h   ; PC=24: MOV R0,R1
    MOV  WORD PTR [BX + 25*2], 0000h   ; PC=25: HALT
    CALL run_vcpu
    JMP  main_loop

; --- Demo 3: Dem nguoc tu 5 ve 0 ---
; Thuat toan: R0 = 5; lap: R0--; neu R0 != 0 thi lap lai
;
; Chuong trinh VCPU-16:
;   PC=0: LOADI R0, 5   -> 0x1005  R0 = 5
;   PC=1: DEC   R0      -> 0x8000  R0 = R0 - 1
;   PC=2: STORE [32],R0 -> 0x3020  MEM[32] = R0 (luu ket qua)
;   PC=3: CMP   R0, R0  -> (dung FLAGS tu DEC) - da duoc cap nhat boi DEC
;   PC=3: JNZ   1       -> 0xC001  Neu R0 != 0 thi quay lai PC=1
;   PC=4: HALT          -> 0x0000
;
; Luu y: Lenh DEC tu dong cap nhat FLAGS.Z, nen khong can CMP rieng
run_demo3:
    CALL reset_vcpu
    LEA  BX, vcpu_MEM
    MOV  WORD PTR [BX + 0*2], 1005h    ; PC=0: LOADI R0, 5
    MOV  WORD PTR [BX + 1*2], 8000h    ; PC=1: DEC R0
    MOV  WORD PTR [BX + 2*2], 3020h    ; PC=2: STORE [32], R0
    MOV  WORD PTR [BX + 3*2], 0C001h   ; PC=3: JNZ 1 (neu R0!=0 thi lap)
    MOV  WORD PTR [BX + 4*2], 0000h    ; PC=4: HALT
    CALL run_vcpu
    JMP  main_loop

; --- Demo 4: Tinh giai thua 5! = 120 ---
; Thuat toan: R0 = 1 (ket qua), R1 = 5 (bien dem)
;   Vong lap: R0 = R0 * R1 ... (vi VCPU-16 chua co MUL,
;   ta mo phong R0*R1 bang phep cong lap lai R1 lan:
;   R0 = R0+R0+...+R0 (R1 lan) - thuc chat: R2=R0, R0=0, lap R1 lan cong R2)
;   Sau do R1--; neu R1>0 thi lap
;
; Chuong trinh don gian hoa (nhan bang vong lap cong):
;   PC=0:  LOADI R0, 1    -> 0x1001  R0 = 1 (ket qua)
;   PC=1:  LOADI R1, 5    -> 0x1405  R1 = 5 (bien dem)
; [Nhan R0 voi R1 = cong R0 vao R3 tong cong R1 lan]
;   PC=2:  MOV   R2, R0   -> 0x4200  R2 = R0 (luu R0 cu truoc khi nhan)
;   PC=3:  MOV   R3, R1   -> 0x4C04  R3 = R1 (dem phu cho vong nhan)
;   PC=4:  LOADI R0, 0    -> 0x1000  R0 = 0 (bo tich luy)
;   PC=5:  ADD   R0, R2   -> 0x5002  R0 = R0 + R2 (cong R2 vao R0)
;   PC=6:  DEC   R3       -> 0x8C00  R3-- (giam bo dem nhan)
;   PC=7:  JNZ   5        -> 0xC005  Neu R3!=0: lap lai phep cong
; [Sau vong nhan: R0 = R2 * R1_cu]
;   PC=8:  DEC   R1       -> 0x8400  R1-- (giam bien dem giai thua)
;   PC=9:  JNZ   2        -> 0xC002  Neu R1!=0: lap lai vong nhan
;   PC=10: HALT           -> 0x0000  R0 = 5! = 120
run_demo4:
    CALL reset_vcpu
    LEA  BX, vcpu_MEM
    MOV  WORD PTR [BX + 0*2],  1001h   ; PC=0:  LOADI R0, 1
    MOV  WORD PTR [BX + 1*2],  1405h   ; PC=1:  LOADI R1, 5
    MOV  WORD PTR [BX + 2*2],  4200h   ; PC=2:  MOV R2, R0
    MOV  WORD PTR [BX + 3*2],  4C04h   ; PC=3:  MOV R3, R1
    MOV  WORD PTR [BX + 4*2],  1000h   ; PC=4:  LOADI R0, 0
    MOV  WORD PTR [BX + 5*2],  5002h   ; PC=5:  ADD R0, R2
    MOV  WORD PTR [BX + 6*2],  08C00h  ; PC=6:  DEC R3
    MOV  WORD PTR [BX + 7*2],  0C005h  ; PC=7:  JNZ 5
    MOV  WORD PTR [BX + 8*2],  8400h   ; PC=8:  DEC R1
    MOV  WORD PTR [BX + 9*2],  0C002h  ; PC=9:  JNZ 2
    MOV  WORD PTR [BX + 10*2], 0000h   ; PC=10: HALT
    CALL run_vcpu
    JMP  main_loop

exit_program:
    LEA  DX, msg_goodbye
    CALL print_str
    MOV  AH, 4Ch        ; INT 21h - Thoat chuong trinh DOS
    INT  21h

MAIN ENDP

; =============================================================================
; THU TUC: RESET_VCPU
; Muc dich: Dat lai toan bo trang thai CPU ao ve gia tri ban dau
; =============================================================================
reset_vcpu PROC
    ; Dat tat ca thanh ghi ve 0
    MOV  vcpu_R0,    0
    MOV  vcpu_R1,    0
    MOV  vcpu_R2,    0
    MOV  vcpu_R3,    0
    MOV  vcpu_PC,    0      ; PC bat dau tu dia chi 0
    MOV  vcpu_IR,    0
    MOV  vcpu_FLAGS, 0
    MOV  vcpu_SP,    15     ; SP tro vao cuoi vung Stack (dia chi 15 trong stack)
    MOV  vcpu_running, 1    ; CPU dang chay
    MOV  step_count,   0    ; Dat lai bo dem buoc

    ; Xoa toan bo 64 o bo nho ao ve 0
    LEA  BX, vcpu_MEM
    MOV  CX, 64         ; 64 o nho
    XOR  AX, AX         ; AX = 0
clear_mem_loop:
    MOV  WORD PTR [BX], 0   ; Ghi 0 vao o nho hien tai
    ADD  BX, 2              ; Tien den o nho tiep theo (moi o 2 bytes)
    LOOP clear_mem_loop

    RET
reset_vcpu ENDP

; =============================================================================
; THU TUC: RUN_VCPU
; Muc dich: Chay vong lap Fetch-Decode-Execute cua VCPU-16
;           Hien thi trang thai sau moi buoc
; =============================================================================
run_vcpu PROC
    ; Hien thi tieu de bang trang thai
    LEA  DX, msg_run_header
    CALL print_str

vcpu_main_loop:
    ; Kiem tra CPU co dang chay khong
    CMP  vcpu_running, 1
    JNE  vcpu_stopped

    ; =========================================================
    ; GIAI DOAN 1: FETCH - NAP LENH
    ; =========================================================
    ; Doc lenh tu vcpu_MEM[PC] vao IR
    ; Dia chi thuc trong mang x86 = base + PC*2 (vi moi word = 2 bytes)
    MOV  BX, vcpu_PC        ; BX = gia tri PC hien tai
    SHL  BX, 1              ; BX = PC * 2 (offset trong mang word)
    LEA  SI, vcpu_MEM       ; SI = dia chi base cua vcpu_MEM
    MOV  AX, [SI + BX]      ; AX = vcpu_MEM[PC] = lenh 16-bit
    MOV  vcpu_IR, AX        ; Luu vao IR (Instruction Register)

    ; Tang PC len 1 (tro sang lenh tiep theo)
    INC  vcpu_PC

    ; =========================================================
    ; GIAI DOAN 2: DECODE - GIAI MA LENH
    ; =========================================================
    ; Tach cac truong tu IR (16-bit):
    ;   Bits 15-12 = OPCODE (4 bit): dich phai 12 lan, AND 0Fh
    ;   Bits 11-10 = RD     (2 bit): dich phai 10 lan, AND 03h
    ;   Bits  9- 8 = RS     (2 bit): dich phai  8 lan, AND 03h
    ;   Bits  7- 0 = IMM8   (8 bit): AND 00FFh
    MOV  AX, vcpu_IR

    ; Tach OPCODE
    MOV  CX, AX
    SHR  CX, 12             ; CX = OPCODE (bits 15-12)
    AND  CX, 0Fh            ; Lay 4 bit thap

    ; Tach RD (thanh ghi dich)
    MOV  DX, AX
    SHR  DX, 10             ; DX = ... RD ...
    AND  DX, 03h            ; Lay 2 bit thap = so hieu RD (0,1,2,3)

    ; Tach RS (thanh ghi nguon)
    MOV  BX, AX
    SHR  BX, 8              ; BX = ... RS ...
    AND  BX, 03h            ; Lay 2 bit thap = so hieu RS (0,1,2,3)

    ; IMM8 = byte thap cua IR
    AND  AX, 00FFh          ; AX = IMM8 (dia chi hoac hang so 8-bit)

    ; Luu tam vao stack x86 de dung trong Execute
    PUSH AX                 ; [SP+0] = IMM8
    PUSH BX                 ; [SP+2] = RS
    PUSH DX                 ; [SP+4] = RD
    PUSH CX                 ; [SP+6] = OPCODE

    ; =========================================================
    ; GIAI DOAN 3: EXECUTE - THUC THI LENH
    ; =========================================================
    ; Dua vao OPCODE de nhay den thu tuc xu ly tuong ung
    POP  CX                 ; CX = OPCODE
    ; Lay lai RD, RS, IMM8 tu stack (van con do)

    ; Bang nhay theo OPCODE
    CMP  CX, 0
    JE   exec_halt
    CMP  CX, 1
    JE   exec_loadi
    CMP  CX, 2
    JE   exec_load
    CMP  CX, 3
    JE   exec_store
    CMP  CX, 4
    JE   exec_mov
    CMP  CX, 5
    JE   exec_add
    CMP  CX, 6
    JE   exec_sub
    CMP  CX, 7
    JE   exec_inc
    CMP  CX, 8
    JE   exec_dec
    CMP  CX, 9
    JE   exec_cmp
    CMP  CX, 0Ah
    JE   exec_jmp
    CMP  CX, 0Bh
    JE   exec_jz
    CMP  CX, 0Ch
    JE   exec_jnz
    CMP  CX, 0Dh
    JE   exec_jn
    CMP  CX, 0Eh
    JE   exec_push
    CMP  CX, 0Fh
    JE   exec_pop
    ; OPCODE khong hop le -> dung CPU
    JMP  exec_halt

; --- Xu ly lenh HALT (0x0): Dung CPU ---
exec_halt:
    ADD  SP, 6              ; Don stack: bo RD, RS, IMM8 da PUSH truoc do
    MOV  vcpu_running, 0    ; Dat co dung
    CALL display_state      ; Hien thi trang thai cuoi
    JMP  vcpu_stopped

; --- Xu ly lenh LOADI (0x1): Rd = IMM8 ---
exec_loadi:
    POP  DX                 ; DX = RD (so hieu thanh ghi dich)
    POP  BX                 ; BX = RS (khong dung)
    POP  AX                 ; AX = IMM8 (gia tri can nap)
    ; Tinh dia chi cua thanh ghi Rd trong bo nho x86
    ; reg_table[RD] chua offset cua thanh ghi do trong DS
    SHL  DX, 1              ; DX = RD * 2 (moi entry trong reg_table la 1 word)
    LEA  SI, reg_table
    ADD  SI, DX        ; SI = dia chi (offset) cua thanh ghi Rd trong DS
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  [SI], AX           ; vcpu_R[RD] = IMM8
    CALL update_flags_nonzero   ; Cap nhat FLAGS.Z dua tren gia tri vua nap
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh LOAD (0x2): Rd = MEM[IMM8] ---
exec_load:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS (khong dung)
    POP  AX                 ; AX = IMM8 = dia chi ao can doc
    ; Doc vcpu_MEM[IMM8]
    MOV  BX, AX
    SHL  BX, 1              ; BX = IMM8 * 2 (offset trong mang word)
    LEA  SI, vcpu_MEM
    MOV  AX, [SI + BX]      ; AX = vcpu_MEM[IMM8]
    ; Ghi vao thanh ghi Rd
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  [SI], AX           ; vcpu_R[RD] = vcpu_MEM[IMM8]
    CALL update_flags_nonzero
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh STORE (0x3): MEM[IMM8] = Rs ---
exec_store:
    POP  DX                 ; DX = RD (khong dung)
    POP  BX                 ; BX = RS (so hieu thanh ghi nguon)
    POP  AX                 ; AX = IMM8 = dia chi ao can ghi
    ; Doc gia tri tu thanh ghi Rs
    SHL  BX, 1
    LEA  SI, reg_table
    ADD  SI, BX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  CX, [SI]           ; CX = vcpu_R[RS]
    ; Ghi vao vcpu_MEM[IMM8]
    MOV  BX, AX
    SHL  BX, 1
    LEA  SI, vcpu_MEM
    MOV  [SI + BX], CX      ; vcpu_MEM[IMM8] = vcpu_R[RS]
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh MOV (0x4): Rd = Rs ---
exec_mov:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS
    POP  AX                 ; AX = IMM8 (khong dung)
    ; Doc gia tri Rs
    SHL  BX, 1
    LEA  SI, reg_table
    ADD  SI, BX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  CX, [SI]           ; CX = vcpu_R[RS]
    ; Ghi vao Rd
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  [SI], CX           ; vcpu_R[RD] = vcpu_R[RS]
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh ADD (0x5): Rd = Rd + Rs ---
exec_add:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS
    POP  AX                 ; AX = IMM8 (khong dung)
    ; Doc Rs
    SHL  BX, 1
    LEA  SI, reg_table
    ADD  SI, BX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  CX, [SI]           ; CX = vcpu_R[RS]
    ; Doc Rd va cong
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  AX, [SI]           ; AX = vcpu_R[RD]
    ADD  AX, CX             ; AX = Rd + Rs
    MOV  [SI], AX           ; Luu ket qua vao Rd
    CALL update_flags_result ; Cap nhat FLAGS dua tren AX
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh SUB (0x6): Rd = Rd - Rs ---
exec_sub:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS
    POP  AX                 ; AX = IMM8 (khong dung)
    ; Doc Rs
    SHL  BX, 1
    LEA  SI, reg_table
    ADD  SI, BX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  CX, [SI]           ; CX = vcpu_R[RS]
    ; Doc Rd va tru
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  AX, [SI]           ; AX = vcpu_R[RD]
    SUB  AX, CX             ; AX = Rd - Rs
    MOV  [SI], AX           ; Luu ket qua vao Rd
    CALL update_flags_result
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh INC (0x7): Rd = Rd + 1 ---
exec_inc:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS (khong dung)
    POP  AX                 ; AX = IMM8 (khong dung)
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  AX, [SI]
    INC  AX                 ; AX = Rd + 1
    MOV  [SI], AX
    CALL update_flags_result
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh DEC (0x8): Rd = Rd - 1 ---
exec_dec:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS (khong dung)
    POP  AX                 ; AX = IMM8 (khong dung)
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  AX, [SI]
    DEC  AX                 ; AX = Rd - 1
    MOV  [SI], AX
    CALL update_flags_result
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh CMP (0x9): Cap nhat FLAGS theo (Rd - Rs), khong luu ket qua ---
exec_cmp:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS
    POP  AX                 ; AX = IMM8 (khong dung)
    ; Doc Rs
    SHL  BX, 1
    LEA  SI, reg_table
    ADD  SI, BX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  CX, [SI]           ; CX = vcpu_R[RS]
    ; Doc Rd va tru (chi de cap nhat FLAGS)
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  AX, [SI]           ; AX = vcpu_R[RD]
    SUB  AX, CX             ; AX = Rd - Rs (chi dung cap nhat flags)
    CALL update_flags_result ; FLAGS phan anh ket qua so sanh
    ; Khong ghi ket qua vao bat ky thanh ghi nao
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh JMP (0xA): PC = IMM8 (nhay vo dieu kien) ---
exec_jmp:
    POP  DX                 ; DX = RD (khong dung)
    POP  BX                 ; BX = RS (khong dung)
    POP  AX                 ; AX = IMM8 = dia chi dich
    MOV  vcpu_PC, AX        ; PC = dia chi dich
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh JZ (0xB): Neu FLAGS.Z=1 thi PC = IMM8 ---
exec_jz:
    POP  DX                 ; RD (khong dung)
    POP  BX                 ; RS (khong dung)
    POP  AX                 ; AX = IMM8 = dia chi dich
    ; Kiem tra FLAGS bit 0 (Zero Flag)
    MOV  CX, vcpu_FLAGS
    AND  CX, 01h            ; Lay bit Z
    CMP  CX, 1
    JNE  jz_no_jump         ; Neu Z=0: khong nhay
    MOV  vcpu_PC, AX        ; Neu Z=1: PC = dia chi dich
jz_no_jump:
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh JNZ (0xC): Neu FLAGS.Z=0 thi PC = IMM8 ---
exec_jnz:
    POP  DX
    POP  BX
    POP  AX                 ; AX = IMM8
    MOV  CX, vcpu_FLAGS
    AND  CX, 01h            ; Lay bit Z
    CMP  CX, 0
    JNE  jnz_no_jump        ; Neu Z=1: khong nhay
    MOV  vcpu_PC, AX        ; Neu Z=0: PC = dia chi dich
jnz_no_jump:
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh JN (0xD): Neu FLAGS.N=1 (ket qua am) thi PC = IMM8 ---
exec_jn:
    POP  DX
    POP  BX
    POP  AX                 ; AX = IMM8
    MOV  CX, vcpu_FLAGS
    AND  CX, 02h            ; Lay bit N (bit 1)
    CMP  CX, 2              ; bit N = 1 thi CX = 2
    JNE  jn_no_jump         ; Neu N=0: khong nhay
    MOV  vcpu_PC, AX        ; Neu N=1: PC = dia chi dich
jn_no_jump:
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh PUSH (0xE): Stack[SP] = Rs; SP-- ---
exec_push:
    POP  DX                 ; DX = RD (khong dung)
    POP  BX                 ; BX = RS
    POP  AX                 ; AX = IMM8 (khong dung)
    ; Doc gia tri tu Rs
    SHL  BX, 1
    LEA  SI, reg_table
    ADD  SI, BX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  CX, [SI]           ; CX = vcpu_R[RS]
    ; Tinh dia chi trong Stack Segment (vung [48..63])
    ; Stack bat dau tu index 48 trong vcpu_MEM
    MOV  BX, vcpu_SP        ; BX = SP hien tai
    ADD  BX, 48             ; BX = 48 + SP (anh xa vao vung stack)
    SHL  BX, 1              ; Tinh offset word
    LEA  SI, vcpu_MEM
    MOV  [SI + BX], CX      ; Luu gia tri vao dinh stack
    DEC  vcpu_SP            ; SP-- (stack tang tu duoi len)
    CALL display_state
    JMP  vcpu_main_loop

; --- Xu ly lenh POP (0xF): SP++; Rd = Stack[SP] ---
exec_pop:
    POP  DX                 ; DX = RD
    POP  BX                 ; BX = RS (khong dung)
    POP  AX                 ; AX = IMM8 (khong dung)
    INC  vcpu_SP            ; SP++ truoc (stack tang tu tren xuong khi pop)
    ; Doc tu stack
    MOV  BX, vcpu_SP
    ADD  BX, 48             ; Anh xa vao vung stack cua vcpu_MEM
    SHL  BX, 1
    LEA  SI, vcpu_MEM
    MOV  CX, [SI + BX]      ; CX = Stack[SP]
    ; Ghi vao Rd
    SHL  DX, 1
    LEA  SI, reg_table
    ADD  SI, DX
    MOV  SI, [SI]        ; Doc offset thanh ghi tu reg_table
    MOV  [SI], CX           ; vcpu_R[RD] = Stack[SP]
    CALL display_state
    JMP  vcpu_main_loop

vcpu_stopped:
    ; Hien thi thong bao HALT va ket qua cuoi
    LEA  DX, msg_halt
    CALL print_str
    LEA  DX, msg_result
    CALL print_str
    MOV  AX, vcpu_R0
    CALL print_decimal
    LEA  DX, msg_newline
    CALL print_str
    LEA  DX, msg_demo_done
    CALL print_str
    ; Cho phim bam de ve menu
    MOV  AH, 01h
    INT  21h
    RET
run_vcpu ENDP

; =============================================================================
; THU TUC: UPDATE_FLAGS_RESULT
; Muc dich: Cap nhat vcpu_FLAGS dua tren gia tri trong AX
;   Z (bit 0) = 1 neu AX == 0
;   N (bit 1) = 1 neu AX la so am (bit 15 = 1)
; =============================================================================
update_flags_result PROC
    PUSH AX
    PUSH CX

    MOV  CX, 0              ; Bat dau voi FLAGS = 000

    ; Kiem tra Zero Flag: AX == 0?
    CMP  AX, 0
    JNE  check_negative
    OR   CX, 01h            ; Dat bit Z = 1

check_negative:
    ; Kiem tra Negative Flag: bit 15 cua AX = 1?
    TEST AX, 8000h          ; Kiem tra bit 15 (dau cua so 16-bit)
    JZ   save_flags
    OR   CX, 02h            ; Dat bit N = 1

save_flags:
    MOV  vcpu_FLAGS, CX
    POP  CX
    POP  AX
    RET
update_flags_result ENDP

; =============================================================================
; THU TUC: UPDATE_FLAGS_NONZERO
; Muc dich: Cap nhat FLAGS dua tren gia tri da ghi vao thanh ghi (AX)
;           Dung sau LOADI, LOAD, MOV
; =============================================================================
update_flags_nonzero PROC
    CALL update_flags_result    ; Dung chung logic voi update_flags_result
    RET
update_flags_nonzero ENDP

; =============================================================================
; THU TUC: DISPLAY_STATE
; Muc dich: Hien thi trang thai hien tai cua VCPU-16 ra man hinh
; Dinh dang: Buoc | PC | IR(hex) | R0  R1  R2  R3 | Z N
; =============================================================================
display_state PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    INC  step_count         ; Tang bo dem buoc
        ; So sanh xem da den buoc 10 chua
          ; Neu > 10 thi nhay toi cuoi (khong in)
    ; ------------------------------------
    ; Tang bo dem buoc


    ; In so thu tu buoc   
    
    LEA  DX, msg_step_prefix    ; In "B"
    CALL print_str
    MOV  AX, step_count
    CALL print_decimal          ; In so buoc
    LEA  DX, msg_pc_prefix      ; In " |"
    CALL print_str

    ; In PC
    MOV  AX, vcpu_PC
    DEC  AX                     ; Hien thi PC truoc khi tang (PC lenh vua thuc thi)
    CALL print_decimal
    LEA  DX, msg_pc_prefix
    CALL print_str

    ; In IR o dang hex (4 chu so)
    MOV  AX, vcpu_IR
    CALL print_hex4
    LEA  DX, msg_pc_prefix
    CALL print_str

    ; In R0
    MOV  AX, vcpu_R0
    CALL print_decimal_padded
    LEA  DX, msg_space5
    CALL print_str

    ; In R1
    MOV  AX, vcpu_R1
    CALL print_decimal_padded
    LEA  DX, msg_space5
    CALL print_str

    ; In R2
    MOV  AX, vcpu_R2
    CALL print_decimal_padded
    LEA  DX, msg_space5
    CALL print_str

    ; In R3
    MOV  AX, vcpu_R3
    CALL print_decimal_padded 
    LEA  DX, msg_pc_prefix
    CALL print_str

    ; In FLAGS: Z va N
    LEA  DX, msg_zflag          ; " Z="
    CALL print_str
    MOV  AX, vcpu_FLAGS
    AND  AX, 01h                ; Lay bit Z
    CALL print_decimal

    LEA  DX, msg_nflag          ; " N="
    CALL print_str
    MOV  AX, vcpu_FLAGS
    SHR  AX, 1
    AND  AX, 01h                ; Lay bit N
    CALL print_decimal

    ; Xuong dong
    LEA  DX, msg_newline
    CALL print_str
    
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
display_state ENDP

; =============================================================================
; THU TUC: PRINT_STR
; Muc dich: In chuoi ky tu ket thuc bang '$' (INT 21h, AH=09h)
; Tham so : DX = offset chuoi
; =============================================================================
print_str PROC
    MOV  AH, 09h
    INT  21h
    RET
print_str ENDP

; =============================================================================
; THU TUC: PRINT_DECIMAL
; Muc dich: In so nguyen khong dau trong AX ra man hinh (dang thap phan)
; Thuat toan: Chia lien tuc cho 10, lay du, in nguoc
; =============================================================================
print_decimal PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    ; Xu ly truong hop so am (bo sung 2)
    TEST AX, 8000h
    JZ   pd_positive
    ; In dau tru
    PUSH AX
    MOV  DL, '-'
    MOV  AH, 02h
    INT  21h
    POP  AX
    NEG  AX             ; Doi sang duong de in chu so

pd_positive:
    ; Truong hop dac biet: AX = 0
    CMP  AX, 0
    JNE  pd_not_zero
    MOV  DL, '0'
    MOV  AH, 02h
    INT  21h
    JMP  pd_done

pd_not_zero:
    ; Dung stack de dao nguoc thu tu chu so
    MOV  CX, 0          ; Dem so chu so da day vao stack
    MOV  BX, 10         ; Chia cho 10

pd_divide_loop:
    CMP  AX, 0
    JE   pd_print_loop  ; Khong con chu so de tach
    XOR  DX, DX         ; DX:AX = AX (chia khong dau)
    DIV  BX             ; AX = thuong, DX = du (chu so hien tai)
    ADD  DL, '0'        ; Chuyen thanh ky tu ASCII
    PUSH DX             ; Day ky tu vao stack
    INC  CX             ; Tang dem chu so
    JMP  pd_divide_loop

pd_print_loop:
    CMP  CX, 0
    JE   pd_done
    POP  DX             ; Lay ky tu tu stack (thu tu dao nguoc = dung)
    MOV  AH, 02h
    INT  21h            ; In ky tu
    DEC  CX
    JMP  pd_print_loop

pd_done:
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
print_decimal ENDP

; =============================================================================
; THU TUC: PRINT_DECIMAL_PADDED
; Muc dich: In so thap phan co can le (toi da 5 ky tu)
;           Dung de can cot trong bang hien thi
; =============================================================================
print_decimal_padded PROC
    PUSH AX
    ; Don gian: goi print_decimal roi in khoang trang phu
    CALL print_decimal
    POP  AX
    RET
print_decimal_padded ENDP

; =============================================================================
; THU TUC: PRINT_HEX4
; Muc dich: In gia tri AX duoi dang 4 chu so hex (0000-FFFF)
; =============================================================================
print_hex4 PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV  CX, 4              ; In 4 nibble (4 chu so hex)
    MOV  BX, AX             ; BX = gia tri can in

ph4_loop:
    ; Lay nibble cao nhat
    MOV  AX, BX
    SHR  AX, 12             ; Dich phai 12 bit de lay nibble dau
    AND  AX, 0Fh            ; Lay 4 bit thap

    ; Chuyen sang ky tu hex
    CMP  AL, 10
    JL   ph4_digit          ; 0-9: cong them '0'
    ADD  AL, 'A' - 10       ; A-F: cong them 'A'-10
    JMP  ph4_print
ph4_digit:
    ADD  AL, '0'
ph4_print:
    MOV  DL, AL
    MOV  AH, 02h
    INT  21h                ; In ky tu hex

    SHL  BX, 4              ; Dich trai 4 bit de lay nibble tiep theo
    DEC  CX
    JNZ  ph4_loop

    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET
print_hex4 ENDP

END MAIN

