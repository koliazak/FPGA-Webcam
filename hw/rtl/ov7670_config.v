`timescale 1ns / 1ps

module ov7670_config (
    input wire clk,
    input wire rst_n,
    input wire start,          // active low (pulled-up btn)
    output reg done,


    output reg [6:0] s_axis_cmd_address,
    output reg       s_axis_cmd_start,
    output reg       s_axis_cmd_write,
    output reg       s_axis_cmd_write_multiple,
    output reg       s_axis_cmd_read,
    output reg       s_axis_cmd_stop,
    output reg       s_axis_cmd_valid,
    input  wire      s_axis_cmd_ready,


    output reg [7:0] s_axis_data_tdata,
    output reg       s_axis_data_tvalid,
    input  wire      s_axis_data_tready,
    output reg       s_axis_data_tlast,

    input wire i2c_busy,
    input wire i2c_missed_ack, // ignored for SCCB

    output reg pwdn,
    output reg cam_rst_n
);

    // -----------------------------------------------------------------
    // Configuration ROM
    //   High byte = OV7670 register address
    //   Low  byte = register value
    //   FFFF      = end of configuration
    //   FFF0      = delay marker
    // -----------------------------------------------------------------
    localparam ROM_DEPTH = 76;
    reg [15:0] rom [0:ROM_DEPTH-1];

    initial begin
        rom[0]  = 16'h1280;
        rom[1]  = 16'hFFF0;
        rom[2]  = 16'h1204;
        rom[3]  = 16'h1180;
        rom[4]  = 16'h0C00;
        rom[5]  = 16'h3E00;
        rom[6]  = 16'h0400;
        rom[7]  = 16'h40D0;
        rom[8]  = 16'h3A04;
        rom[9]  = 16'h1418;
        rom[10] = 16'h4FB3;
        rom[11] = 16'h50B3;
        rom[12] = 16'h5100;
        rom[13] = 16'h523D;
        rom[14] = 16'h53A7;
        rom[15] = 16'h54E4;
        rom[16] = 16'h589E;
        rom[17] = 16'h3DC0;
        rom[18] = 16'h1714;
        rom[19] = 16'h1802;
        rom[20] = 16'h3280;
        rom[21] = 16'h1903;
        rom[22] = 16'h1A7B;
        rom[23] = 16'h030A;
        rom[24] = 16'h0F41;
        rom[25] = 16'h1E00;
        rom[26] = 16'h330B;
        rom[27] = 16'h3C78;
        rom[28] = 16'h6900;
        rom[29] = 16'h7400;
        rom[30] = 16'hB084;
        rom[31] = 16'hB10C;
        rom[32] = 16'hB20E;
        rom[33] = 16'hB380;
        rom[34] = 16'h703A;
        rom[35] = 16'h7135;
        rom[36] = 16'h7211;
        rom[37] = 16'h73F0;
        rom[38] = 16'hA202;
        rom[39] = 16'h7A20;
        rom[40] = 16'h7B10;
        rom[41] = 16'h7C1E;
        rom[42] = 16'h7D35;
        rom[43] = 16'h7E5A;
        rom[44] = 16'h7F69;
        rom[45] = 16'h8076;
        rom[46] = 16'h8180;
        rom[47] = 16'h8288;
        rom[48] = 16'h838F;
        rom[49] = 16'h8496;
        rom[50] = 16'h85A3;
        rom[51] = 16'h86AF;
        rom[52] = 16'h87C4;
        rom[53] = 16'h88D7;
        rom[54] = 16'h89E8;
        rom[55] = 16'h13E0;
        rom[56] = 16'h0000;
        rom[57] = 16'h1000;
        rom[58] = 16'h0D40;
        rom[59] = 16'h1418;
        rom[60] = 16'hA505;
        rom[61] = 16'hAB07;
        rom[62] = 16'h2495;
        rom[63] = 16'h2533;
        rom[64] = 16'h26E3;
        rom[65] = 16'h9F78;
        rom[66] = 16'hA068;
        rom[67] = 16'hA103;
        rom[68] = 16'hA6D8;
        rom[69] = 16'hA7D8;
        rom[70] = 16'hA8F0;
        rom[71] = 16'hA990;
        rom[72] = 16'hAA94;
        rom[73] = 16'h13E5;
        rom[74] = 16'hFFFF;
    end


    reg [19:0] timer;

    localparam [3:0]
        ST_IDLE           = 4'd0,
        ST_PWRDN_RELEASE  = 4'd1,
        ST_RESET_WAIT     = 4'd2,
        ST_POST_RESET     = 4'd3,
        ST_READ_ROM       = 4'd4,
        ST_CHECK_ENTRY    = 4'd5,
        ST_DELAY          = 4'd6,
        ST_SEND_CMD       = 4'd7,
        ST_SEND_DATA0     = 4'd8,
        ST_SEND_DATA1     = 4'd9,
        ST_WAIT_I2C       = 4'd10,
        ST_DONE           = 4'd11;

    reg [3:0] state;
    reg [6:0] rom_addr;
    reg [15:0] rom_data;
    reg [7:0] reg_addr;
    reg [7:0] reg_val;
    reg       start_d;      // for edge detect

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= ST_IDLE;
            done   <= 1'b0;
            pwdn   <= 1'b1;      // power-down active high
            cam_rst_n <= 1'b0;   // reset active low

            rom_addr  <= 7'd0;
            rom_data  <= 16'd0;
            reg_addr  <= 8'd0;
            reg_val   <= 8'd0;
            timer     <= 20'd0;
            start_d   <= 1'b1;

            s_axis_cmd_address      <= 7'd0;
            s_axis_cmd_start        <= 1'b0;
            s_axis_cmd_write        <= 1'b0;
            s_axis_cmd_write_multiple <= 1'b0;
            s_axis_cmd_read         <= 1'b0;
            s_axis_cmd_stop         <= 1'b0;
            s_axis_cmd_valid        <= 1'b0;

            s_axis_data_tdata  <= 8'd0;
            s_axis_data_tvalid <= 1'b0;
            s_axis_data_tlast  <= 1'b0;
        end else begin
        
            s_axis_cmd_valid   <= 1'b0;
            s_axis_data_tvalid <= 1'b0;
            s_axis_data_tlast  <= 1'b0;

            start_d <= start;

            if (timer != 20'd0)
                timer <= timer - 1'b1;

            case (state)
            
                ST_IDLE: begin
                    done      <= 1'b0;
                    pwdn      <= 1'b1;
                    cam_rst_n <= 1'b0;
                    rom_addr  <= 7'd0;
                    if (!start) begin
                        state <= ST_PWRDN_RELEASE;
                        timer <= 20'd500_000;   // 10 ms for 50 MHz clock
                    end
                end

                ST_PWRDN_RELEASE: begin
                    pwdn      <= 1'b0;
                    cam_rst_n <= 1'b0;
                    if (timer == 20'd0) begin
                        state <= ST_RESET_WAIT;
                        timer <= 20'd500_000;   // 10 ms
                    end
                end

                ST_RESET_WAIT: begin
                    pwdn      <= 1'b0;
                    cam_rst_n <= 1'b0;
                    if (timer == 20'd0) begin
                        state <= ST_POST_RESET;
                        timer <= 20'd500_000;   // 10 ms
                    end
                end


                ST_POST_RESET: begin
                    pwdn      <= 1'b0;
                    cam_rst_n <= 1'b1;
                    if (timer == 20'd0) begin
                        state <= ST_READ_ROM;
                    end
                end

                ST_READ_ROM: begin
                    rom_data <= rom[rom_addr];
                    state    <= ST_CHECK_ENTRY;
                end

                ST_CHECK_ENTRY: begin
                    if (rom_data == 16'hFFFF) begin
                        state <= ST_DONE;
                    end else if (rom_data == 16'hFFF0) begin
                        state <= ST_DELAY;
                        timer <= 20'd500_000;   // 10 ms delay marker
                        rom_addr <= rom_addr + 1'b1;
                    end else begin
                        reg_addr <= rom_data[15:8];
                        reg_val  <= rom_data[7:0];
                        state    <= ST_SEND_CMD;
                    end
                end

                ST_DELAY: begin
                    if (timer == 20'd0) begin
                        state <= ST_READ_ROM;
                    end
                end

                ST_SEND_CMD: begin
                    s_axis_cmd_address        <= 7'h21;
                    s_axis_cmd_write_multiple <= 1'b1;
                    s_axis_cmd_start          <= 1'b1;
                    s_axis_cmd_stop           <= 1'b1;
                    s_axis_cmd_valid          <= 1'b1;
                    if (s_axis_cmd_ready) begin
                        state <= ST_SEND_DATA0;
                    end
                end


                // Send register address (1st data byte)
                ST_SEND_DATA0: begin
                    s_axis_data_tdata  <= reg_addr;
                    s_axis_data_tvalid <= 1'b1;
                    s_axis_data_tlast  <= 1'b0;
                    if (s_axis_data_tready) begin
                        state <= ST_SEND_DATA1;
                    end
                end

                // Send register value (2nd data byte, tlast = 1 -> STOP)
                ST_SEND_DATA1: begin
                    s_axis_data_tdata  <= reg_val;
                    s_axis_data_tvalid <= 1'b1;
                    s_axis_data_tlast  <= 1'b1;
                    if (s_axis_data_tready) begin
                        state <= ST_WAIT_I2C;
                    end
                end

                ST_WAIT_I2C: begin
                    if (!i2c_busy) begin
                        rom_addr <= rom_addr + 1'b1;
                        state    <= ST_READ_ROM;
                    end
                end


                // All registers written
                ST_DONE: begin
                    done <= 1'b1;
                    if (!start && start_d) begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
