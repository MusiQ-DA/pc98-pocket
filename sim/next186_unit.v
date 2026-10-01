//============================================================================
//
//  next186_unit -- Next186_CPU + BIU186_32bSync_2T_DelayRead as one unit,
//  the shape upstream calls unit186 (fpga/core/next186/soc_ref/unit186.v)
//  minus the SoC's VGA ports, plus the WSEL fix upstream left dangling.
//
//  Lint and area-measurement top for the vendored core; also the
//  instantiation template next186_cpu_bridge will wrap. Every pin the
//  bridge needs to watch or drive is exported. The stall model and the
//  meaning of each port are in fpga/core/next186/INTEGRATION_NOTES.md.
//
//  The DIN mux is upstream's: I/O reads and the interrupt-acknowledge stage
//  take PORT_DIN (the 8-bit-bus side's answer); memory reads take the
//  BIU's RAM-port translation.
//
//  SPDX-License-Identifier: LGPL-2.1-or-later (matches the vendored core)
//
//============================================================================

`timescale 1ns / 1ps

module next186_unit (
    input         CLK,
    input         CE,          // unit tick: bridge-gated cpu_ce train
    input         RST,
    input         INTR,        // level, from the PIC's INT output
    input         NMI,         // edge-detected inside the CPU

    // CPU status / I/O + INTA surface
    output        HALT,
    output        LOCK,
    output        INTA,        // comb pulse: vector wanted on DIN now
    output        IORQ,        // port access this stage
    output        MREQ,        // data memory access this stage
    output        WR,
    output        WORD,
    output [20:0] ADDR,        // byte addr; [15:0] is the port when IORQ
    output [15:0] PORT_ADDR,
    output [15:0] DOUT,        // CPU write data
    input  [15:0] PORT_DIN,    // I/O or INTA read data (vector in [7:0])
    output        CE186,       // BIU's CPU-tick gate, exported so the
                               // bridge can see when a tick would retire
                               // a CPU stage (stall checks)

    // BIU's 32-bit fixed-latency "SRAM" port -- served by the bridge
    input  [31:0] RAM_DIN,
    output [31:0] RAM_DOUT,
    output [18:0] RAM_ADDR,
    output        RAM_MREQ,
    output  [3:0] RAM_WMASK,
    output        RAM_RD,
    output        RAM_WR,

    // fetch-stream observability (debug; the bridge does not serve these)
    output [20:0] IADDR,
    output        IFETCH,
    output        FLUSH
);

    wire [15:0] cpu_din;
    wire [15:0] biu_dout;
    wire [47:0] cpu_instr;
    wire        cpu_mreq;
    wire        cpu_iorq;
    wire        cpu_inta;
    wire        cpu_wr;
    wire        cpu_word;
    wire [20:0] cpu_addr;
    wire [2:0]  cpu_isize;
    wire        ce_186;

    assign cpu_din   = (cpu_iorq | cpu_inta) ? PORT_DIN : biu_dout;
    assign PORT_ADDR = cpu_addr[15:0];
    assign IORQ      = cpu_iorq;
    assign INTA      = cpu_inta;
    assign MREQ      = cpu_mreq;
    assign WR        = cpu_wr;
    assign WORD      = cpu_word;
    assign ADDR      = cpu_addr;
    assign CE186     = ce_186;

    Next186_CPU cpu (
        .ADDR   (cpu_addr),
        .DIN    (cpu_din),
        .DOUT   (DOUT),
        .CLK    (CLK),
        .CE     (ce_186 & CE),
        .INTR   (INTR),
        .NMI    (NMI),
        .RST    (RST),
        .MREQ   (cpu_mreq),
        .IORQ   (cpu_iorq),
        .INTA   (cpu_inta),
        .WR     (cpu_wr),
        .WORD   (cpu_word),
        .LOCK   (LOCK),
        .IADDR  (IADDR),
        .INSTR  (cpu_instr),
        .IFETCH (IFETCH),
        .FLUSH  (FLUSH),
        .ISIZE  (cpu_isize),
        .HALT   (HALT)
    );

    BIU186_32bSync_2T_DelayRead biu (
        .CLK        (CLK),
        .INSTR      (cpu_instr),
        .ISIZE      (cpu_isize),
        .IFETCH     (IFETCH),
        .FLUSH      (FLUSH),
        .MREQ       (cpu_mreq),
        .WR         (cpu_wr),
        .WORD       (cpu_word),
        .ADDR       (cpu_addr),
        .IADDR      (IADDR),
        .CE186      (ce_186),
        .RAM_DIN    (RAM_DIN),
        .RAM_DOUT   (RAM_DOUT),
        .RAM_ADDR   (RAM_ADDR),
        .RAM_MREQ   (RAM_MREQ),
        .RAM_WMASK  (RAM_WMASK),
        .DOUT       (biu_dout),
        .DIN        (DOUT),
        .CE         (CE),
        .data_bound (),
        // upstream leaves WSEL dangling and eats the lane bug on odd-byte
        // writes; the port comment says it wants {~A0, A0}
        .WSEL       ({~cpu_addr[0], cpu_addr[0]}),
        .RAM_RD     (RAM_RD),
        .RAM_WR     (RAM_WR)
    );

endmodule
