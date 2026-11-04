`timescale 1ns / 1ps


module rect_addr_gen 
//#(
//    parameter W         = 640,
//    parameter H         = 480,
//    parameter GRID_STEP = 16
//)

(
    input wire         clk,
    input wire         rst_n,

    //input  wire [$clog2(W)-1:0]  u, // 0..639
    //input  wire [$clog2(H)-1:0]  v, // 0..479
    input  wire [9:0]  u, // 0..639
    input  wire [8:0]  v, // 0..479
    input  wire        valid_in,

    // BRAM addresses
    output reg  [10:0] addr_00, // top left
    output reg  [10:0] addr_01, // top right
    output reg  [10:0] addr_10, // down left
    output reg  [10:0] addr_11, // down right
    

    // 0..16 relative addresses for interpolation
    output reg  [3:0]  dx,
    output reg  [3:0]  dy,
    output reg         valid_out

);


    wire [5:0] idx_u = u[9:4]; 
    wire [4:0] idx_v = v[8:4];


    wire [5:0] idx_u_next = (idx_u == 6'd40) ? 6'd40 : idx_u + 1'b1; 
    wire [4:0] idx_v_next = (idx_v == 6'd30) ? 6'd30 : idx_v + 1'b1;


    always @(posedge clk) begin
        if (!rst_n) begin
            addr_00 <= 0;
            addr_01 <= 0;
            addr_10 <= 0;
            addr_11 <= 0;
            dx <= 0;
            dy <= 0;
            valid_out <= 0;
        end else begin
            addr_00 <= (idx_v      * 6'd41) + idx_u; 
            addr_01 <= (idx_v      * 6'd41) + idx_u_next; 
            addr_10 <= (idx_v_next * 6'd41) + idx_u; 
            addr_11 <= (idx_v_next * 6'd41) + idx_u_next; 

            dx <= u[3:0];
            dy <= v[3:0];
            valid_out <= valid_in;
        end
    end


endmodule
