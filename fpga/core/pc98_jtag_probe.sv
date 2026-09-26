//
// pc98_jtag_probe -- read the diagnostic bus over the USB Blaster's JTAG.
//
// One SLD node, sld_virtual_jtag_basic with a one-bit virtual IR (unused);
// the whole protocol lives in a single 40-bit DR scan per transaction:
//
//   TDI  = {addr[7:0], 32'h00000000}  -- the last eight bits shifted in
//                                       latch the probe address
//   TDO  = rdata[31:0], LSB first     -- the value captured at the scan's
//                                       start, i.e. the PREVIOUS address's
//                                       read. Two scans per logical read:
//                                       set the address, then read.
//
// The mux lives in core_top, which sees every dbg_* wire already, so adding
// a probe point is one line there and nothing here. Costs a handful of
// registers and no firmware ROM -- the panel's readout, without a camera.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
`default_nettype none

module pc98_jtag_probe (
    // Probe bus -- the mux core_top feeds. Synchronous to tck; the values it
    // carries are quasi-static diagnostic registers, so no synchroniser chain.
    output logic [7:0]  probe_addr_sel,
    input  wire [31:0]  probe_data
);

    wire        vj_tck, vj_tdi;
    wire        vj_cdr, vj_sdr, vj_udr;
    logic       vj_tdo;
    logic [7:0]  addr_q;
    logic [39:0] shreg;

    // One node, index 0, one-bit IR. The hub addresses this instance through
    // USER1's DR; USER0 shifts our forty bits.
    sld_virtual_jtag_basic #(
        .sld_mfg_id             (11'h0),        // AMPP/third-party: vendor 0
        .sld_type_id            (8'h71),        // 'q' -- our own probe type
        .sld_version            (5'd1),
        .sld_instance_index     (0),
        .sld_auto_instance_index("YES"),
        .sld_ir_width           (1),
        .sld_sim_n_scan         (0),
        .sld_sim_action         ("UNUSED"),
        .sld_sim_total_length   (0)
    ) u_vjtag (
        .tck                (vj_tck),
        .tdi                (vj_tdi),
        .ir_in              (),
        .tdo                (vj_tdo),
        .ir_out             (1'b0),
        .virtual_state_cdr  (vj_cdr),
        .virtual_state_sdr  (vj_sdr),
        .virtual_state_e1dr (),
        .virtual_state_pdr  (),
        .virtual_state_e2dr (),
        .virtual_state_udr  (vj_udr),
        .virtual_state_cir  (),
        .virtual_state_uir  (),
        .tms                (),
        .jtag_state_tlr     (),
        .jtag_state_rti     (),
        .jtag_state_sdrs    (),
        .jtag_state_cdr     (),
        .jtag_state_sdr     (),
        .jtag_state_e1dr    (),
        .jtag_state_pdr     (),
        .jtag_state_e2dr    (),
        .jtag_state_udr     (),
        .jtag_state_sirs    (),
        .jtag_state_cir     (),
        .jtag_state_sir     (),
        .jtag_state_e1ir    (),
        .jtag_state_pir     (),
        .jtag_state_e2ir    (),
        .jtag_state_uir     ()
    );

    // {8 bits of next address} above {32 bits of answer}. Bits enter at bit 39
    // and leave at bit 0, so the last eight TDI bits land in [39:32] and the
    // captured answer exits least-significant first.
    always_ff @(posedge vj_tck) begin
        if (vj_cdr)
            shreg <= {8'h00, probe_data};
        else if (vj_sdr)
            shreg <= {vj_tdi, shreg[39:1]};
        if (vj_udr)
            addr_q <= shreg[39:32];
    end

    assign vj_tdo            = shreg[0];
    assign probe_addr_sel    = addr_q;

endmodule

`default_nettype wire
