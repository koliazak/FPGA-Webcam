`timescale 1ns / 1ps


module bilinear_interp_core (
    input wire               clk,
    input wire               rst_n,

    input wire signed [17:0] v00, // top left
    input wire signed [17:0] v01, // top right
    input wire signed [17:0] v10, // bottom left
    input wire signed [17:0] v11, // bottom right

    input wire        [3:0]  dx,
    input wire        [3:0]  dy,
    input wire               valid_in,

    output reg signed [17:0] result,
    output reg               valid_out
);


    reg signed [17:0] top_val;
    reg signed [17:0] bot_val;

    reg [3:0] dy_reg;
    reg       valid_reg;


    always @(posedge clk) begin
        if (!rst_n) begin
            result    <= 0;
            valid_out <= 0;
            dy_reg    <= 0;
            valid_reg <= 0;
            top_val   <= 0;
            bot_val   <= 0;
        end else begin
            
            // ===================================
            // STAGE 1: calculate top_val, bot_val
            // ===================================
            top_val <= v00 + ($signed({1'b0, dx})*(v01-v00) >>> 4);
            bot_val <= v10 + ($signed({1'b0, dx})*(v11-v10) >>> 4);

            dy_reg <= dy;
            valid_reg <= valid_in;
            

            // ===================================
            // STAGE 2: calculate result
            // ===================================
            result <= top_val + ($signed({1'b0, dy}) * (bot_val - top_val) >>> 4);
            valid_out <= valid_reg;
        end 

    end



endmodule