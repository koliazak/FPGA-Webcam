`timescale 1ns / 1ps

// Converts AXI-Stream video stream (UG934: TUSER = SOF, TLAST = EOL)
// to video which can be fed to DDR via DMA, e.g generates TLAST at EOF
//
// - no backpressure: s_axis_tready = 1
// - if frame is corrupted, m_axis_tlast goes to 1 and DMA transaction  
//   closes earlier than expected
//

module axis_video_to_dma #(
    parameter H      = 480,
    parameter DATA_W = 8
)
(
    input wire clk,
    input wire rst_n,

    // Axi-Stream input
    input wire [DATA_W-1:0]  s_axis_tdata,
    input wire               s_axis_tvalid,
    input wire               s_axis_tuser,
    input wire               s_axis_tlast,
    output wire              s_axis_tready,

    // Axi-Stream output
    output reg [DATA_W-1:0]  m_axis_tdata,
    output reg               m_axis_tvalid,
    output reg               m_axis_tuser, // start of frame
    output reg               m_axis_tlast, // end of frame
    input  wire              m_axis_tready,

    // Sticky error flags (for ILA): [0] SOF in the middle of a frame,
    // [1] FIFO is full
    output reg[1:0]          err
);

    assign s_axis_tready = 1'b1;

    localparam S_WAIT_SOF = 1'd0;
    localparam S_PASS     = 2'd1;
    localparam S_SOF_PEND = 2'd3;
    
    reg [1:0]           state;
    reg [DATA_W-1:0]    sof_data_d;
    reg [$clog2(H)-1:0] line_idx;

    always @(posedge clk) begin
        if (!rst_n) begin
            m_axis_tvalid <= 0;
            m_axis_tuser  <= 0;
            m_axis_tlast  <= 0;
            m_axis_tdata  <= 0;
            state         <= S_WAIT_SOF;
            line_idx      <= 0;
            err           <= 0;
            sof_data_d    <= 0;
        end else begin
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tuser  <= s_axis_tuser;
            m_axis_tlast  <= s_axis_tlast && line_idx == H - 1;
            m_axis_tvalid <= s_axis_tvalid && (state == S_PASS || s_axis_tuser);

        
            if (m_axis_tvalid && !m_axis_tready) begin
                err[1] <= 1;
            end


            case (state)

                S_WAIT_SOF: begin
                    if (s_axis_tuser && s_axis_tvalid) begin 
                        state <= S_PASS;
                    end
                end 

                S_PASS: begin

                    // Unexpected SOF in the middle of a frame
                    if (s_axis_tuser && s_axis_tvalid) begin
                        err[0] <= 1;
                        sof_data_d <= s_axis_tdata; 
                        m_axis_tvalid <= 1;
                        m_axis_tlast  <= 1;
                        m_axis_tuser  <= 0;
                        m_axis_tdata  <= 0;
                        state <= S_SOF_PEND;
                    end
                    
                    // Normal EOF
                    else if (s_axis_tvalid && s_axis_tlast) begin
                        if (line_idx == H - 1) begin
                            state <= S_WAIT_SOF;
                        end else begin
                            line_idx <= line_idx + 1;                   
                        end
                    end
                end

                S_SOF_PEND: begin
                    m_axis_tdata <= sof_data_d;
                    m_axis_tlast <= 0;
                    m_axis_tuser <= 1;
                    m_axis_tvalid <= 1;
                    state <= S_PASS;
                end

            endcase

            if (s_axis_tuser && s_axis_tvalid) begin
                line_idx <= 0;
            end

        end
    end


endmodule