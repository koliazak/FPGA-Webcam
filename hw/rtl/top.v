module top
(
    input  wire       clk,
    input  wire       start,
    
    output wire       sioc,
    output wire       siod,
    
    input  wire [7:0] p_data,
    
    input  wire       p_clock,
    output wire       x_clock,
    input  wire       vsync,
    input  wire       href,
    output wire       pwdn,
    output wire       ret,
    
    output wire       done_led
);
    
    assign ret  = 1;
    assign pwdn = 0;
    
    wire clk25;
    clk_wiz_0 u_clk25 (.clk_in1(clk), .clk_out1(clk25));
    
    localparam CLK_FREQ     = 25_000_000;
    localparam ROM_DEPTH    = 128;
    localparam SAMPLE_WIDTH = 16;
    
    wire [$clog2(ROM_DEPTH)-1:0] rom_addr;
    wire [SAMPLE_WIDTH-1:0] rom_dout;

    wire [7:0] SCCB_addr;
    wire [7:0] SCCB_data;
    wire       SCCB_start;
    wire       SCCB_ready;
    wire       SCCB_SIOC_oe;
    wire       SCCB_SIOD_oe;
    
    assign sioc = SCCB_SIOC_oe ? 1'b0 : 1'bZ;
    assign siod = SCCB_SIOD_oe ? 1'b0 : 1'bZ;
    
    rom u_OV7670_config_rom (
        .clk(clk25),
        .addr(rom_addr),
        .data_out(rom_dout)
        );
        
    OV7670_config #(.CLK_FREQ(CLK_FREQ)) u_OV7670_config(
        .clk(clk25),
        .SCCB_interface_ready(SCCB_ready),
        .rom_data(rom_dout),
        .start(~start),
        .rom_addr(rom_addr),
        .done(done_led),
        .SCCB_interface_addr(SCCB_addr),
        .SCCB_interface_data(SCCB_data),
        .SCCB_interface_start(SCCB_start)
        );
    
    SCCB_interface #( .CLK_FREQ(CLK_FREQ)) u_SCCB(
        .clk(clk25),
        .start(SCCB_start),
        .address(SCCB_addr),
        .data(SCCB_data),
        .ready(SCCB_ready),
        .SIOC_oe(SCCB_SIOC_oe),
        .SIOD_oe(SCCB_SIOD_oe)
        );
        
//    camera_read u_camera_read(
//	.p_clock(p_clock),
//	.vsync(vsync),
//	.href(href),
//	.p_data(p_data),
//	.pixel_data(),
//	.pixel_valid(),
//	.frame_done()
//    );
    
endmodule