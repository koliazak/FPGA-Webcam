`timescale 1ns / 1ps

// Single-port RAM. Both read and write are gated by `en`,
// so with an address cycling 0..DEPTH-1 it acts as a delay line of
// exactly DEPTH enabled steps.
module ram #(
    parameter WIDTH=8,
    parameter DEPTH=640
)(
    input wire clk,
    input wire en,

    input wire [$clog2(DEPTH)-1:0] addr,
    input wire [WIDTH-1:0] din,
    output reg [WIDTH-1:0] dout
);

    reg [WIDTH-1:0] ram[0:DEPTH-1];

    always @(posedge clk) begin
        if (en) begin
            dout      <= ram[addr];
            ram[addr] <= din;
        end
    end

endmodule
