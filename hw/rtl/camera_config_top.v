`timescale 1ns / 1ps

module camera_config_top (
    input  wire clk,     // 50MHz
    input  wire start,   // pulled-up
    output wire done_led,
    output wire pwdn,
    output wire cam_rst_n,
    output wire xclk,
    inout  wire siod,
    inout  wire sioc
);

    // 24 MHz
    clk_wiz_0 u_clk(.clk_in1(clk), .clk_out1(xclk));


    reg [15:0] rst_cnt = 16'hFFFF;
    reg        rst_n;
    always @(posedge clk) begin
        if (rst_cnt != 16'd0)
            rst_cnt <= rst_cnt - 1'b1;
        rst_n <= (rst_cnt == 16'd0);
    end


    wire scl_i, scl_o, scl_t;
    wire sda_i, sda_o, sda_t;

    IOBUF scl_iobuf (
        .I (scl_o),
        .IO(sioc),
        .O (scl_i),
        .T (scl_t)
    );

    IOBUF sda_iobuf (
        .I (sda_o),
        .IO(siod),
        .O (sda_i),
        .T (sda_t)
    );


    wire [6:0] s_axis_cmd_address;
    wire       s_axis_cmd_start;
    wire       s_axis_cmd_write;
    wire       s_axis_cmd_write_multiple;
    wire       s_axis_cmd_read;
    wire       s_axis_cmd_stop;
    wire       s_axis_cmd_valid;
    wire       s_axis_cmd_ready;

    wire [7:0] s_axis_data_tdata;
    wire       s_axis_data_tvalid;
    wire       s_axis_data_tready;
    wire       s_axis_data_tlast;

    wire       i2c_busy;
    wire       i2c_missed_ack;


    // Prescale = Fclk / (F_i2c * 4) = 50 000 000 / (100 000 * 4) = 125
    i2c_master i2c_inst (
        .clk(clk),
        .rst(!rst_n),

        .s_axis_cmd_address      (s_axis_cmd_address),
        .s_axis_cmd_start        (s_axis_cmd_start),
        .s_axis_cmd_read         (s_axis_cmd_read),
        .s_axis_cmd_write        (s_axis_cmd_write),
        .s_axis_cmd_write_multiple (s_axis_cmd_write_multiple),
        .s_axis_cmd_stop         (s_axis_cmd_stop),
        .s_axis_cmd_valid        (s_axis_cmd_valid),
        .s_axis_cmd_ready        (s_axis_cmd_ready),

        .s_axis_data_tdata       (s_axis_data_tdata),
        .s_axis_data_tvalid      (s_axis_data_tvalid),
        .s_axis_data_tready      (s_axis_data_tready),
        .s_axis_data_tlast       (s_axis_data_tlast),

        .m_axis_data_tdata       (),
        .m_axis_data_tvalid      (),
        .m_axis_data_tready      (1'b1),
        .m_axis_data_tlast       (),

        .scl_i                   (scl_i),
        .scl_o                   (scl_o),
        .scl_t                   (scl_t),
        .sda_i                   (sda_i),
        .sda_o                   (sda_o),
        .sda_t                   (sda_t),

        .busy                    (i2c_busy),
        .bus_control             (),
        .bus_active              (),
        .missed_ack              (i2c_missed_ack),

        .prescale                (16'd125),
        .stop_on_idle            (1'b0)
    );


    ov7670_config config_inst (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .start                   (start),
        .done                    (done_led),

        .s_axis_cmd_address      (s_axis_cmd_address),
        .s_axis_cmd_start        (s_axis_cmd_start),
        .s_axis_cmd_write        (s_axis_cmd_write),
        .s_axis_cmd_write_multiple (s_axis_cmd_write_multiple),
        .s_axis_cmd_read         (s_axis_cmd_read),
        .s_axis_cmd_stop         (s_axis_cmd_stop),
        .s_axis_cmd_valid        (s_axis_cmd_valid),
        .s_axis_cmd_ready        (s_axis_cmd_ready),

        .s_axis_data_tdata       (s_axis_data_tdata),
        .s_axis_data_tvalid      (s_axis_data_tvalid),
        .s_axis_data_tready      (s_axis_data_tready),
        .s_axis_data_tlast       (s_axis_data_tlast),

        .i2c_busy                (i2c_busy),
        .i2c_missed_ack          (i2c_missed_ack),

        .pwdn                    (pwdn),
        .cam_rst_n               (cam_rst_n)
    );

endmodule
