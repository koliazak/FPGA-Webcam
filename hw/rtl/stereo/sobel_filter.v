`timescale 1ns/1ps

// 3x3 Sobel on an AXI-Stream video stream (UG934: TUSER = SOF, TLAST = EOL).
//
// No backpressure: every input pixel is accepted and produces exactly one
// output pixel; put a FIFO after this module. m_axis_tready is only used for
// the overflow flag.

module sobel_filter
#(
    parameter W   = 640,
    parameter H   = 480,
    parameter DIR = "X" // X | Y
)(
    input wire        clk,
    input wire        rst_n,

    // Axi-Stream Grayscale input
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    input  wire       s_axis_tuser, // start of frame
    input  wire       s_axis_tlast, // end of line
    output wire       s_axis_tready,

    // Output Axi-Stream: 6-bit unsigned, CAP (31) = zero gradient
    output reg [5:0]  m_axis_tdata,
    output reg        m_axis_tvalid,
    output reg        m_axis_tuser, // start of frame
    output reg        m_axis_tlast, // end of line
    input  wire       m_axis_tready,

    // Sticky error flags (for ILA): [0] TLAST at wrong column,
    // [1] input pixel during flush, [2] output overflow (FIFO full)
    output reg [2:0]  err
);

    localparam AW  = $clog2(W);
    localparam HW  = $clog2(H);
    localparam LAT = W + 5;          // steps from input pixel to output register
    localparam CW  = $clog2(LAT + 1);
    localparam signed [10:0] CAP = 31;   // OpenCV preFilterCap


    reg flushing;
    assign s_axis_tready = 1'b1;

    wire in_sof  = s_axis_tvalid && s_axis_tuser;
    wire in_eol  = s_axis_tvalid && s_axis_tlast;
    wire pipe_en = s_axis_tvalid || flushing;

    // ---------------------------------------------------------------
    // Input side counters
    // ---------------------------------------------------------------
    reg [AW-1:0] addr;       // input column counter
    reg [HW-1:0] in_y;       // input row
    // Line buffer address: the SOF pixel always goes to column 0 (resync)
    wire [AW-1:0] col = in_sof ? {AW{1'b0}} : addr;
    wire in_last = in_eol && (in_y == H-1);   // last pixel of the frame

    always @(posedge clk) begin
        if (!rst_n) begin
            addr <= 0;
            in_y <= 0;
        end else begin
            if (pipe_en) begin
                if (in_eol || col == W-1) addr <= 0;
                else                      addr <= col + 1'b1;
            end

            if (in_sof)      in_y <= 0;
            else if (in_eol) in_y <= in_y + 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Line buffers
    // ---------------------------------------------------------------
    wire [7:0] line0 = s_axis_tdata; // pixel from current line
    wire [7:0] line1;
    wire [7:0] line2;

    reg [7:0] line0_d1, line0_d2;
    reg [7:0] line1_d1;

    always @(posedge clk) begin
        if (!rst_n) begin
            line0_d1 <= 0;
            line0_d2 <= 0;
            line1_d1 <= 0;
        end else if (pipe_en) begin
            line0_d1 <= line0;
            line0_d2 <= line0_d1;

            line1_d1 <= line1;
        end
    end

    ram #(
        .WIDTH(8), .DEPTH(W)
    ) lb1 (
        .clk(clk), .en(pipe_en), .addr(col), .din(line0), .dout(line1)
    );

    ram #(
        .WIDTH(8), .DEPTH(W)
    ) lb2 (
        .clk(clk), .en(pipe_en), .addr(col), .din(line1), .dout(line2)
    );

    // --- 3x3 Window Registers ---
    // p_Y_X, Y - row, X - column
    reg [7:0] p2_2, p2_1, p2_0;
    reg [7:0] p1_2, p1_1, p1_0;
    reg [7:0] p0_2, p0_1, p0_0;

    always @(posedge clk) begin
        if (!rst_n) begin
            p0_0 <= 0; p0_1 <= 0; p0_2 <= 0;
            p1_0 <= 0; p1_1 <= 0; p1_2 <= 0;
            p2_0 <= 0; p2_1 <= 0; p2_2 <= 0;
        end else if (pipe_en) begin
            p0_2 <= p0_1; p0_1 <= p0_0; p0_0 <= line0_d2;
            p1_2 <= p1_1; p1_1 <= p1_0; p1_0 <= line1_d1;
            p2_2 <= p2_1; p2_1 <= p2_0; p2_0 <= line2;
        end
    end

    reg          synced;     // a SOF has been seen in this frame
    reg [CW-1:0] step_cnt;   // steps since SOF, saturates at LAT
    reg [AW-1:0] out_x;      // column of the next output pixel
    reg [HW-1:0] out_y;      // row of the next output pixel

    // -- Sobel Math ---
    // Rows of the window: top = p2_*, mid = p1_*, bot = p0_*.
    // Column 0 (p*_0) is the newest = rightmost pixel, column 2 the leftmost.
    // Reflect-101 at the frame top/bottom: the missing row is replaced by the
    // opposite one. 
    wire top_row = (out_y == 0);
    wire bot_row = (out_y == H-1);

    wire [7:0] t0 = top_row ? p0_0 : p2_0;
    wire [7:0] t1 = top_row ? p0_1 : p2_1;
    wire [7:0] t2 = top_row ? p0_2 : p2_2;
    wire [7:0] b0 = bot_row ? p2_0 : p0_0;
    wire [7:0] b1 = bot_row ? p2_1 : p0_1;
    wire [7:0] b2 = bot_row ? p2_2 : p0_2;

    reg signed [10:0] diff;

    always @(posedge clk) begin
        if (!rst_n) begin
            diff <= 0;
        end else if (pipe_en) begin
            if (DIR == "X") begin
                // right - left
                diff <= (t0 + (p1_0 << 1) + b0) - (t2 + (p1_2 << 1) + b2);
            end else begin
                // bottom - top
                diff <= (b0 + (b1 << 1) + b2) - (t0 + (t1 << 1) + t2);
            end
        end
    end

    // clip(diff, -CAP, CAP) + CAP
    reg [5:0] diff_q;
    always @(*) begin
        if (diff > CAP)        diff_q = 2*CAP;
        else if (diff < -CAP)  diff_q = 0;
        else                   diff_q = diff + CAP;
    end

    // ---------------------------------------------------------------
    // Frame control
    // ---------------------------------------------------------------

    // The output loaded at this step is a real pixel
    wire primed   = synced && !in_sof && (step_cnt == LAT);
    wire emit     = pipe_en && primed;
    wire out_last = (out_x == W-1) && (out_y == H-1);

    
    wire border_col = (out_x == 0) || (out_x == W-1);
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axis_tdata <= 0;
        end else if (pipe_en) begin
            m_axis_tdata <= border_col ? CAP[5:0] : diff_q;
        end
    end
    
    always @(posedge clk) begin
        if (!rst_n) begin
            synced        <= 0;
            step_cnt      <= 0;
            flushing      <= 0;
            out_x         <= 0;
            out_y         <= 0;
            m_axis_tvalid <= 0;
            m_axis_tuser  <= 0;
            m_axis_tlast  <= 0;
            err           <= 0;
        end else begin
            m_axis_tvalid <= emit;

            if (in_sof) begin
                // (Re)start of frame: everything restarts from pixel 0
                synced   <= 1;
                step_cnt <= 1;
                flushing <= 0;
                out_x    <= 0;
                out_y    <= 0;
            end else begin
                if (pipe_en && step_cnt != LAT)
                    step_cnt <= step_cnt + 1'b1;

                if (in_last)
                    flushing <= 1;

                if (emit) begin
                    m_axis_tuser <= (out_x == 0) && (out_y == 0);
                    m_axis_tlast <= (out_x == W-1);

                    if (out_x == W-1) begin
                        out_x <= 0;
                        out_y <= out_y + 1'b1;
                    end else begin
                        out_x <= out_x + 1'b1;
                    end

                    if (out_last) begin
                        flushing <= 0;
                        synced   <= 0;
                        out_y    <= 0;
                    end
                end
            end

            // Sticky errors
            if (in_eol && col != W-1)            err[0] <= 1'b1;
            if (s_axis_tvalid && flushing)       err[1] <= 1'b1;
            if (m_axis_tvalid && !m_axis_tready) err[2] <= 1'b1;
        end
    end

endmodule
