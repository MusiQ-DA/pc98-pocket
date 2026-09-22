// Minimal altsyncram for the softcore testbench: the instances in
// softcpu_subsystem are the OSD framebuffer (8/8 bit ports) and the OSD font
// RAM (a 32-bit CPU port over the same memory the 8-bit glyph port reads).
// Simple dual-port behavioural model with byte enables and mixed port widths,
// enough to elaborate and run. The output is unregistered (one-cycle read),
// matching every instance's outdata_reg_* setting.
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
    // clock2/clock3 are deliberately absent: they only exist on the real
    // megafunction in operation modes this design never selects, and Quartus
    // errors on a connection to a port the variant does not have.
    input  wire  [1:0]           eccstatus
);
    // One byte-granular memory both widths view, so a wide port A and a narrow
    // port B address the same bytes (that is the font RAM's whole job).
    localparam BYTES_A = numwords_a * width_a / 8;
    localparam BYTES_B = numwords_b * width_b / 8;
    localparam MEM_BYTES = (BYTES_A > BYTES_B) ? BYTES_A : BYTES_B;
    reg [7:0] mem [0:MEM_BYTES-1];

    always @(posedge clock0) begin
        if (wren_a) begin
            for (int i = 0; i < width_a/8; i++)
                if (byteena_a[i])
                    mem[address_a*(width_a/8) + i] <= data_a[i*8 +: 8];
        end
        for (int i = 0; i < width_a/8; i++)
            q_a[i*8 +: 8] <= mem[address_a*(width_a/8) + i];
    end
    always @(posedge clock1) begin
        if (wren_b) begin
            for (int i = 0; i < width_b/8; i++)
                if (byteena_b[i])
                    mem[address_b*(width_b/8) + i] <= data_b[i*8 +: 8];
        end
        for (int i = 0; i < width_b/8; i++)
            q_b[i*8 +: 8] <= mem[address_b*(width_b/8) + i];
    end
    wire _unused = &{1'b0, aclr0, aclr1, addressstall_a, addressstall_b,
                     clocken0, clocken1, clocken2, clocken3,
                     rden_a, rden_b, eccstatus, 1'b0};
endmodule
`default_nettype wire
