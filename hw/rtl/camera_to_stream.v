module ov7670_axi_stream_capture #(
    parameter WIDTH = 640
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

    reg  [15:0] d_latch         = 16'b0;
    reg  [18:0] address         = 19'b0;
    reg  [1:0]  line            = 2'b0;
    reg  [6:0]  href_last       = 7'b0;
    reg         we_reg          = 1'b0;
    reg         href_hold       = 1'b0;
    reg         latched_vsync   = 1'b0;
    reg         latched_href    = 1'b0;
    reg  [7:0]  latched_d       = 8'b0;
    reg         sof             = 1'b0;
    reg         eol             = 1'b0;

    reg        tvalid_reg = 1'b0;
    reg [15:0] tdata_reg  = 16'b0;
    reg        tlast_reg  = 1'b0;
    reg        tuser_reg  = 1'b0;

    assign m_axis_tvalid = tvalid_reg;
    assign m_axis_tdata  = tdata_reg;
    assign m_axis_tlast  = tlast_reg;
    assign m_axis_tuser  = tuser_reg;

    assign aclk          = ~pclk;

    always @(posedge pclk) begin
        if (we_reg) begin
            if (m_axis_tready || !tvalid_reg) begin
                tvalid_reg <= 1'b1;
                tdata_reg  <= d_latch;
                tlast_reg  <= eol;
                tuser_reg  <= sof;
                address    <= address + 1;
            end
        end else if (m_axis_tready) begin
            tvalid_reg <= 1'b0;
        end

        if (href_hold == 1'b0 && latched_href == 1'b1) begin
            case (line)
                2'b00: line <= 2'b01;
                2'b01: line <= 2'b10;
                2'b10: line <= 2'b11;
                default: line <= 2'b00;
            endcase
        end
        href_hold <= latched_href;

        if (latched_href) begin
            d_latch <= {d_latch[7:0], latched_d};
        end
        we_reg <= 1'b0;

        if (latched_vsync) begin
            address    <= 19'b0;
            href_last  <= 7'b0;
            line       <= 2'b0;
        end else begin
            if (href_last[0]) begin
                we_reg <= 1'b1;
                href_last <= 7'b0;
            end else begin
                href_last <= {href_last[5:0], latched_href};
            end
        end

        if ((address % WIDTH) == (WIDTH - 1)) begin
            eol <= 1'b1;
        end else begin
            eol <= 1'b0;
        end

        if (address == 0) begin
            sof <= 1'b1;
        end else begin
            sof <= 1'b0;
        end
    end

    always @(negedge pclk) begin
        latched_d     <= d;
        latched_href  <= href;
        latched_vsync <= vsync;
    end

endmodule
