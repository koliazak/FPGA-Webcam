######################################################################
#                                                                    #
#           Constriants File for EBAZ4205 Zynq Board                 #
#                      v0.1 2019-12-08                               #
#             By Xiaohai Li (haixiaolee@gmail.com)                   #
#                                                                    #
######################################################################


# Dual-color LED
set_property IOSTANDARD LVCMOS33 [get_ports {emio_tri_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {emio_tri_io[0]}]

set_property PACKAGE_PIN W13 [get_ports {emio_tri_io[0]}]
set_property PACKAGE_PIN W14 [get_ports {emio_tri_io[1]}]

set_property DRIVE 12 [get_ports {emio_tri_io[1]}]
set_property DRIVE 12 [get_ports {emio_tri_io[0]}]

# ENET0 MII via EMIO
set_property IOSTANDARD LVCMOS33 [get_ports enet0_mdio_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports enet0_mdio_mdio_io]

set_property IOSTANDARD LVCMOS33 [get_ports enet0_mii_rx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports enet0_mii_rx_dv]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_rxd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_rxd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_rxd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_rxd[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports enet0_mii_tx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_tx_en[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_txd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_txd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_txd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {enet0_mii_txd[0]}]

set_property PACKAGE_PIN W15 [get_ports enet0_mdio_mdc]
set_property PACKAGE_PIN Y14 [get_ports enet0_mdio_mdio_io]

set_property PACKAGE_PIN U14 [get_ports enet0_mii_rx_clk]
set_property PACKAGE_PIN W16 [get_ports enet0_mii_rx_dv]
set_property PACKAGE_PIN Y17 [get_ports {enet0_mii_rxd[3]}]
set_property PACKAGE_PIN V17 [get_ports {enet0_mii_rxd[2]}]
set_property PACKAGE_PIN V16 [get_ports {enet0_mii_rxd[1]}]
set_property PACKAGE_PIN Y16 [get_ports {enet0_mii_rxd[0]}]

set_property PACKAGE_PIN U15 [get_ports enet0_mii_tx_clk]
set_property PACKAGE_PIN W19 [get_ports {enet0_mii_tx_en[0]}]
set_property PACKAGE_PIN Y19 [get_ports {enet0_mii_txd[3]}]
set_property PACKAGE_PIN V18 [get_ports {enet0_mii_txd[2]}]
set_property PACKAGE_PIN Y18 [get_ports {enet0_mii_txd[1]}]
set_property PACKAGE_PIN W18 [get_ports {enet0_mii_txd[0]}]

set_property DRIVE 8 [get_ports enet0_mdio_mdc]
set_property DRIVE 8 [get_ports enet0_mdio_mdio_io]

set_property DRIVE 8 [get_ports {enet0_mii_tx_en[0]}]
set_property DRIVE 8 [get_ports {enet0_mii_txd[3]}]
set_property DRIVE 8 [get_ports {enet0_mii_txd[2]}]
set_property DRIVE 8 [get_ports {enet0_mii_txd[1]}]
set_property DRIVE 8 [get_ports {enet0_mii_txd[0]}]



#########################################################
#                                                       #
#                   CUSTOM PORTS                        #
#                                                       #
#########################################################

# Clock
#create_clock -period 20.000 -name clk [get_ports clk]
#set_property IOSTANDARD LVCMOS33 [get_ports clk]
#set_property PACKAGE_PIN N18 [get_ports clk]


set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data[0]}]

set_property PACKAGE_PIN M17 [get_ports {pixel_data[7]}]
set_property PACKAGE_PIN P18 [get_ports {pixel_data[6]}]
## data5 N20
set_property PACKAGE_PIN K19 [get_ports {pixel_data[5]}] 
set_property PACKAGE_PIN M19 [get_ports {pixel_data[4]}]
set_property PACKAGE_PIN M20 [get_ports {pixel_data[3]}]
set_property PACKAGE_PIN L17 [get_ports {pixel_data[2]}]
set_property PACKAGE_PIN M18 [get_ports {pixel_data[1]}]
set_property PACKAGE_PIN L20 [get_ports {pixel_data[0]}]


set_property IOSTANDARD LVCMOS33 [get_ports pclk] 
create_clock -period 40.000 -name pclk [get_ports pclk]
set_property PACKAGE_PIN N20 [get_ports pclk] 


set_property IOSTANDARD LVCMOS33 [get_ports xclk]
set_property IOSTANDARD LVCMOS33 [get_ports vsync]
set_property IOSTANDARD LVCMOS33 [get_ports href]
set_property IOSTANDARD LVCMOS33 [get_ports pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst_n]

# p_clock K19

set_property PACKAGE_PIN J20 [get_ports xclk] 
set_property PACKAGE_PIN J19 [get_ports vsync]
set_property PACKAGE_PIN K18 [get_ports href]
set_property PACKAGE_PIN L19 [get_ports pwdn]
set_property PACKAGE_PIN L16 [get_ports cam_rst_n]

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


#set_property IOSTANDARD LVCMOS33 [get_ports key[3]]
#set_property IOSTANDARD LVCMOS33 [get_ports key[2]]
#set_property IOSTANDARD LVCMOS33 [get_ports key[1]]
#set_property IOSTANDARD LVCMOS33 [get_ports key[0]]

#set_property PACKAGE_PIN U19 [get_ports key[3]]
#set_property PACKAGE_PIN T19 [get_ports key[2]]
#set_property PACKAGE_PIN U20 [get_ports key[1]]
#set_property PACKAGE_PIN V20 [get_ports key[0]]


#set_property IOSTANDARD LVCMOS33 [get_ports search_en_btn]
#set_property PACKAGE_PIN T19 [get_ports search_en_btn]


#set_property IOSTANDARD LVCMOS33 [get_ports btn_search_up]
#set_property IOSTANDARD LVCMOS33 [get_ports btn_search_down]

#set_property PACKAGE_PIN T19 [get_ports btn_search_up]
#set_property PACKAGE_PIN U19 [get_ports btn_search_down]

## LED

set_property PACKAGE_PIN E19 [get_ports done_led]
set_property IOSTANDARD LVCMOS33 [get_ports done_led]

#set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets p_clock_IBUF]

#set_property PACKAGE_PIN H18 [get_ports busy_led]
#set_property IOSTANDARD LVCMOS33 [get_ports busy_led]

#set_property PACKAGE_PIN K17 [get_ports error_led]
#set_property IOSTANDARD LVCMOS33 [get_ports error_led]

#set_property PACKAGE_PIN K17 [get_ports btn_led]
#set_property IOSTANDARD LVCMOS33 [get_ports btn_led]


