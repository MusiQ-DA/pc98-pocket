// The address bus is twelve bits, so the array has to be too.
//
// It used to be declared to the exact length of microcode.mem, 3962 words, and
// every read from 0x0F7A upward was outside it. The sequencer prefetches PC+1,
// so the last real microinstruction -- 0x0F79, the unconditional jump that ends
// MUL8 -- sat next to an out-of-range read, and the undefined value beside it
// took the jump away. The EU then walked forward through empty microcode until
// it landed back in the opcode dispatch table with a stale byte, and every
// MUL r/m8 desynchronised the instruction stream.
//
// That is why a PC-98 ITF hangs on this core: its first job is a CPU flag
// self-test, and the test uses MUL. The PC/AT BIOS reached POST only because it
// never executes one.
//
// microcode.mem is padded to 4096 words to match.
module eu_rom(
  input clka,
  input [11:0] addra,
  output reg [31:0] douta
);

reg [31:0] memory[4095:0];

initial $readmemh("microcode.mem", memory);

always @(posedge clka)
  douta <= memory[addra];

endmodule