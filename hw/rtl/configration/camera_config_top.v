`timescale 1ns / 1ps

module camera_config_top (
    input  wire clk,     // 50MHz
    input  wire start,   // active LOW
    output wire done_led,

    // Camera L ports
    output wire pwdn_l,
    output wire cam_rst_n_l,
    output wire xclk_l,
    inout  wire siod_l,
    inout  wire sioc_l,

    // Camera R ports
    output wire pwdn_r,
    output wire cam_rst_n_r,
    output wire xclk_r,
    inout  wire siod_r,
    inout  wire sioc_r,


    // PS ports


    input  wire ps_scl_o_l,
    input  wire ps_scl_t_l,
    input  wire ps_sda_o_l,
    input  wire ps_sda_t_l,
    output wire ps_scl_i_l,
    output wire ps_sda_i_l,

    input  wire ps_scl_o_r,
    input  wire ps_scl_t_r,
    input  wire ps_sda_o_r,
    input  wire ps_sda_t_r,
    output wire ps_scl_i_r,
    output wire ps_sda_i_r
);

    // 24 MHz
    wire xclk;
    clk_wiz_0 u_clk(.clk_in1(clk), .clk_out1(xclk));

    assign xclk_l = xclk;
    assign xclk_r = xclk;


    reg [15:0] rst_cnt = 16'hFFFF;
    reg        rst_n;
    always @(posedge clk) begin
        if (rst_cnt != 16'd0)
            rst_cnt <= rst_cnt - 1'b1;
        rst_n <= (rst_cnt == 16'd0);
    end


    // --- I2C MUX ---

    wire scl_i, scl_o, scl_t;
    wire sda_i, sda_o, sda_t;

    wire scl_i_l, scl_o_l, scl_t_l;
    wire sda_i_l, sda_o_l, sda_t_l;

    wire scl_i_r, scl_o_r, scl_t_r;
    wire sda_i_r, sda_o_r, sda_t_r;

    IOBUF scl_l_iobuf (.I(scl_o_l), .IO(sioc_l), .O(scl_i_l), .T(scl_t_l));
    IOBUF sda_l_iobuf (.I(sda_o_l), .IO(siod_l), .O(sda_i_l), .T(sda_t_l));
    IOBUF scl_r_iobuf (.I(scl_o_r), .IO(sioc_r), .O(scl_i_r), .T(scl_t_r));
    IOBUF sda_r_iobuf (.I(sda_o_r), .IO(siod_r), .O(sda_i_r), .T(sda_t_r));

    reg cam_sel; // 0 - Camera L, 1 - Camera R

    assign scl_o_l = 1'b0;
    assign sda_o_l = 1'b0;
    assign scl_o_r = 1'b0;
    assign sda_o_r = 1'b0;

    assign scl_t_l = ( (cam_sel == 1'b0) ? scl_t : 1'b1 ) & ps_scl_t_l;
    assign sda_t_l = ( (cam_sel == 1'b0) ? sda_t : 1'b1 ) & ps_sda_t_l;
    assign scl_t_r = ( (cam_sel == 1'b1) ? scl_t : 1'b1 ) & ps_scl_t_r;
    assign sda_t_r = ( (cam_sel == 1'b1) ? sda_t : 1'b1 ) & ps_sda_t_r;

    assign scl_i = (cam_sel == 1'b0) ? scl_i_l : scl_i_r;
    assign sda_i = (cam_sel == 1'b0) ? sda_i_l : sda_i_r;
    
    assign ps_scl_i_l = scl_i_l; 
    assign ps_scl_i_r = scl_i_r;
    assign ps_sda_i_l = sda_i_l;
    assign ps_sda_i_r = sda_i_r;

    // --- Debounce for start button ---

    reg [1:0]  start_sync = 2'b11;
    reg [19:0] db_cnt     = 0;
    reg        start_db   = 1'b1;
    reg        start_db_d =1'b1;

    always @(posedge clk) begin
        start_sync <= {start_sync[0], start};
        start_db_d <= start_db;
        if (start_sync[1] == start_db_d) begin
            db_cnt <= 0;
        end else if (db_cnt == 20'd500_000) begin // 10ms
            db_cnt <= 0;
            start_db <= start_sync[1];
        end else begin
            db_cnt <= db_cnt + 1'b1;
        end
    end

    wire start_press = start_db_d & ~start_db;

    // --- Top State Machine ---

    localparam [2:0] S_WAIT_START = 3'd0;
    localparam [2:0] S_PWR_DELAY  = 3'd1;
    localparam [2:0] S_CONF_L     = 3'd2;
    localparam [2:0] S_WAIT_L     = 3'd3;
    localparam [2:0] S_CONF_R     = 3'd4;
    localparam [2:0] S_WAIT_R     = 3'd5;
    localparam [2:0] S_SYNC       = 3'd6;
    localparam [2:0] S_DONE       = 3'd7;

    reg[2:0] state = S_WAIT_START;
    reg[19:0] delay_timer;

    reg global_pwdn = 1'b1;
    reg global_rst_n = 1'b0;

    reg config_start_n = 1'b1;
    wire config_done;

    assign pwdn_l = global_pwdn;
    assign pwdn_r = global_pwdn;
    assign cam_rst_n_l = global_rst_n;
    assign cam_rst_n_r = global_rst_n;

    reg done_led_d;
    assign done_led = done_led_d;


    
    always @(posedge clk) begin
        if (!rst_n) begin
            delay_timer    <= 20'd500_000;
            state          <= S_PWR_DELAY;
            global_pwdn    <= 1'b0;
            global_rst_n   <= 1'b0;
            cam_sel        <= 1'b0;
            config_start_n <= 1'b1;
            done_led_d     <= 1'b0;
        end else begin
            case (state)

                S_WAIT_START: begin
                    if (start_press) begin
                        global_pwdn <= 1'b0;
                        delay_timer <= 20'd500_000;
                        state <= S_PWR_DELAY;
                    end
                end

                S_PWR_DELAY: begin
                    done_led_d <= 1'b0;
                    if (delay_timer > 0) begin                    
                        delay_timer <= delay_timer - 1'b1;
                    end else begin
                        global_rst_n <= 1'b1;
                        cam_sel <= 1'b0;
                        state <= S_CONF_L;
                    end

                end

                S_CONF_L: begin
                    config_start_n <= 1'b0;
                    state <= S_WAIT_L;
                end

                S_WAIT_L: begin
                    config_start_n <= 1'b1;
                    if (config_done) begin
                        cam_sel <= 1'b1;          
                        state <= S_CONF_R;
                    end
                end

                S_CONF_R: begin
                        config_start_n <= 1'b0;
                        state <= S_WAIT_R;
                end

                S_WAIT_R: begin
                        config_start_n <= 1'b1;
                    if (config_done) begin
                        global_pwdn <= 1'b1;
                        delay_timer <= 20'd500_000;
                        state <= S_SYNC;
                    end     
                end

                S_SYNC: begin
                    if (delay_timer > 0) begin                    
                        delay_timer <= delay_timer - 1'b1;
                    end else begin
                        global_pwdn <= 1'b0;
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done_led_d <= 1'b1;
                    state <= S_WAIT_START;
                end
                

            endcase
        end
    end


    // --- I2C Master ---

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


    // --- Configurator Inst ---

    ov7670_config config_inst (
        .clk                     (clk),
        .rst_n                   (rst_n),

        .start                   (config_start_n),
        .done                    (config_done),

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
        .i2c_missed_ack          (i2c_missed_ack)
    );

endmodule
