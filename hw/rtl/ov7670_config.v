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
    localparam ROM_DEPTH = 80;
    reg [15:0] rom [0:ROM_DEPTH-1];

    initial begin
        rom[0]  = 16'h1280; // COM7: reset all registers
        rom[1]  = 16'hFFF0; // delay

        // 640x480 VGA, YUV 4:2:2
        rom[2]  = 16'h1200; // COM7: YUV (COM7[2]=0, COM7[0]=0), VGA
        rom[3]  = 16'h1180; // CLKRC: use external XCLK directly
        rom[4]  = 16'h1300; // COM8: AEC/AGC/AWB/banding filter off
        rom[5]  = 16'h0C00; // COM3: scaling and DCW disabled
        rom[6]  = 16'h0D00; // COM4: full-window average
        rom[7]  = 16'h3E00; // COM14: normal PCLK, manual scaling disabled
        rom[8]  = 16'h4200; // COM17: full window

        // Fixed 4:2:2 byte order and output range: YUYV, full 0..255.
        rom[9]  = 16'h3B00; // COM11: night mode and 50/60 Hz auto detect off
        rom[10] = 16'h3A00; // TSLB: normal UV, YUYV, auto output window off
        rom[11] = 16'h3D80; // COM13: fixed gamma on, UV auto-adjust off
        rom[12] = 16'h40C0; // COM15: full-range output; RGB fields unused
        rom[13] = 16'h4108; // COM16: auto edge/de-noise off, AWB gain path on

        // Manual exposure code 0x0100:
        // {AECHH[5:0], AECH[7:0], COM1[1:0]} = 0x0100.
        rom[14] = 16'h0400; // COM1: AEC[1:0]=0, CCIR656 disabled
        rom[15] = 16'h0700; // AECHH: AEC[15:10]=0
        rom[16] = 16'h1040; // AECH: AEC[9:2]=0x40

        // Fixed gain and fixed white balance.
        rom[17] = 16'h0000; // GAIN[7:0]=0 (minimum manual analog gain)
        rom[18] = 16'h0300; // VREF: AGC[9:8]=0; VGA vertical LSBs=0
        rom[19] = 16'h0180; // BLUE: fixed blue AWB gain
        rom[20] = 16'h0280; // RED: fixed red AWB gain
        rom[21] = 16'h6A00; // GGAIN: fixed green AWB gain
        rom[22] = 16'h6900; // GFIX: Gr/Gb/R/B fixed at 1x
        rom[23] = 16'h7400; // REG74: digital gain bypass

        // 640x480 active window and deterministic timing.
        rom[24] = 16'h1E00; // MVFP: mirror, vflip, black-sun off
        rom[25] = 16'h1500; // COM10: normal PCLK/HREF/VSYNC polarities
        rom[26] = 16'h1711; // HSTART: VGA default
        rom[27] = 16'h1861; // HSTOP: VGA default
        rom[28] = 16'h3280; // HREF: VGA default LSBs/edge offset
        rom[29] = 16'h1903; // VSTRT: VGA default
        rom[30] = 16'h1A7B; // VSTOP: VGA default
        rom[31] = 16'h1B00; // PSHFT: no pixel-data delay
        rom[32] = 16'h2A00; // EXHCH: no dummy pixels / HSYNC delay
        rom[33] = 16'h2B00; // EXHCL: no dummy pixels
        rom[34] = 16'h2D00; // ADVFL: no inserted dummy lines
        rom[35] = 16'h2E00; // ADVFH: no inserted dummy lines
        rom[36] = 16'h9200; // DM_LNL: no dummy lines
        rom[37] = 16'h9300; // DM_LNH: no dummy lines

        // Disable automatic/adaptive image functions.
        rom[38] = 16'h6600; // LCC5: lens correction disabled
        rom[39] = 16'h3F00; // EDGE: fixed edge enhancement factor 0
        rom[40] = 16'h4C00; // DNSTH: fixed de-noise strength 0
        rom[41] = 16'h4B00; // REG4B: UV average disabled
        rom[42] = 16'h7600; // REG76: black/white pixel correction off
//        rom[43] = 16'hB100; // ABLC1: automatic black-level calibration off
//        rom[44] = 16'hBE00; // AD-CHB: blue black-level compensation 0
//        rom[45] = 16'hBF00; // AD-CHR: red black-level compensation 0
//        rom[46] = 16'hC000; // AD-CHGb: Gb black-level compensation 0
//        rom[47] = 16'hC100; // AD-CHGr: Gr black-level compensation 0

        // Fixed image-processing controls (datasheet defaults).
        rom[48] = 16'h5500; // BRIGHT
        rom[49] = 16'h5640; // CONTRAS
        rom[50] = 16'h5780; // CONTRAS_CENTER
        rom[51] = 16'h4F40; // MTX1
        rom[52] = 16'h5034; // MTX2
        rom[53] = 16'h510C; // MTX3
        rom[54] = 16'h5217; // MTX4
        rom[55] = 16'h5329; // MTX5
        rom[56] = 16'h5440; // MTX6
        rom[57] = 16'h581E; // MTXS: auto contrast center off
        rom[58] = 16'hC9C0; // SATCTR: fixed saturation value
        rom[59] = 16'hA400; // NT_CTRL: fixed frame-rate behavior
        rom[60] = 16'h8C00; // RGB444 disabled (not used in YUV mode)

        // Fixed gamma curve (datasheet defaults; enabled by COM13[7]).
        rom[61] = 16'h7A24; // SLOP
        rom[62] = 16'h7B04; // GAM1
        rom[63] = 16'h7C07; // GAM2
        rom[64] = 16'h7D10; // GAM3
        rom[65] = 16'h7E28; // GAM4
        rom[66] = 16'h7F36; // GAM5
        rom[67] = 16'h8044; // GAM6
        rom[68] = 16'h8152; // GAM7
        rom[69] = 16'h8260; // GAM8
        rom[70] = 16'h836C; // GAM9
        rom[71] = 16'h8478; // GAM10
        rom[72] = 16'h858C; // GAM11
        rom[73] = 16'h869E; // GAM12
        rom[74] = 16'h87BB; // GAM13
        rom[75] = 16'h88D2; // GAM14
        rom[76] = 16'h89E5; // GAM15

        // Freeze AGC/AEC after all manual exposure/gain fields are written.
        rom[77] = 16'h1401; // COM9: freeze AGC/AEC, 2x automatic ceiling
        rom[78] = 16'h1300; // COM8: AEC/AGC/AWB/banding filter remain off
        rom[79] = 16'hFFFF;
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
                    if (!start | !done) begin
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
