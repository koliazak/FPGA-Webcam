`timescale 1ns / 1ps



module sad_input #(
    parameter W = 640,
    parameter H = 480, 
    parameter WIN = 19, 
    parameter D = 64,
    parameter MIN_DISP = 22,
    parameter P = 4
)(
    input wire clk,
    input wire rst_n,

    // AXI Stream Slave left channel 
    input  wire [5:0] s_l_tdata,
    input  wire       s_l_tvalid,
    input  wire       s_l_tuser, // SOF - start of frame
    input  wire       s_l_tlast, // EOL - end of line
    output wire       s_l_tready,
    
    // AXI Stream Slave right channel 
    input  wire [5:0] s_r_tdata,
    input  wire       s_r_tvalid,
    input  wire       s_r_tuser, // SOF - start of frame
    input  wire       s_r_tlast, // EOL - end of line
    output wire       s_r_tready,

    // Master channel to SAD units 
    output reg  [5:0]            m_l_new,
    output wire [5:0]            m_l_old,
    output wire [D*6-1:0]        m_r_new_taps,  // [k*6 +: 6] = R(x - MIN_DISP - k)
    output wire [D*6-1:0]        m_r_old_taps,
    output reg  [$clog2(W)-1:0]  m_x,
    output reg  [$clog2(H)-1:0]  m_y,
    output reg  [$clog2(P)-1:0]  m_phase,
    output reg                   m_valid,

    output reg  [1:0]            err

);

    localparam U = D / P;
    
    reg [$clog2(W)-1:0] in_x;
    reg [$clog2(H)-1:0] in_y;

    wire in_sof_l = s_l_tvalid && s_l_tuser;
    wire in_sof_r = s_r_tvalid && s_r_tuser;
    wire in_eol_l = s_l_tvalid && s_l_tlast;
    wire in_eol_r = s_r_tvalid && s_r_tlast;

    wire can_accept = !m_valid || (m_phase == P-1);
    wire accept = can_accept && s_l_tvalid && s_r_tvalid;
    
    assign s_l_tready = accept; 
    assign s_r_tready = accept;
    

    wire [$clog2(W)-1:0] col = in_sof_l ? 0 : in_x;
    wire [$clog2(H)-1:0] row = in_sof_l ? 0 : in_y;

    always @(posedge clk) begin
        if (!rst_n) begin
            err <= 0;
        end else begin
            if (accept && ((s_l_tuser ^ s_r_tuser) || (s_l_tlast ^ s_r_tlast))) err[0] <= 1'b1;
            if (accept && in_eol_l && col != W-1)                               err[1] <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            m_valid <= 0;
            m_phase <= 0;
        end else if (accept) begin
            m_valid <= 1'b1;
            m_phase <= 1'b0;
        end else if (m_valid) begin
            if (m_phase == P-1) m_valid <= 0;
            m_phase <= m_phase + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            m_x  <= 0;
            m_y  <= 0;
            in_x <= 0;
            in_y <= 0;
        end else if (accept) begin
            m_x <= col;
            m_y <= row;

            if (in_eol_l || col == W-1) in_x <= 0;
            else                        in_x <= col+1'b1;

            in_y <= in_eol_l ? row + 1'b1 : row;    
        end
    end

    
    // === Line Buffers ===
    
    reg [$clog2(W*WIN)-1:0] addr;
    wire[$clog2(W*WIN)-1:0] a = in_sof_l ? 0 : addr;

    always @(posedge clk) begin
        if (!rst_n) begin
            addr <= 0;
        end else begin

            if (accept) addr <=  (a == W*WIN-1) ? 0 : a + 1'b1;
        end
    end


    wire[5:0] L_old;
    wire[5:0] R_old;

    reg[(MIN_DISP+D)*6-1:0] srn; // shift register new R
    reg[(MIN_DISP+D)*6-1:0] sro; // shift register old R
    

    assign m_l_old = L_old;
    assign m_r_old_taps = sro[(MIN_DISP-1)*6 +: D*6];    
    assign m_r_new_taps = srn[MIN_DISP*6 +: D*6];
    always @(posedge clk) begin
        if(accept) begin
            sro <= {sro[(MIN_DISP+D)*6-1-6:0], R_old};
            srn <= {srn[(MIN_DISP+D)*6-1-6:0], s_r_tdata};
            m_l_new <= s_l_tdata;
        end

    end


    ram #(
        .WIDTH(12),
        .DEPTH(W*WIN)
    ) inst_ram (
        .clk(clk),
        .en(accept),

        .addr(a),
        .din({s_r_tdata, s_l_tdata}),
        .dout({R_old, L_old})
    );



endmodule