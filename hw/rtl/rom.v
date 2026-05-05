module rom 
#(
	parameter ROM_DEPTH    = 128,
	parameter SAMPLE_WIDTH = 16
)
(
	input  wire                         clk,
	input  wire [$clog2(ROM_DEPTH)-1:0] addr,

	output reg  [SAMPLE_WIDTH-1:0]      data_out
);

	reg[SAMPLE_WIDTH-1:0] mem[0:ROM_DEPTH-1];

	initial begin
		$readmemh("OV7670_conf.mem", mem);
	end

	always @(posedge clk) begin
		data_out <= mem[addr];
	end

endmodule