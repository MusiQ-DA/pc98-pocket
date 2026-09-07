// Minimal altsyncram for the softcore testbench: the only instance in
// softcpu_subsystem is the OSD framebuffer, and the disk bridge has its own.
// Simple dual-port behavioural model, enough to elaborate and run.
`default_nettype none
module altsyncram #(
    parameter operation_mode = "BIDIR_DUAL_PORT",
    parameter width_a = 8, parameter widthad_a = 14, parameter numwords_a = 16384,
    parameter width_b = 8, parameter widthad_b = 14, parameter numwords_b = 16384,
    parameter address_reg_b = "CLOCK1",
    parameter outdata_reg_a = "UNREGISTERED",
    parameter outdata_reg_b = "UNREGISTERED",
    parameter lpm_type = "altsyncram",
    parameter intended_device_family = "Cyclone V",
    parameter init_file = ""
) (
    input  wire                  clock0,
    input  wire                  clock1,
    input  wire [widthad_a-1:0]  address_a,
    input  wire [width_a-1:0]    data_a,
    input  wire                  wren_a,
    output reg  [width_a-1:0]    q_a,
    input  wire [widthad_b-1:0]  address_b,
    input  wire [width_b-1:0]    data_b,
    input  wire                  wren_b,
    output reg  [width_b-1:0]    q_b,
    input  wire                  aclr0,
    input  wire                  aclr1,
    // Optional altsyncram ports the real megafunction carries; unused here but
    // instantiations connect them by name.
    input  wire                  addressstall_a,
    input  wire                  addressstall_b,
    input  wire [width_a/8-1:0]  byteena_a,
    input  wire [width_b/8-1:0]  byteena_b,
    input  wire                  clocken0,
    input  wire                  clocken1,
    input  wire                  clocken2,
    input  wire                  clocken3,
    input  wire                  rden_a,
    input  wire                  rden_b,
    input  wire                  clock2,
    input  wire                  clock3,
    input  wire  [1:0]           eccstatus
);
    reg [width_a-1:0] mem [0:numwords_a-1];
    always @(posedge clock0) begin
        if (wren_a) mem[address_a] <= data_a;
        q_a <= mem[address_a];
    end
    always @(posedge clock1) begin
        if (wren_b) mem[address_b] <= data_b;
        q_b <= mem[address_b];
    end
    wire _unused = &{1'b0, aclr0, aclr1, addressstall_a, addressstall_b,
                     byteena_a, byteena_b, clocken0, clocken1, clocken2,
                     clocken3, rden_a, rden_b, clock2, clock3, eccstatus, 1'b0};
endmodule
`default_nettype wire
