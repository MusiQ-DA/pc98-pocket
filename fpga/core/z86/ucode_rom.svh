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
    `U( 6,4'h6,0), // 124: LOAD      0b0110
    `U( 7,4'h6,0), // 125: STORE     0b0110
    `U( 0,4'h0,1), // 126: .end
    // 50 REP_MOVSB
    `U(12,4'h0,0), // 129: TESTZX
    `U(14,4'h4,0), // 130: JT        4
    `U( 6,4'h6,0), // 131: LOAD      0b0110
    `U( 7,4'h6,0), // 132: STORE     0b0110
    `U(21,4'h1,0), // 133: DEC       CX
    `U(13,4'ha,0), // 134: J         -6
    `U( 0,4'h0,1), // 135: .end
    // 57 MOVSW
    `U( 6,4'he,0), // 140: LOAD      0b1110
    `U( 7,4'he,0), // 141: STORE     0b1110
    `U( 0,4'h0,1), // 142: .end
    // 5A REP_MOVSW
    `U(12,4'h0,0), // 145: TESTZX
    `U(14,4'h4,0), // 146: JT        4
    `U( 6,4'he,0), // 147: LOAD      0b1110
    `U( 7,4'he,0), // 148: STORE     0b1110
    `U(21,4'h1,0), // 149: DEC       CX
    `U(13,4'ha,0), // 150: J         -6
    `U( 0,4'h0,1), // 151: .end
    // 61 CMPSB
    `U( 6,4'h6,0), // 156: LOAD      0b0110
    `U( 6,4'h7,0), // 157: LOAD      0b0111
    `U(20,4'h0,0), // 158: STR_CMP   0
    `U( 0,4'h0,1), // 159: .end
    // 65 REPNE_CMPSB
    `U(12,4'h0,0), // 162: TESTZX
    `U(14,4'h6,0), // 163: JT        6
    `U( 6,4'h6,0), // 164: LOAD      0b0110
    `U( 6,4'h7,0), // 165: LOAD      0b0111
    `U(21,4'h1,0), // 166: DEC       CX
    `U(20,4'h0,0), // 167: STR_CMP   0
    `U(11,4'h3,0), // 168: TESTF     ZF
    `U(15,4'h8,0), // 169: JF        -8
    `U( 0,4'h0,1), // 170: .end
    // 6E REPE_CMPSB
    `U(12,4'h0,0), // 173: TESTZX
    `U(14,4'h6,0), // 174: JT        6
    `U( 6,4'h6,0), // 175: LOAD      0b0110
    `U( 6,4'h7,0), // 176: LOAD      0b0111
    `U(21,4'h1,0), // 177: DEC       CX
    `U(20,4'h0,0), // 178: STR_CMP   0
    `U(11,4'h3,0), // 179: TESTF     ZF
    `U(14,4'h8,0), // 180: JT        -8
    `U( 0,4'h0,1), // 181: .end
    // 77 CMPSW
    `U( 6,4'he,0), // 186: LOAD      0b1110
    `U( 6,4'hf,0), // 187: LOAD      0b1111
    `U(20,4'h1,0), // 188: STR_CMP   1
    `U( 0,4'h0,1), // 189: .end
    // 7B REPNE_CMPSW
    `U(12,4'h0,0), // 192: TESTZX
    `U(14,4'h6,0), // 193: JT        6
    `U( 6,4'he,0), // 194: LOAD      0b1110
    `U( 6,4'hf,0), // 195: LOAD      0b1111
    `U(21,4'h1,0), // 196: DEC       CX
    `U(20,4'h1,0), // 197: STR_CMP   1
    `U(11,4'h3,0), // 198: TESTF     ZF
    `U(15,4'h8,0), // 199: JF        -8
    `U( 0,4'h0,1), // 200: .end
    // 84 REPE_CMPSW
    `U(12,4'h0,0), // 203: TESTZX
    `U(14,4'h6,0), // 204: JT        6
    `U( 6,4'he,0), // 205: LOAD      0b1110
    `U( 6,4'hf,0), // 206: LOAD      0b1111
    `U(21,4'h1,0), // 207: DEC       CX
    `U(20,4'h1,0), // 208: STR_CMP   1
    `U(11,4'h3,0), // 209: TESTF     ZF
    `U(14,4'h8,0), // 210: JT        -8
    `U( 0,4'h0,1), // 211: .end
    // 8D REP_CMPSW
    `U(12,4'h0,0), // 214: TESTZX
    `U(14,4'h5,0), // 215: JT        5
    `U( 6,4'he,0), // 216: LOAD      0b1110
    `U( 6,4'hf,0), // 217: LOAD      0b1111
    `U(21,4'h1,0), // 218: DEC       CX
    `U(20,4'h1,0), // 219: STR_CMP   1
    `U(13,4'h9,0), // 220: J         -7
    `U( 0,4'h0,1), // 221: .end
    // 95 STOSB
    `U( 7,4'h7,0), // 226: STORE     0b0111
    `U( 0,4'h0,1), // 227: .end
    // 97 REP_STOSB
    `U(12,4'h0,0), // 230: TESTZX
    `U(14,4'h3,0), // 231: JT        3
    `U(21,4'h1,0), // 232: DEC       CX
    `U( 7,4'h7,0), // 233: STORE     0b0111
    `U(13,4'hb,0), // 234: J         -5
    `U( 0,4'h0,1), // 235: .end
    // 9D STOSW
    `U( 7,4'hf,0), // 240: STORE     0b1111
    `U( 0,4'h0,1), // 241: .end
    // 9F REP_STOSW
    `U(12,4'h0,0), // 244: TESTZX
    `U(14,4'h3,0), // 245: JT        3
    `U(21,4'h1,0), // 246: DEC       CX
    `U( 7,4'hf,0), // 247: STORE     0b1111
    `U(13,4'hb,0), // 248: J         -5
    `U( 0,4'h0,1), // 249: .end
    // A5 LODSB
    `U( 6,4'h6,0), // 254: LOAD      0b0110
    `U(18,4'h8,0), // 255: WR_REG    AL
    `U( 0,4'h0,1), // 256: .end
    // A8 REP_LODSB
    `U(12,4'h0,0), // 259: TESTZX
    `U(14,4'h4,0), // 260: JT        4
    `U( 6,4'h6,0), // 261: LOAD      0b0110
    `U(21,4'h1,0), // 262: DEC       CX
    `U(18,4'h8,0), // 263: WR_REG    AL
    `U(13,4'ha,0), // 264: J         -6
    `U( 0,4'h0,1), // 265: .end
    // AF LODSW
    `U( 6,4'he,0), // 270: LOAD      0b1110
    `U(18,4'h0,0), // 271: WR_REG    AX
    `U( 0,4'h0,1), // 272: .end
    // B2 REP_LODSW
    `U(12,4'h0,0), // 275: TESTZX
    `U(14,4'h4,0), // 276: JT        4
    `U( 6,4'he,0), // 277: LOAD      0b1110
    `U(21,4'h1,0), // 278: DEC       CX
    `U(18,4'h0,0), // 279: WR_REG    AX
    `U(13,4'ha,0), // 280: J         -6
    `U( 0,4'h0,1), // 281: .end
    // B9 SCASB
    `U( 6,4'h7,0), // 286: LOAD      0b0111
    `U(20,4'h0,0), // 287: STR_CMP   0
    `U( 0,4'h0,1), // 288: .end
    // BC REPNE_SCASB
    `U(12,4'h0,0), // 291: TESTZX
    `U(14,4'h5,0), // 292: JT        5
    `U( 6,4'h7,0), // 293: LOAD      0b0111
    `U(21,4'h1,0), // 294: DEC       CX
    `U(20,4'h0,0), // 295: STR_CMP   0
    `U(11,4'h3,0), // 296: TESTF     ZF
    `U(15,4'h9,0), // 297: JF        -7
    `U( 0,4'h0,1), // 298: .end
    // C4 REPE_SCASB
    `U(12,4'h0,0), // 301: TESTZX
    `U(14,4'h5,0), // 302: JT        5
    `U( 6,4'h7,0), // 303: LOAD      0b0111
    `U(21,4'h1,0), // 304: DEC       CX
    `U(20,4'h0,0), // 305: STR_CMP   0
    `U(11,4'h3,0), // 306: TESTF     ZF
    `U(14,4'h9,0), // 307: JT        -7
    `U( 0,4'h0,1), // 308: .end
    // CC SCASW
    `U( 6,4'hf,0), // 313: LOAD      0b1111
    `U(20,4'h1,0), // 314: STR_CMP   1
    `U( 0,4'h0,1), // 315: .end
    // CF REPNE_SCASW
    `U(12,4'h0,0), // 318: TESTZX
    `U(14,4'h5,0), // 319: JT        5
    `U( 6,4'hf,0), // 320: LOAD      0b1111
    `U(21,4'h1,0), // 321: DEC       CX
    `U(20,4'h1,0), // 322: STR_CMP   1
    `U(11,4'h3,0), // 323: TESTF     ZF
    `U(15,4'h9,0), // 324: JF        -7
    `U( 0,4'h0,1), // 325: .end
    // D7 REPE_SCASW
    `U(12,4'h0,0), // 328: TESTZX
    `U(14,4'h5,0), // 329: JT        5
    `U( 6,4'hf,0), // 330: LOAD      0b1111
    `U(21,4'h1,0), // 331: DEC       CX
    `U(20,4'h1,0), // 332: STR_CMP   1
    `U(11,4'h3,0), // 333: TESTF     ZF
    `U(14,4'h9,0), // 334: JT        -7
    `U( 0,4'h0,1), // 335: .end
    // DF LES
    `U( 6,4'h0,0), // 340: LOAD      0
    `U( 6,4'h1,0), // 341: LOAD      1
    `U(18,4'ha,0), // 342: WR_REG    REG
    `U(19,4'h0,0), // 343: WR_SEG    0
    `U( 0,4'h0,1), // 344: .end
    // E4 LDS
    `U( 6,4'h0,0), // 347: LOAD      0
    `U( 6,4'h1,0), // 348: LOAD      1
    `U(18,4'ha,0), // 349: WR_REG    REG
    `U(19,4'h3,0), // 350: WR_SEG    3
    `U( 0,4'h0,1), // 351: .end
    // E9 PUSHF
    `U( 1,4'h4,0), // 356: PUSH      FLAGS
    `U( 0,4'h0,1), // 357: .end
    // EB POPF
    `U( 2,4'h2,0), // 360: POP       TMP_FLAGS
    `U(17,4'h0,0), // 361: WR_FLAGS
    `U( 0,4'h0,1), // 362: .end
    // EE PUSH_R16
    `U( 1,4'h3,0), // 365: PUSH      RM
    `U( 0,4'h0,1), // 366: .end
    // F0 PUSH_M16
    `U( 6,4'h0,0), // 369: LOAD      0
    `U( 1,4'h5,0), // 370: PUSH      TMP_LO
    `U( 0,4'h0,1), // 371: .end
    // F3 MUL8
    `U( 6,4'h0,0), // 376: LOAD      0
    `U(22,4'h0,0), // 377: MULU      0
    `U( 0,4'h0,1), // 378: .end
    // F6 MUL16
    `U( 6,4'h8,0), // 381: LOAD      8
    `U(22,4'h1,0), // 382: MULU      1
    `U( 0,4'h0,1), // 383: .end
    // F9 IMUL8
    `U( 6,4'h0,0), // 386: LOAD      0
    `U(23,4'h0,0), // 387: MULS      0
    `U( 0,4'h0,1), // 388: .end
    // FC IMUL16
    `U( 6,4'h0,0), // 391: LOAD      0
    `U(23,4'h1,0), // 392: MULS      1
    `U( 0,4'h0,1), // 393: .end
    // FF DIV8
    `U( 6,4'h0,0), // 400: LOAD      0
    `U(24,4'h0,0), // 401: DIV       0b00
    `U(14,4'h1,0), // 402: JT       1
    `U( 0,4'h0,1), // 403: .end
    `U( 4,4'h0,0), // 405: GETVEC_OFF      0
    `U( 5,4'h0,0), // 406: GETVEC_SEG      0
    `U( 1,4'h4,0), // 407: PUSH  FLAGS
    `U( 1,4'h0,0), // 408: PUSH  CS
    `U( 1,4'h2,0), // 409: PUSH  IP_AFTER
    `U(10,4'h0,0), // 410: BR_FAR     0
    `U( 0,4'h0,1), // 411: .end
    // 10A DIV16
    `U( 6,4'h0,0), // 414: LOAD      0
    `U(24,4'h1,0), // 415: DIV       0b01
    `U(14,4'h1,0), // 416: JT       1
    `U( 0,4'h0,1), // 417: .end
    `U( 4,4'h0,0), // 419: GETVEC_OFF      0
    `U( 5,4'h0,0), // 420: GETVEC_SEG      0
    `U( 1,4'h4,0), // 421: PUSH  FLAGS
    `U( 1,4'h0,0), // 422: PUSH  CS
    `U( 1,4'h2,0), // 423: PUSH  IP_AFTER
    `U(10,4'h0,0), // 424: BR_FAR     0
    `U( 0,4'h0,1), // 425: .end
    // 115 IDIV8
    `U( 6,4'h0,0), // 428: LOAD      0
    `U(24,4'h2,0), // 429: DIV       0b10
    `U(14,4'h1,0), // 430: JT       1
    `U( 0,4'h0,1), // 431: .end
    `U( 4,4'h0,0), // 433: GETVEC_OFF      0
    `U( 5,4'h0,0), // 434: GETVEC_SEG      0
    `U( 1,4'h4,0), // 435: PUSH  FLAGS
    `U( 1,4'h0,0), // 436: PUSH  CS
    `U( 1,4'h2,0), // 437: PUSH  IP_AFTER
    `U(10,4'h0,0), // 438: BR_FAR     0
    `U( 0,4'h0,1), // 439: .end
    // 120 IDIV16
    `U( 6,4'h0,0), // 442: LOAD      0
    `U(24,4'h3,0), // 443: DIV       0b11
    `U(14,4'h1,0), // 444: JT       1
    `U( 0,4'h0,1), // 445: .end
    `U( 4,4'h0,0), // 447: GETVEC_OFF      0
    `U( 5,4'h0,0), // 448: GETVEC_SEG      0
    `U( 1,4'h4,0), // 449: PUSH  FLAGS
    `U( 1,4'h0,0), // 450: PUSH  CS
    `U( 1,4'h2,0), // 451: PUSH  IP_AFTER
    `U(10,4'h0,0), // 452: BR_FAR     0
    `U( 0,4'h0,1), // 453: .end
    // 12B DAA
    `U(25,4'h0,0), // 461: ADJ   0
    `U( 0,4'h0,1), // 462: .end
    // 12D DAS
    `U(25,4'h1,0), // 465: ADJ   1
    `U( 0,4'h0,1), // 466: .end
    // 12F AAA
    `U(25,4'h2,0), // 469: ADJ   2
    `U( 0,4'h0,1), // 470: .end
    // 131 AAS
    `U(25,4'h3,0), // 473: ADJ   3
    `U( 0,4'h0,1), // 474: .end
    // 133 AAM
    `U(25,4'h4,0), // 477: ADJ       4
    `U(14,4'h1,0), // 478: JT       1
    `U( 0,4'h0,1), // 479: .end
    `U( 4,4'h0,0), // 480: GETVEC_OFF      0
    `U( 5,4'h0,0), // 481: GETVEC_SEG      0
    `U( 1,4'h4,0), // 482: PUSH  FLAGS
    `U( 1,4'h0,0), // 483: PUSH  CS
    `U( 1,4'h2,0), // 484: PUSH  IP_AFTER
    `U(10,4'h0,0), // 485: BR_FAR     0
    `U( 0,4'h0,1), // 486: .end
    // 13D AAD
    `U(26,4'h0,0), // 490: AAD
    `U( 0,4'h0,1), // 491: .end
    // 13F HLT
    `U(30,4'h0,0), // 495: HALT
    `U( 0,4'h0,1), // 496: .end
    // 141 PUSHA
    `U(16,4'h4,0), // 504: READ     SP
    `U( 1,4'h8,0), // 505: PUSH     AX
    `U( 1,4'h9,0), // 506: PUSH     CX
    `U( 1,4'ha,0), // 507: PUSH     DX
    `U( 1,4'hb,0), // 508: PUSH     BX
    `U( 1,4'h5,0), // 509: PUSH     TMP_LO
    `U( 1,4'hd,0), // 510: PUSH     BP
    `U( 1,4'he,0), // 511: PUSH     SI
    `U( 1,4'hf,0), // 512: PUSH     DI
    `U( 0,4'h0,1), // 513: .end
    // 14B POPA
    `U( 2,4'hf,0), // 516: POP      DI
    `U( 2,4'he,0), // 517: POP      SI
    `U( 2,4'hd,0), // 518: POP      BP
    `U( 2,4'h0,0), // 519: POP      TMP_LO
    `U( 2,4'hb,0), // 520: POP      BX
    `U( 2,4'ha,0), // 521: POP      DX
    `U( 2,4'h9,0), // 522: POP      CX
    `U( 2,4'h8,0), // 523: POP      AX
    `U( 0,4'h0,1), // 524: .end
    // 154 BOUND
    `U( 6,4'h0,0), // 530: LOAD   0
    `U( 6,4'h1,0), // 531: LOAD   1
    `U(27,4'h0,0), // 532: IN_RANGE
    `U(14,4'h5,0), // 533: JT     5
    `U( 4,4'h5,0), // 535: GETVEC_OFF 5
    `U( 5,4'h5,0), // 536: GETVEC_SEG 5
    `U( 1,4'h0,0), // 537: PUSH     CS
    `U( 1,4'h2,0), // 538: PUSH     IP_AFTER
    `U(10,4'h0,0), // 539: BR_FAR   0
    `U( 0,4'h0,1), // 540: .end
    // 15E ARPL
    `U( 0,4'h0,1), // 551: .end
    // 15F IMUL_IW
    `U( 6,4'h0,0), // 556: LOAD     0
    `U(23,4'h3,0), // 557: MULS     3
    `U( 0,4'h0,1), // 558: .end
    // 162 IMUL_IB
    `U( 6,4'h0,0), // 561: LOAD     0
    `U(23,4'h2,0), // 562: MULS     2
    `U( 0,4'h0,1), // 563: .end
    // 165 INSB
    `U(28,4'h0,0), // 568: IN      BYTE
    `U( 7,4'h6,0), // 569: STORE   0b0110
    `U( 0,4'h0,1), // 570: .end
    // 168 INSW
    `U(28,4'h1,0), // 573: IN      WORD
    `U( 7,4'he,0), // 574: STORE   0b1110
    `U( 0,4'h0,1), // 575: .end
    // 16B OUTSB
    `U( 6,4'h6,0), // 578: LOAD    0b0110
    `U(29,4'h0,0), // 579: OUT     BYTE
    `U( 0,4'h0,1), // 580: .end
    // 16E OUTSW
    `U( 6,4'he,0), // 583: LOAD    0b1110
    `U(29,4'h1,0), // 584: OUT     WORD
    `U( 0,4'h0,1), // 585: .end
    // 171 ENTER
    `U( 1,4'hd,0), // 607: PUSH     BP
    `U(16,4'h8,0), // 608: READ     ENTER_IB
    `U(16,4'h4,0), // 609: READ     SP
    `U(18,4'h5,0), // 610: WR_REG   BP
    `U(12,4'h1,0), // 614: TESTZX   TMP_HI
    `U(14,4'h3,0), // 615: JT       3
    `U( 1,4'hd,0), // 616: PUSH     BP
    `U(21,4'h8,0), // 617: DEC      TMP_HI
    `U(13,4'hb,0), // 618: J        -5
    `U( 3,4'h1,0), // 620: ADJSP    SUB_IW
    `U( 0,4'h0,1), // 621: .end
    // 17C LEAVE
    `U(16,4'h5,0), // 624: READ     BP
    `U(18,4'h4,0), // 625: WR_REG   SP
    `U( 2,4'hd,0), // 626: POP      BP
    `U( 0,4'h0,1), // 627: .end
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