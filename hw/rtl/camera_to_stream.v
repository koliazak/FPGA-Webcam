`timescale 1ns / 1ps

module ov7670_axi_stream_capture #(
    parameter WIDTH = 640,
    parameter HEIGHT = 480
)(
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,
    input  wire        m_axis_tready,

    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    output wire        m_axis_tuser,
    output wire [15:0] m_axis_tdata,
    output wire        aclk
);

    assign aclk = ~pclk;
    reg        latched_vsync = 0;
    reg        latched_href  = 0;
    reg [7:0]  latched_d     = 0;

    // Capture signals on falling edge of pclk due to ov7670 datasheet
    always @(negedge pclk) begin
        latched_vsync <= vsync;
        latched_href  <= href;
        latched_d     <= d;
    end


    reg [7:0]  byte1 = 0;
    reg        byte_idx = 0;
    reg        pixel_ready = 0;
    reg [15:0] pixel_data = 0;

    always @(posedge pclk) begin
        pixel_ready <= 1'b0;
        if (latched_vsync) begin
            byte_idx <= 0;
        end else if (latched_href) begin
            if (byte_idx == 0) begin
                byte1 <= latched_d;
                byte_idx <= 1'b1;
            end else begin
                pixel_data <= {byte1, latched_d};
                pixel_ready <= 1'b1;
                byte_idx <= 1'b0;
            end
        end else begin
            byte_idx <= 0;
        end
    end


    // FSM
    localparam ST_WAIT_VSYNC = 2'd0;
    localparam ST_CAPTURE    = 2'd1;
    localparam ST_ABORT      = 2'd2;

    reg [1:0]  state = ST_WAIT_VSYNC;
    reg [18:0] pixel_cnt = 0;
    reg        early_tlast_sent = 0;

    reg        tvalid_reg = 0;
    reg [15:0] tdata_reg  = 0;
    reg        tlast_reg  = 0;
    reg        tuser_reg  = 0;

    assign m_axis_tvalid = tvalid_reg;
    assign m_axis_tdata  = tdata_reg;
    assign m_axis_tlast  = tlast_reg;
    assign m_axis_tuser  = tuser_reg;

    always @(posedge pclk) begin
        if (tvalid_reg && m_axis_tready) begin
            tvalid_reg <= 1'b0;
            tlast_reg  <= 1'b0;
            tuser_reg  <= 1'b0;
        end

        if (latched_vsync) begin
            if (m_axis_tready) begin
                state <= ST_CAPTURE;
            end else begin
                state <= ST_WAIT_VSYNC;
            end
            pixel_cnt <= 0;
            early_tlast_sent <= 0;
            tvalid_reg <= 1'b0;
            tlast_reg  <= 1'b0;
        end else begin
            case (state)
                ST_CAPTURE: begin
                    if (pixel_ready) begin
                        // Handling FIFO overflow
                        if (tvalid_reg && !m_axis_tready) begin
			// Abort frame if FIFO is overflowed
                            state <= ST_ABORT;
                        end else begin
                            tdata_reg  <= pixel_data;
                            tvalid_reg <= 1'b1;
                            tuser_reg  <= (pixel_cnt == 0); // SOF on the first pixel
                            tlast_reg  <= (pixel_cnt == (WIDTH * HEIGHT) - 1); // EOF on the last pixel
                            pixel_cnt  <= pixel_cnt + 1;
                        end
                    end
                end

                ST_ABORT: begin
                    // "fake" TLAST, so DMA sends interrupt
                    // and this error is detected in software
                    if (!early_tlast_sent && !tvalid_reg) begin
                        tdata_reg  <= 16'h0000;
                        tvalid_reg <= 1'b1;
                        tlast_reg  <= 1'b1;
                        early_tlast_sent <= 1'b1;
                    end
                end

                ST_WAIT_VSYNC: begin
                    // just ignore pixels while waiting for vsync
                end
            endcase
        end
    end

endmodule
