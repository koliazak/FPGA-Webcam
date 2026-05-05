# Clock

create_clock -period 20.000 -name clk [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN N18 [get_ports clk]


set_property IOSTANDARD LVCMOS33 [get_ports p_data[7]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[6]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[5]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[4]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[3]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[2]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[1]]
set_property IOSTANDARD LVCMOS33 [get_ports p_data[0]]

set_property PACKAGE_PIN M17 [get_ports p_data[7]]
set_property PACKAGE_PIN P18 [get_ports p_data[6]]
set_property PACKAGE_PIN N20 [get_ports p_data[5]]
set_property PACKAGE_PIN M19 [get_ports p_data[4]]
set_property PACKAGE_PIN M20 [get_ports p_data[3]]
set_property PACKAGE_PIN L17 [get_ports p_data[2]]
set_property PACKAGE_PIN M18 [get_ports p_data[1]]
set_property PACKAGE_PIN L20 [get_ports p_data[0]]


set_property IOSTANDARD LVCMOS33 [get_ports p_clock]
set_property IOSTANDARD LVCMOS33 [get_ports x_clock]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]
set_property IOSTANDARD LVCMOS33 [get_ports href]
set_property IOSTANDARD LVCMOS33 [get_ports pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports ret]

set_property PACKAGE_PIN K19 [get_ports p_clock]
set_property PACKAGE_PIN J20 [get_ports x_clock]
set_property PACKAGE_PIN J19 [get_ports vsync]
set_property PACKAGE_PIN K18 [get_ports href]
set_property PACKAGE_PIN L19 [get_ports pwdn]
set_property PACKAGE_PIN L16 [get_ports ret]

set_property PACKAGE_PIN H20 [get_ports siod]
set_property IOSTANDARD LVCMOS33 [get_ports siod]
set_property PULLTYPE PULLUP [get_ports siod]

set_property PACKAGE_PIN G19 [get_ports sioc]
set_property IOSTANDARD LVCMOS33 [get_ports sioc]
set_property PULLTYPE PULLUP [get_ports sioc]


# i2c

#set_property PACKAGE_PIN J19 [get_ports i2c_sda]
#set_property IOSTANDARD LVCMOS33 [get_ports i2c_sda]
#set_property PULLTYPE PULLUP [get_ports i2c_sda]

#set_property PACKAGE_PIN K18 [get_ports i2c_scl]
#set_property IOSTANDARD LVCMOS33 [get_ports i2c_scl]
#set_property PULLTYPE PULLUP [get_ports i2c_scl]


# reset

#set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
#set_property PACKAGE_PIN P19 [get_ports rst_n]


# buttons

set_property IOSTANDARD LVCMOS33 [get_ports start]
set_property PACKAGE_PIN U20 [get_ports start]

#set_property IOSTANDARD LVCMOS33 [get_ports search_en_btn]
#set_property PACKAGE_PIN T19 [get_ports search_en_btn]


#set_property IOSTANDARD LVCMOS33 [get_ports btn_search_up]
#set_property IOSTANDARD LVCMOS33 [get_ports btn_search_down]

#set_property PACKAGE_PIN T19 [get_ports btn_search_up]
#set_property PACKAGE_PIN U19 [get_ports btn_search_down]

## LED

set_property PACKAGE_PIN E19 [get_ports done_led]
set_property IOSTANDARD LVCMOS33 [get_ports done_led]

#set_property PACKAGE_PIN H18 [get_ports search_en_led]
#set_property IOSTANDARD LVCMOS33 [get_ports search_en_led]

#set_property PACKAGE_PIN K17 [get_ports error_led]
#set_property IOSTANDARD LVCMOS33 [get_ports error_led]