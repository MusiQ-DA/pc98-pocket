// dcfifo stand-in for scripts/lint_core.sh. sync_fifo.sv and data_loader.sv
// instantiate the old-style Quartus megafunction by name with defparam, which
// Quartus resolves internally; Verilator needs a module to elaborate. This is
// a behavioural model, not a timing-accurate dual-clock FIFO: the pointers are
// plain binary and there are no gray-code synchronisers, so use it for lint
// and for same-rate smoke sims, not for clock-domain tests. The defparam'd
// parameters are declared so every name resolves.
`default_nettype none
module dcfifo #(
    parameter lpm_width = 32,
    parameter lpm_numwords = 4,
    parameter lpm_widthu = 2,
    parameter lpm_showahead = "OFF",
    parameter lpm_type = "dcfifo",
    parameter intended_device_family = "Cyclone V",
    parameter overflow_checking = "ON",
    parameter underflow_checking = "ON",
    parameter use_eab = "ON",
    parameter clocks_are_synchronized = "FALSE",
    parameter rdsync_delaypipe = 5,
    parameter wrsync_delaypipe = 5,
    parameter add_ram_output_register = "OFF"
) (
    input  wire                  rdclk,
    input  wire                  rdreq,
    input  wire                  wrclk,
    input  wire                  wrreq,
    input  wire                  aclr,
    input  wire [lpm_width-1:0]  data,
    output reg  [lpm_width-1:0]  q,
    output wire                  rdempty,
    output wire                  wrfull,
    output wire                  rdfull,
    output wire                  wrempty,
    output wire [lpm_widthu-1:0] rdusedw,
    output wire [lpm_widthu-1:0] wrusedw,
    output reg                   eccstatus
);
    localparam WORDS = 1 << lpm_widthu;

    reg  [lpm_width-1:0] mem [0:WORDS-1];
    reg  [lpm_widthu:0]  wbin = 0;   // extra bit distinguishes full from empty
    reg  [lpm_widthu:0]  rbin = 0;

    wire [lpm_widthu:0] used = wbin - rbin;

    assign rdempty = (used == 0);
    assign wrfull  = (used == (WORDS));
    assign rdfull  = (used == (WORDS));
    assign wrempty = (used == 0);
    assign rdusedw = used[lpm_widthu-1:0];
    assign wrusedw = used[lpm_widthu-1:0];

    always @(posedge wrclk) begin
        if (aclr) begin
            wbin <= 0;
        end else if (wrreq && used != WORDS) begin
            mem[wbin[lpm_widthu-1:0]] <= data;
            wbin <= wbin + 1'b1;
        end
    end

    always @(posedge rdclk) begin
        if (aclr) begin
            rbin     <= 0;
            q        <= {lpm_width{1'b0}};
            eccstatus <= 1'b0;
        end else if (rdreq && used != 0) begin
            q    <= mem[rbin[lpm_widthu-1:0]];
            rbin <= rbin + 1'b1;
        end
    end
endmodule
`default_nettype wire
