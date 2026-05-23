`timescale 1ns / 1ps


module TOP(
    input  wire clk,
    input  wire start,
    
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] pixel_data,
    
    output wire       pwdn,
    output wire       cam_rst_n,
    
    output wire       xclk,
    inout  wire       siod,
    inout  wire       sioc,
    
    output wire done_led
    );

    
    camera_config_top u_conf (
        .clk(clk),
        .start(start),
        .done_led(done_led),
        .pwdn(pwdn),
        .cam_rst_n(cam_rst_n),
        .xclk(xclk),
        .siod(siod),
        .sioc(sioc)
    );
    
    wire aclk;
    wire m_axis_tvalid;
    wire [15:0] m_axis_tdata;
    wire m_axis_tlast;
    wire m_axis_tuser;
    
    ov7670_axi_stream_capture #(.WIDTH(640)) u_decode_stream
    (
        .pclk(pclk),
        .vsync(vsync),
        .href(href),
        .d(pixel_data),
        .m_axis_tready(1'b1),
    
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .aclk(aclk)
);
    
    ila_0 u_ila (
        .clk(clk),
        .probe0(pclk),
        .probe1(aclk),
        .probe2(vsync),
        .probe3(href),
        .probe4(m_axis_tvalid),
        .probe5(m_axis_tuser),
        .probe6(m_axis_tlast),
        .probe7(m_axis_tdata)
    );
    
endmodule
