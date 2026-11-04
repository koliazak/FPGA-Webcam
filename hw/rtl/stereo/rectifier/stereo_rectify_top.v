`timescale 1ns / 1ps 

module stereo_rectify_top(
    input wire clk,
    input wire rst_n,

    input wire [9:0] s_axis_u,
    input wire [8:0] s_axis_v,
    input wire       s_axis_tvalid,


    output wire [35:0] m_axis_tdata,  // 35:18 - Y, 17:0 - X
    output wire        m_axis_tvalid

);

    // top left, top right, down left, down right
    wire [10:0] addr_00, addr_01, addr_10, addr_11;
    wire [3:0]  dx_gen, dy_gen;
    wire        valid_gen;

    wire [35:0] v00_data, v01_data, v10_data, v11_data;
    
    reg  [3:0]  dx_delayed, dy_delayed;
    reg         valid_delayed;


    always @(posedge clk) begin
        if (!rst_n) begin
            valid_delayed <= 0;
            dx_delayed    <= 0;
            dy_delayed    <= 0;
        end else begin
            dx_delayed    <= dx_gen;
            dy_delayed    <= dy_gen;
            valid_delayed <= valid_gen; 
        end
    end

    // 2 tick delay
    rect_addr_gen address_generator (
        .clk  (clk),
        .rst_n(rst_n),

        .u(s_axis_u), // 0..639
        .v(s_axis_v), // 0..479
        .valid_in(s_axis_tvalid),

        .addr_00(addr_00),
        .addr_01(addr_01),
        .addr_10(addr_10), 
        .addr_11(addr_11),

        .dx(dx_gen),
        .dy(dy_gen),
        .valid_out(valid_gen)
    );
    

    wire [17:0] v00_x = v00_data[17:0];
    wire [17:0] v00_y = v00_data[35:18];

    wire [17:0] v01_x = v01_data[17:0];
    wire [17:0] v01_y = v01_data[35:18];

    wire [17:0] v10_x = v10_data[17:0];
    wire [17:0] v10_y = v10_data[35:18];

    wire [17:0] v11_x = v11_data[17:0];
    wire [17:0] v11_y = v11_data[35:18];


    dual_port_rom #(
        .DATA_WIDTH(36),
        .ADDR_WIDTH(11), // log2(30*40) = 11 | *rounded up
        .INIT_FILE("rect_map.hex")
    ) rom0 (
        .clk(clk),

        .addr_a(addr_00),
        .q_a(v00_data),
        
        .addr_b(addr_01),
        .q_b(v01_data)
    );


    dual_port_rom #(
        .DATA_WIDTH(36),
        .ADDR_WIDTH(11),
        .INIT_FILE("rect_map.hex")
    ) rom1 (
        .clk(clk),

        .addr_a(addr_10),
        .q_a(v10_data),
        
        .addr_b(addr_11),
        .q_b(v11_data)
    );



    bilinear_interp_core bilinear_interp_X (
        .clk(clk),
        .rst_n(rst_n),

        .v00(v00_x),
        .v01(v01_x), 
        .v10(v10_x),
        .v11(v11_x), 

        .dx(dx_delayed),
        .dy(dy_delayed),
        .valid_in(valid_delayed),

        .result(m_axis_tdata[17:0]),
        .valid_out(m_axis_tvalid)
    );

    bilinear_interp_core bilinear_interp_Y (
        .clk(clk),
        .rst_n(rst_n),

        .v00(v00_y),
        .v01(v01_y), 
        .v10(v10_y),
        .v11(v11_y), 

        .dx(dx_delayed),
        .dy(dy_delayed),
        .valid_in(valid_delayed),

        .result(m_axis_tdata[35:18]),
        .valid_out()
    );

    // Since bilinear_interp_core work with the same clk and rst_n signals, we can assume, that valid_out will be burst simultaneously 


endmodule