// Minimal sld_virtual_jtag_basic for lint and benches: the JTAG-side pins
// idle, and tdo is never shifted, so the probe block it feeds just sits. The
// point is elaboration -- the real megafunction only exists inside Quartus.
`default_nettype none
module sld_virtual_jtag_basic #(
    parameter sld_mfg_id = 0,
    parameter sld_type_id = 0,
    parameter sld_version = 0,
    parameter sld_instance_index = 0,
    parameter sld_auto_instance_index = "NO",
    parameter sld_ir_width = 1,
    parameter sld_sim_n_scan = 0,
    parameter sld_sim_action = "UNUSED",
    parameter sld_sim_total_length = 0,
    parameter lpm_type = "sld_virtual_jtag_basic",
    parameter lpm_hint = "UNUSED"
) (
    output tck,
    output tdi,
    output [sld_ir_width-1:0] ir_in,
    input  tdo,
    input  [sld_ir_width-1:0] ir_out,
    output virtual_state_cdr,
    output virtual_state_sdr,
    output virtual_state_e1dr,
    output virtual_state_pdr,
    output virtual_state_e2dr,
    output virtual_state_udr,
    output virtual_state_cir,
    output virtual_state_uir,
    output tms,
    output jtag_state_tlr,
    output jtag_state_rti,
    output jtag_state_sdrs,
    output jtag_state_cdr,
    output jtag_state_sdr,
    output jtag_state_e1dr,
    output jtag_state_pdr,
    output jtag_state_e2dr,
    output jtag_state_udr,
    output jtag_state_sirs,
    output jtag_state_cir,
    output jtag_state_sir,
    output jtag_state_e1ir,
    output jtag_state_pir,
    output jtag_state_e2ir,
    output jtag_state_uir
);
    assign tck = 1'b0;
    assign tdi = 1'b0;
    assign ir_in = {sld_ir_width{1'b0}};
    assign virtual_state_cdr = 1'b0;
    assign virtual_state_sdr = 1'b0;
    assign virtual_state_e1dr = 1'b0;
    assign virtual_state_pdr = 1'b0;
    assign virtual_state_e2dr = 1'b0;
    assign virtual_state_udr = 1'b0;
    assign virtual_state_cir = 1'b0;
    assign virtual_state_uir = 1'b0;
    assign tms = 1'b0;
    assign jtag_state_tlr = 1'b0;
    assign jtag_state_rti = 1'b0;
    assign jtag_state_sdrs = 1'b0;
    assign jtag_state_cdr = 1'b0;
    assign jtag_state_sdr = 1'b0;
    assign jtag_state_e1dr = 1'b0;
    assign jtag_state_pdr = 1'b0;
    assign jtag_state_e2dr = 1'b0;
    assign jtag_state_udr = 1'b0;
    assign jtag_state_sirs = 1'b0;
    assign jtag_state_cir = 1'b0;
    assign jtag_state_sir = 1'b0;
    assign jtag_state_e1ir = 1'b0;
    assign jtag_state_pir = 1'b0;
    assign jtag_state_e2ir = 1'b0;
    assign jtag_state_uir = 1'b0;
endmodule
`default_nettype wire
