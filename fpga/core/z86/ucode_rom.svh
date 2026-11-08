// Auto-generated – do not edit
localparam [5:0] MC_NOP = 0;
localparam [5:0] MC_PUSH = 1;
localparam [5:0] MC_POP = 2;
localparam [5:0] MC_ADJSP = 3;
localparam [5:0] MC_GETVEC_OFF = 4;
localparam [5:0] MC_GETVEC_SEG = 5;
localparam [5:0] MC_LOAD = 6;
localparam [5:0] MC_STORE = 7;
localparam [5:0] MC_BR_REL16 = 8;
localparam [5:0] MC_BR_ABS16 = 9;
localparam [5:0] MC_BR_FAR = 10;
localparam [5:0] MC_TESTF = 11;
localparam [5:0] MC_TESTZX = 12;
localparam [5:0] MC_J = 13;
localparam [5:0] MC_JT = 14;
localparam [5:0] MC_JF = 15;
localparam [5:0] MC_READ = 16;
localparam [5:0] MC_WR_FLAGS = 17;
localparam [5:0] MC_WR_REG = 18;
localparam [5:0] MC_WR_SEG = 19;
localparam [5:0] MC_STR_CMP = 20;
localparam [5:0] MC_DEC = 21;
localparam [5:0] MC_MULU = 22;
localparam [5:0] MC_MULS = 23;
localparam [5:0] MC_DIV = 24;
localparam [5:0] MC_ADJ = 25;
localparam [5:0] MC_AAD = 26;
localparam [5:0] MC_IN_RANGE = 27;
localparam [5:0] MC_IN = 28;
localparam [5:0] MC_OUT = 29;
localparam [5:0] MC_HALT = 30;
localparam [5:0] MC_DESC = 31;
localparam [5:0] MC_LDDT = 32;
localparam [5:0] MC_STDT = 33;
localparam [5:0] MC_SMSW = 34;
localparam [5:0] MC_LMSW = 35;
const uinstr_t microcode_rom [512] = '{
    // 00 NOP
    `U( 0,4'h0,1), // 8: .end
    // 01 CALL_NEAR
    `U( 1,4'h2,0), // 11: PUSH  IP_AFTER
    `U( 8,4'h0,0), // 12: BR_REL16
    `U( 0,4'h0,1), // 13: .end
    // 04 CALL_RM
    `U( 1,4'h2,0), // 16: PUSH  IP_AFTER
    `U( 6,4'h0,0), // 17: LOAD      0
    `U( 9,4'h0,0), // 18: BR_ABS16
    `U( 0,4'h0,1), // 19: .end
    // 08 CALL_FAR
    `U( 1,4'h0,0), // 22: PUSH  CS
    `U( 1,4'h2,0), // 23: PUSH  IP_AFTER
    `U(10,4'h1,0), // 24: BR_FAR     1
    `U( 0,4'h0,1), // 25: .end
    // 0C CALL_EP
    `U( 1,4'h0,0), // 28: PUSH  CS
    `U( 1,4'h2,0), // 29: PUSH  IP_AFTER
    `U( 6,4'h0,0), // 30: LOAD       0
    `U( 6,4'h1,0), // 31: LOAD       1
    `U(10,4'h0,0), // 32: BR_FAR     0
    `U( 0,4'h0,1), // 33: .end
    // 12 JMP_RM
    `U( 6,4'h0,0), // 36: LOAD       0
    `U( 9,4'h0,0), // 37: BR_ABS16
    `U( 0,4'h0,1), // 38: .end
    // 15 JMP_EP
    `U( 6,4'h0,0), // 41: LOAD       0
    `U( 6,4'h1,0), // 42: LOAD       1
    `U(10,4'h0,0), // 43: BR_FAR     0
    `U( 0,4'h0,1), // 44: .end
    // 19 RET_NEAR
    `U( 2,4'h0,0), // 47: POP   0
    `U( 9,4'h0,0), // 48: BR_ABS16
    `U( 0,4'h0,1), // 49: .end
    // 1C RET_NEAR_IMM
    `U( 2,4'h0,0), // 52: POP   0
    `U( 3,4'h0,0), // 53: ADJSP 0
    `U( 9,4'h0,0), // 54: BR_ABS16
    `U( 0,4'h0,1), // 55: .end
    // 20 RET_FAR
    `U( 2,4'h0,0), // 58: POP   0
    `U( 2,4'h1,0), // 59: POP   1
    `U(10,4'h0,0), // 60: BR_FAR     0
    `U( 0,4'h0,1), // 61: .end
    // 24 RET_FAR_IMM
    `U( 2,4'h0,0), // 64: POP   0
    `U( 2,4'h1,0), // 65: POP   1
    `U( 3,4'h0,0), // 66: ADJSP 0
    `U(10,4'h0,0), // 67: BR_FAR     0
    `U( 0,4'h0,1), // 68: .end
    // 29 IRET
    `U( 2,4'h0,0), // 71: POP     0
    `U( 2,4'h1,0), // 72: POP     1
    `U( 2,4'h2,0), // 73: POP     2
    `U(17,4'h0,0), // 74: WR_FLAGS
    `U(10,4'h0,0), // 75: BR_FAR  0
    `U( 0,4'h0,1), // 76: .end
    // 2F INT3
    `U( 1,4'h4,0), // 82: PUSH  FLAGS
    `U( 4,4'h3,0), // 83: GETVEC_OFF      3
    `U( 5,4'h3,0), // 84: GETVEC_SEG      3
    `U( 1,4'h0,0), // 85: PUSH  CS
    `U( 1,4'h2,0), // 86: PUSH  IP_AFTER
    `U(10,4'h0,0), // 87: BR_FAR     0
    `U( 0,4'h0,1), // 88: .end
    // 36 INT_IMM
    `U( 1,4'h4,0), // 91: PUSH  FLAGS
    `U( 4,4'hf,0), // 92: GETVEC_OFF      15
    `U( 5,4'hf,0), // 93: GETVEC_SEG      15
    `U( 1,4'h0,0), // 94: PUSH  CS
    `U( 1,4'h2,0), // 95: PUSH  IP_AFTER
    `U(10,4'h0,0), // 96: BR_FAR     0
    `U( 0,4'h0,1), // 97: .end
    // 3D INTO
    `U(11,4'h5,0), // 100: TESTF   OF
    `U(15,4'h6,0), // 101: JF     6
    `U( 1,4'h4,0), // 102: PUSH  FLAGS
    `U( 4,4'h4,0), // 103: GETVEC_OFF      4
    `U( 5,4'h4,0), // 104: GETVEC_SEG      4
    `U( 1,4'h0,0), // 105: PUSH  CS
    `U( 1,4'h2,0), // 106: PUSH  IP_AFTER
    `U(10,4'h0,0), // 107: BR_FAR     0
    `U( 0,4'h0,1), // 108: .end
    // 46 INT1
    `U( 1,4'h4,0), // 111: PUSH  FLAGS
    `U( 4,4'h1,0), // 112: GETVEC_OFF      1
    `U( 5,4'h1,0), // 113: GETVEC_SEG      1
    `U( 1,4'h0,0), // 114: PUSH  CS
    `U( 1,4'h2,0), // 115: PUSH  IP_AFTER
    `U(10,4'h0,0), // 116: BR_FAR     0
    `U( 0,4'h0,1), // 117: .end
    // 4D MOVSB
    `U( 6,4'h6,0), // 132: LOAD      0b0110
    `U( 7,4'h6,0), // 133: STORE     0b0110
    `U( 0,4'h0,1), // 134: .end
    // 50 REP_MOVSB
    `U(12,4'h2,0), // 137: TESTZX    REP
    `U(14,4'h4,0), // 138: JT        4
    `U( 6,4'h6,0), // 139: LOAD      0b0110
    `U( 7,4'h6,0), // 140: STORE     0b0110
    `U(21,4'h1,0), // 141: DEC       CX
    `U(13,4'ha,0), // 142: J         -6
    `U( 0,4'h0,1), // 143: .end
    // 57 MOVSW
    `U( 6,4'he,0), // 148: LOAD      0b1110
    `U( 7,4'he,0), // 149: STORE     0b1110
    `U( 0,4'h0,1), // 150: .end
    // 5A REP_MOVSW
    `U(12,4'h2,0), // 153: TESTZX    REP
    `U(14,4'h4,0), // 154: JT        4
    `U( 6,4'he,0), // 155: LOAD      0b1110
    `U( 7,4'he,0), // 156: STORE     0b1110
    `U(21,4'h1,0), // 157: DEC       CX
    `U(13,4'ha,0), // 158: J         -6
    `U( 0,4'h0,1), // 159: .end
    // 61 CMPSB
    `U( 6,4'h6,0), // 164: LOAD      0b0110
    `U( 6,4'h7,0), // 165: LOAD      0b0111
    `U(20,4'h0,0), // 166: STR_CMP   0
    `U( 0,4'h0,1), // 167: .end
    // 65 REPNE_CMPSB
    `U(12,4'h2,0), // 170: TESTZX    REP
    `U(14,4'h6,0), // 171: JT        6
    `U( 6,4'h6,0), // 172: LOAD      0b0110
    `U( 6,4'h7,0), // 173: LOAD      0b0111
    `U(21,4'h1,0), // 174: DEC       CX
    `U(20,4'h0,0), // 175: STR_CMP   0
    `U(11,4'h3,0), // 176: TESTF     ZF
    `U(15,4'h8,0), // 177: JF        -8
    `U( 0,4'h0,1), // 178: .end
    // 6E REPE_CMPSB
    `U(12,4'h2,0), // 181: TESTZX    REP
    `U(14,4'h6,0), // 182: JT        6
    `U( 6,4'h6,0), // 183: LOAD      0b0110
    `U( 6,4'h7,0), // 184: LOAD      0b0111
    `U(21,4'h1,0), // 185: DEC       CX
    `U(20,4'h0,0), // 186: STR_CMP   0
    `U(11,4'h3,0), // 187: TESTF     ZF
    `U(14,4'h8,0), // 188: JT        -8
    `U( 0,4'h0,1), // 189: .end
    // 77 CMPSW
    `U( 6,4'he,0), // 194: LOAD      0b1110
    `U( 6,4'hf,0), // 195: LOAD      0b1111
    `U(20,4'h1,0), // 196: STR_CMP   1
    `U( 0,4'h0,1), // 197: .end
    // 7B REPNE_CMPSW
    `U(12,4'h2,0), // 200: TESTZX    REP
    `U(14,4'h6,0), // 201: JT        6
    `U( 6,4'he,0), // 202: LOAD      0b1110
    `U( 6,4'hf,0), // 203: LOAD      0b1111
    `U(21,4'h1,0), // 204: DEC       CX
    `U(20,4'h1,0), // 205: STR_CMP   1
    `U(11,4'h3,0), // 206: TESTF     ZF
    `U(15,4'h8,0), // 207: JF        -8
    `U( 0,4'h0,1), // 208: .end
    // 84 REPE_CMPSW
    `U(12,4'h2,0), // 211: TESTZX    REP
    `U(14,4'h6,0), // 212: JT        6
    `U( 6,4'he,0), // 213: LOAD      0b1110
    `U( 6,4'hf,0), // 214: LOAD      0b1111
    `U(21,4'h1,0), // 215: DEC       CX
    `U(20,4'h1,0), // 216: STR_CMP   1
    `U(11,4'h3,0), // 217: TESTF     ZF
    `U(14,4'h8,0), // 218: JT        -8
    `U( 0,4'h0,1), // 219: .end
    // 8D REP_CMPSW
    `U(12,4'h2,0), // 222: TESTZX    REP
    `U(14,4'h5,0), // 223: JT        5
    `U( 6,4'he,0), // 224: LOAD      0b1110
    `U( 6,4'hf,0), // 225: LOAD      0b1111
    `U(21,4'h1,0), // 226: DEC       CX
    `U(20,4'h1,0), // 227: STR_CMP   1
    `U(13,4'h9,0), // 228: J         -7
    `U( 0,4'h0,1), // 229: .end
    // 95 STOSB
    `U( 7,4'h7,0), // 234: STORE     0b0111
    `U( 0,4'h0,1), // 235: .end
    // 97 REP_STOSB
    `U(12,4'h2,0), // 238: TESTZX    REP
    `U(14,4'h3,0), // 239: JT        3
    `U(21,4'h1,0), // 240: DEC       CX
    `U( 7,4'h7,0), // 241: STORE     0b0111
    `U(13,4'hb,0), // 242: J         -5
    `U( 0,4'h0,1), // 243: .end
    // 9D STOSW
    `U( 7,4'hf,0), // 248: STORE     0b1111
    `U( 0,4'h0,1), // 249: .end
    // 9F REP_STOSW
    `U(12,4'h2,0), // 252: TESTZX    REP
    `U(14,4'h3,0), // 253: JT        3
    `U(21,4'h1,0), // 254: DEC       CX
    `U( 7,4'hf,0), // 255: STORE     0b1111
    `U(13,4'hb,0), // 256: J         -5
    `U( 0,4'h0,1), // 257: .end
    // A5 LODSB
    `U( 6,4'h6,0), // 262: LOAD      0b0110
    `U(18,4'h8,0), // 263: WR_REG    AL
    `U( 0,4'h0,1), // 264: .end
    // A8 REP_LODSB
    `U(12,4'h2,0), // 267: TESTZX    REP
    `U(14,4'h4,0), // 268: JT        4
    `U( 6,4'h6,0), // 269: LOAD      0b0110
    `U(21,4'h1,0), // 270: DEC       CX
    `U(18,4'h8,0), // 271: WR_REG    AL
    `U(13,4'ha,0), // 272: J         -6
    `U( 0,4'h0,1), // 273: .end
    // AF LODSW
    `U( 6,4'he,0), // 278: LOAD      0b1110
    `U(18,4'h0,0), // 279: WR_REG    AX
    `U( 0,4'h0,1), // 280: .end
    // B2 REP_LODSW
    `U(12,4'h2,0), // 283: TESTZX    REP
    `U(14,4'h4,0), // 284: JT        4
    `U( 6,4'he,0), // 285: LOAD      0b1110
    `U(21,4'h1,0), // 286: DEC       CX
    `U(18,4'h0,0), // 287: WR_REG    AX
    `U(13,4'ha,0), // 288: J         -6
    `U( 0,4'h0,1), // 289: .end
    // B9 SCASB
    `U( 6,4'h7,0), // 294: LOAD      0b0111
    `U(20,4'h0,0), // 295: STR_CMP   0
    `U( 0,4'h0,1), // 296: .end
    // BC REPNE_SCASB
    `U(12,4'h2,0), // 299: TESTZX    REP
    `U(14,4'h5,0), // 300: JT        5
    `U( 6,4'h7,0), // 301: LOAD      0b0111
    `U(21,4'h1,0), // 302: DEC       CX
    `U(20,4'h0,0), // 303: STR_CMP   0
    `U(11,4'h3,0), // 304: TESTF     ZF
    `U(15,4'h9,0), // 305: JF        -7
    `U( 0,4'h0,1), // 306: .end
    // C4 REPE_SCASB
    `U(12,4'h2,0), // 309: TESTZX    REP
    `U(14,4'h5,0), // 310: JT        5
    `U( 6,4'h7,0), // 311: LOAD      0b0111
    `U(21,4'h1,0), // 312: DEC       CX
    `U(20,4'h0,0), // 313: STR_CMP   0
    `U(11,4'h3,0), // 314: TESTF     ZF
    `U(14,4'h9,0), // 315: JT        -7
    `U( 0,4'h0,1), // 316: .end
    // CC SCASW
    `U( 6,4'hf,0), // 321: LOAD      0b1111
    `U(20,4'h1,0), // 322: STR_CMP   1
    `U( 0,4'h0,1), // 323: .end
    // CF REPNE_SCASW
    `U(12,4'h2,0), // 326: TESTZX    REP
    `U(14,4'h5,0), // 327: JT        5
    `U( 6,4'hf,0), // 328: LOAD      0b1111
    `U(21,4'h1,0), // 329: DEC       CX
    `U(20,4'h1,0), // 330: STR_CMP   1
    `U(11,4'h3,0), // 331: TESTF     ZF
    `U(15,4'h9,0), // 332: JF        -7
    `U( 0,4'h0,1), // 333: .end
    // D7 REPE_SCASW
    `U(12,4'h2,0), // 336: TESTZX    REP
    `U(14,4'h5,0), // 337: JT        5
    `U( 6,4'hf,0), // 338: LOAD      0b1111
    `U(21,4'h1,0), // 339: DEC       CX
    `U(20,4'h1,0), // 340: STR_CMP   1
    `U(11,4'h3,0), // 341: TESTF     ZF
    `U(14,4'h9,0), // 342: JT        -7
    `U( 0,4'h0,1), // 343: .end
    // DF LES
    `U( 6,4'h0,0), // 348: LOAD      0
    `U( 6,4'h1,0), // 349: LOAD      1
    `U(18,4'ha,0), // 350: WR_REG    REG
    `U(19,4'h0,0), // 351: WR_SEG    0
    `U( 0,4'h0,1), // 352: .end
    // E4 LDS
    `U( 6,4'h0,0), // 355: LOAD      0
    `U( 6,4'h1,0), // 356: LOAD      1
    `U(18,4'ha,0), // 357: WR_REG    REG
    `U(19,4'h3,0), // 358: WR_SEG    3
    `U( 0,4'h0,1), // 359: .end
    // E9 PUSHF
    `U( 1,4'h4,0), // 364: PUSH      FLAGS
    `U( 0,4'h0,1), // 365: .end
    // EB POPF
    `U( 2,4'h2,0), // 368: POP       TMP_FLAGS
    `U(17,4'h0,0), // 369: WR_FLAGS
    `U( 0,4'h0,1), // 370: .end
    // EE PUSH_R16
    `U( 1,4'h3,0), // 373: PUSH      RM
    `U( 0,4'h0,1), // 374: .end
    // F0 PUSH_M16
    `U( 6,4'h0,0), // 377: LOAD      0
    `U( 1,4'h5,0), // 378: PUSH      TMP_LO
    `U( 0,4'h0,1), // 379: .end
    // F3 MUL8
    `U( 6,4'h0,0), // 384: LOAD      0
    `U(22,4'h0,0), // 385: MULU      0
    `U( 0,4'h0,1), // 386: .end
    // F6 MUL16
    `U( 6,4'h8,0), // 389: LOAD      8
    `U(22,4'h1,0), // 390: MULU      1
    `U( 0,4'h0,1), // 391: .end
    // F9 IMUL8
    `U( 6,4'h0,0), // 394: LOAD      0
    `U(23,4'h0,0), // 395: MULS      0
    `U( 0,4'h0,1), // 396: .end
    // FC IMUL16
    `U( 6,4'h0,0), // 399: LOAD      0
    `U(23,4'h1,0), // 400: MULS      1
    `U( 0,4'h0,1), // 401: .end
    // FF DIV8
    `U( 6,4'h0,0), // 408: LOAD      0
    `U(24,4'h0,0), // 409: DIV       0b00
    `U(14,4'h1,0), // 410: JT       1
    `U( 0,4'h0,1), // 411: .end
    `U( 1,4'h4,0), // 413: PUSH  FLAGS
    `U( 4,4'h0,0), // 415: GETVEC_OFF      0
    `U( 5,4'h0,0), // 416: GETVEC_SEG      0
    `U( 1,4'h0,0), // 417: PUSH  CS
    `U( 1,4'h1,0), // 418: PUSH  IP_THIS
    `U(10,4'h0,0), // 420: BR_FAR     0
    `U( 0,4'h0,1), // 421: .end
    // 10A DIV16
    `U( 6,4'h0,0), // 424: LOAD      0
    `U(24,4'h1,0), // 425: DIV       0b01
    `U(14,4'h1,0), // 426: JT       1
    `U( 0,4'h0,1), // 427: .end
    `U( 1,4'h4,0), // 429: PUSH  FLAGS
    `U( 4,4'h0,0), // 431: GETVEC_OFF      0
    `U( 5,4'h0,0), // 432: GETVEC_SEG      0
    `U( 1,4'h0,0), // 433: PUSH  CS
    `U( 1,4'h1,0), // 434: PUSH  IP_THIS
    `U(10,4'h0,0), // 435: BR_FAR     0
    `U( 0,4'h0,1), // 436: .end
    // 115 IDIV8
    `U( 6,4'h0,0), // 439: LOAD      0
    `U(24,4'h2,0), // 440: DIV       0b10
    `U(14,4'h1,0), // 441: JT       1
    `U( 0,4'h0,1), // 442: .end
    `U( 1,4'h4,0), // 444: PUSH  FLAGS
    `U( 4,4'h0,0), // 446: GETVEC_OFF      0
    `U( 5,4'h0,0), // 447: GETVEC_SEG      0
    `U( 1,4'h0,0), // 448: PUSH  CS
    `U( 1,4'h1,0), // 449: PUSH  IP_THIS
    `U(10,4'h0,0), // 450: BR_FAR     0
    `U( 0,4'h0,1), // 451: .end
    // 120 IDIV16
    `U( 6,4'h0,0), // 454: LOAD      0
    `U(24,4'h3,0), // 455: DIV       0b11
    `U(14,4'h1,0), // 456: JT       1
    `U( 0,4'h0,1), // 457: .end
    `U( 1,4'h4,0), // 459: PUSH  FLAGS
    `U( 4,4'h0,0), // 461: GETVEC_OFF      0
    `U( 5,4'h0,0), // 462: GETVEC_SEG      0
    `U( 1,4'h0,0), // 463: PUSH  CS
    `U( 1,4'h1,0), // 464: PUSH  IP_THIS
    `U(10,4'h0,0), // 465: BR_FAR     0
    `U( 0,4'h0,1), // 466: .end
    // 12B DAA
    `U(25,4'h0,0), // 474: ADJ   0
    `U( 0,4'h0,1), // 475: .end
    // 12D DAS
    `U(25,4'h1,0), // 478: ADJ   1
    `U( 0,4'h0,1), // 479: .end
    // 12F AAA
    `U(25,4'h2,0), // 482: ADJ   2
    `U( 0,4'h0,1), // 483: .end
    // 131 AAS
    `U(25,4'h3,0), // 486: ADJ   3
    `U( 0,4'h0,1), // 487: .end
    // 133 AAM
    `U(25,4'h4,0), // 490: ADJ       4
    `U(14,4'h1,0), // 491: JT       1
    `U( 0,4'h0,1), // 492: .end
    `U( 1,4'h4,0), // 493: PUSH  FLAGS
    `U( 4,4'h0,0), // 495: GETVEC_OFF      0
    `U( 5,4'h0,0), // 496: GETVEC_SEG      0
    `U( 1,4'h0,0), // 497: PUSH  CS
    `U( 1,4'h1,0), // 498: PUSH  IP_THIS
    `U(10,4'h0,0), // 499: BR_FAR     0
    `U( 0,4'h0,1), // 500: .end
    // 13D AAD
    `U(26,4'h0,0), // 504: AAD
    `U( 0,4'h0,1), // 505: .end
    // 13F HLT
    `U(30,4'h0,0), // 509: HALT
    `U( 0,4'h0,1), // 510: .end
    // 141 PUSHA
    `U(16,4'h4,0), // 518: READ     SP
    `U( 1,4'h8,0), // 519: PUSH     AX
    `U( 1,4'h9,0), // 520: PUSH     CX
    `U( 1,4'ha,0), // 521: PUSH     DX
    `U( 1,4'hb,0), // 522: PUSH     BX
    `U( 1,4'h5,0), // 523: PUSH     TMP_LO
    `U( 1,4'hd,0), // 524: PUSH     BP
    `U( 1,4'he,0), // 525: PUSH     SI
    `U( 1,4'hf,0), // 526: PUSH     DI
    `U( 0,4'h0,1), // 527: .end
    // 14B POPA
    `U( 2,4'hf,0), // 530: POP      DI
    `U( 2,4'he,0), // 531: POP      SI
    `U( 2,4'hd,0), // 532: POP      BP
    `U( 2,4'h0,0), // 533: POP      TMP_LO
    `U( 2,4'hb,0), // 534: POP      BX
    `U( 2,4'ha,0), // 535: POP      DX
    `U( 2,4'h9,0), // 536: POP      CX
    `U( 2,4'h8,0), // 537: POP      AX
    `U( 0,4'h0,1), // 538: .end
    // 154 BOUND
    `U( 6,4'h0,0), // 544: LOAD   0
    `U( 6,4'h1,0), // 545: LOAD   1
    `U(27,4'h0,0), // 546: IN_RANGE
    `U(14,4'h6,0), // 547: JT     6
    `U( 1,4'h4,0), // 552: PUSH     FLAGS
    `U( 4,4'h5,0), // 553: GETVEC_OFF 5
    `U( 5,4'h5,0), // 554: GETVEC_SEG 5
    `U( 1,4'h0,0), // 555: PUSH     CS
    `U( 1,4'h1,0), // 556: PUSH     IP_THIS
    `U(10,4'h0,0), // 557: BR_FAR   0
    `U( 0,4'h0,1), // 558: .end
    // 15F ARPL
    `U( 0,4'h0,1), // 569: .end
    // 160 IMUL_IW
    `U( 6,4'h0,0), // 574: LOAD     0
    `U(23,4'h3,0), // 575: MULS     3
    `U( 0,4'h0,1), // 576: .end
    // 163 IMUL_IB
    `U( 6,4'h0,0), // 579: LOAD     0
    `U(23,4'h2,0), // 580: MULS     2
    `U( 0,4'h0,1), // 581: .end
    // 166 INSB
    `U(28,4'h0,0), // 586: IN      BYTE
    `U( 7,4'h6,0), // 587: STORE   0b0110
    `U( 0,4'h0,1), // 588: .end
    // 169 INSW
    `U(28,4'h1,0), // 591: IN      WORD
    `U( 7,4'he,0), // 592: STORE   0b1110
    `U( 0,4'h0,1), // 593: .end
    // 16C OUTSB
    `U( 6,4'h6,0), // 596: LOAD    0b0110
    `U(29,4'h0,0), // 597: OUT     BYTE
    `U( 0,4'h0,1), // 598: .end
    // 16F OUTSW
    `U( 6,4'he,0), // 601: LOAD    0b1110
    `U(29,4'h1,0), // 602: OUT     WORD
    `U( 0,4'h0,1), // 603: .end
    // 172 REP_INSB
    `U(12,4'h2,0), // 608: TESTZX    REP
    `U(14,4'h4,0), // 609: JT        4
    `U(28,4'h0,0), // 610: IN        BYTE
    `U( 7,4'h6,0), // 611: STORE     0b0110
    `U(21,4'h1,0), // 612: DEC       CX
    `U(13,4'ha,0), // 613: J         -6
    `U( 0,4'h0,1), // 614: .end
    // 179 REP_INSW
    `U(12,4'h2,0), // 617: TESTZX    REP
    `U(14,4'h4,0), // 618: JT        4
    `U(28,4'h1,0), // 619: IN        WORD
    `U( 7,4'he,0), // 620: STORE     0b1110
    `U(21,4'h1,0), // 621: DEC       CX
    `U(13,4'ha,0), // 622: J         -6
    `U( 0,4'h0,1), // 623: .end
    // 180 REP_OUTSB
    `U(12,4'h2,0), // 626: TESTZX    REP
    `U(14,4'h4,0), // 627: JT        4
    `U( 6,4'h6,0), // 628: LOAD      0b0110
    `U(29,4'h0,0), // 629: OUT       BYTE
    `U(21,4'h1,0), // 630: DEC       CX
    `U(13,4'ha,0), // 631: J         -6
    `U( 0,4'h0,1), // 632: .end
    // 187 REP_OUTSW
    `U(12,4'h2,0), // 635: TESTZX    REP
    `U(14,4'h4,0), // 636: JT        4
    `U( 6,4'he,0), // 637: LOAD      0b1110
    `U(29,4'h1,0), // 638: OUT       WORD
    `U(21,4'h1,0), // 639: DEC       CX
    `U(13,4'ha,0), // 640: J         -6
    `U( 0,4'h0,1), // 641: .end
    // 18E ENTER
    `U( 1,4'hd,0), // 663: PUSH     BP
    `U(16,4'h8,0), // 664: READ     ENTER_IB
    `U(16,4'h4,0), // 665: READ     SP
    `U(18,4'h5,0), // 666: WR_REG   BP
    `U(12,4'h1,0), // 670: TESTZX   TMP_HI
    `U(14,4'h3,0), // 671: JT       3
    `U( 1,4'hd,0), // 672: PUSH     BP
    `U(21,4'h8,0), // 673: DEC      TMP_HI
    `U(13,4'hb,0), // 674: J        -5
    `U( 3,4'h1,0), // 676: ADJSP    SUB_IW
    `U( 0,4'h0,1), // 677: .end
    // 199 LEAVE
    `U(16,4'h5,0), // 680: READ     BP
    `U(18,4'h4,0), // 681: WR_REG   SP
    `U( 2,4'hd,0), // 682: POP      BP
    `U( 0,4'h0,1), // 683: .end
    // 19D SGDT
    `U(33,4'h0,0), // 693: STDT     0
    `U(33,4'h1,0), // 694: STDT     1
    `U(33,4'h2,0), // 695: STDT     2
    `U( 0,4'h0,1), // 696: .end
    // 1A1 SIDT
    `U(33,4'h4,0), // 699: STDT     4
    `U(33,4'h5,0), // 700: STDT     5
    `U(33,4'h6,0), // 701: STDT     6
    `U( 0,4'h0,1), // 702: .end
    // 1A5 LGDT
    `U( 6,4'h0,0), // 705: LOAD     0
    `U( 6,4'h1,0), // 706: LOAD     1
    `U(32,4'h0,0), // 707: LDDT     GDTR
    `U( 0,4'h0,1), // 708: .end
    // 1A9 LIDT
    `U( 6,4'h0,0), // 711: LOAD     0
    `U( 6,4'h1,0), // 712: LOAD     1
    `U(32,4'h1,0), // 713: LDDT     IDTR
    `U( 0,4'h0,1), // 714: .end
    // 1AD SMSW
    `U(34,4'h0,0), // 717: SMSW
    `U( 0,4'h0,1), // 718: .end
    // 1AF LMSW
    `U( 6,4'h0,0), // 721: LOAD     0
    `U(35,4'h0,0), // 722: LMSW
    `U( 0,4'h0,1), // 723: .end
    // 1B2 MOV_SREG_PM
    `U( 6,4'h0,0), // 726: LOAD     0
    `U(31,4'h0,0), // 727: DESC     TMP_LO
    `U(19,4'h4,0), // 728: WR_SEG   MODRM
    `U( 0,4'h0,1), // 729: .end
    // 1B6 POP_SREG_PM
    `U( 2,4'h1,0), // 732: POP      1
    `U(31,4'h1,0), // 733: DESC     TMP_HI
    `U(19,4'h8,0), // 734: WR_SEG   OPCODE
    `U( 0,4'h0,1), // 735: .end
    // 1BA LES_PM
    `U( 6,4'h0,0), // 738: LOAD      0
    `U( 6,4'h1,0), // 739: LOAD      1
    `U(31,4'h1,0), // 740: DESC      TMP_HI
    `U(18,4'ha,0), // 741: WR_REG    REG
    `U(19,4'h0,0), // 742: WR_SEG    0
    `U( 0,4'h0,1), // 743: .end
    // 1C0 LDS_PM
    `U( 6,4'h0,0), // 746: LOAD      0
    `U( 6,4'h1,0), // 747: LOAD      1
    `U(31,4'h1,0), // 748: DESC      TMP_HI
    `U(18,4'ha,0), // 749: WR_REG    REG
    `U(19,4'h3,0), // 750: WR_SEG    3
    `U( 0,4'h0,1), // 751: .end
    // 1C6 JMP_FAR_PM
    `U(31,4'h2,0), // 754: DESC     DISP
    `U(10,4'h1,0), // 755: BR_FAR   1
    `U( 0,4'h0,1), // 756: .end
    // 1C9 CALL_FAR_PM
    `U( 1,4'h0,0), // 759: PUSH     CS
    `U( 1,4'h2,0), // 760: PUSH     IP_AFTER
    `U(31,4'h2,0), // 761: DESC     DISP
    `U(10,4'h1,0), // 762: BR_FAR   1
    `U( 0,4'h0,1), // 763: .end
    // 1CE CALL_EP_PM
    `U( 1,4'h0,0), // 766: PUSH     CS
    `U( 1,4'h2,0), // 767: PUSH     IP_AFTER
    `U( 6,4'h0,0), // 768: LOAD     0
    `U( 6,4'h1,0), // 769: LOAD     1
    `U(31,4'h1,0), // 770: DESC     TMP_HI
    `U(10,4'h0,0), // 771: BR_FAR   0
    `U( 0,4'h0,1), // 772: .end
    // 1D5 JMP_EP_PM
    `U( 6,4'h0,0), // 775: LOAD     0
    `U( 6,4'h1,0), // 776: LOAD     1
    `U(31,4'h1,0), // 777: DESC     TMP_HI
    `U(10,4'h0,0), // 778: BR_FAR   0
    `U( 0,4'h0,1), // 779: .end
    // 1DA RET_FAR_PM
    `U( 2,4'h0,0), // 782: POP      0
    `U( 2,4'h1,0), // 783: POP      1
    `U(31,4'h1,0), // 784: DESC     TMP_HI
    `U(10,4'h0,0), // 785: BR_FAR   0
    `U( 0,4'h0,1), // 786: .end
    // 1DF RET_FAR_IMM_PM
    `U( 2,4'h0,0), // 789: POP      0
    `U( 2,4'h1,0), // 790: POP      1
    `U( 3,4'h0,0), // 791: ADJSP    0
    `U(31,4'h1,0), // 792: DESC     TMP_HI
    `U(10,4'h0,0), // 793: BR_FAR   0
    `U( 0,4'h0,1), // 794: .end
    // 1E5 IRET_PM
    `U( 2,4'h0,0), // 797: POP      0
    `U( 2,4'h1,0), // 798: POP      1
    `U( 2,4'h2,0), // 799: POP      2
    `U(17,4'h0,0), // 800: WR_FLAGS
    `U(31,4'h1,0), // 801: DESC     TMP_HI
    `U(10,4'h0,0), // 802: BR_FAR   0
    `U( 0,4'h0,1), // 803: .end
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1), // empty
    `U( 0,4'h0,1) // empty
};