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



# Left camera

set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_r[0]}]

set_property PACKAGE_PIN T19 [get_ports {pixel_data_r[7]}]
set_property PACKAGE_PIN H16 [get_ports {pixel_data_r[6]}]
set_property PACKAGE_PIN U20 [get_ports {pixel_data_r[5]}]
set_property PACKAGE_PIN H18 [get_ports {pixel_data_r[4]}]
set_property PACKAGE_PIN V20 [get_ports {pixel_data_r[3]}]
set_property PACKAGE_PIN R18 [get_ports {pixel_data_r[2]}]
set_property PACKAGE_PIN U19 [get_ports {pixel_data_r[1]}]
set_property PACKAGE_PIN G20 [get_ports {pixel_data_r[0]}]


set_property IOSTANDARD LVCMOS33 [get_ports pclk_r]
create_clock -period 40.000 -name pclk_l [get_ports pclk_r]
set_property PACKAGE_PIN K17 [get_ports pclk_r]


set_property IOSTANDARD LVCMOS33 [get_ports xclk_r]
set_property IOSTANDARD LVCMOS33 [get_ports vsync_r]
set_property IOSTANDARD LVCMOS33 [get_ports href_r]
#set_property IOSTANDARD LVCMOS33 [get_ports pwdn_r]
#set_property IOSTANDARD LVCMOS33 [get_ports cam_rst_n_r]

set_property PACKAGE_PIN J18 [get_ports xclk_r]
set_property PACKAGE_PIN H17 [get_ports vsync_r]
set_property PACKAGE_PIN P20 [get_ports href_r]
#set_property PACKAGE_PIN H16 [get_ports pwdn_r]
#set_property PACKAGE_PIN B20 [get_ports cam_rst_n_r]

set_property PACKAGE_PIN D18 [get_ports siod_r]
set_property IOSTANDARD LVCMOS33 [get_ports siod_r]
set_property PULLTYPE PULLUP [get_ports siod_r]

set_property PACKAGE_PIN E19 [get_ports sioc_r]
set_property IOSTANDARD LVCMOS33 [get_ports sioc_r]
set_property PULLTYPE PULLUP [get_ports sioc_r]


# Right camera

set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pixel_data_l[0]}]

set_property PACKAGE_PIN L20 [get_ports {pixel_data_l[7]}]
set_property PACKAGE_PIN M18 [get_ports {pixel_data_l[6]}]
set_property PACKAGE_PIN L17 [get_ports {pixel_data_l[5]}]
set_property PACKAGE_PIN M20 [get_ports {pixel_data_l[4]}]
set_property PACKAGE_PIN K18 [get_ports {pixel_data_l[3]}]
set_property PACKAGE_PIN M19 [get_ports {pixel_data_l[2]}]
set_property PACKAGE_PIN M17 [get_ports {pixel_data_l[1]}]
set_property PACKAGE_PIN P18 [get_ports {pixel_data_l[0]}]


set_property IOSTANDARD LVCMOS33 [get_ports pclk_l]
create_clock -period 40.000 -name pclk_r [get_ports pclk_l]
set_property PACKAGE_PIN N20 [get_ports pclk_l]


set_property IOSTANDARD LVCMOS33 [get_ports xclk_l]
set_property IOSTANDARD LVCMOS33 [get_ports vsync_l]
set_property IOSTANDARD LVCMOS33 [get_ports href_l]
set_property IOSTANDARD LVCMOS33 [get_ports pwdn_l]
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst_n_l]

set_property PACKAGE_PIN L16 [get_ports xclk_l]
set_property PACKAGE_PIN G19 [get_ports vsync_l]
set_property PACKAGE_PIN H20 [get_ports href_l]
set_property PACKAGE_PIN L19 [get_ports pwdn_l]
set_property PACKAGE_PIN J19 [get_ports cam_rst_n_l]

set_property PACKAGE_PIN K19 [get_ports siod_l]
set_property IOSTANDARD LVCMOS33 [get_ports siod_l]
set_property PULLTYPE PULLUP [get_ports siod_l]

set_property PACKAGE_PIN J20 [get_ports sioc_l]
set_property IOSTANDARD LVCMOS33 [get_ports sioc_l]
set_property PULLTYPE PULLUP [get_ports sioc_l]


# buttons

set_property IOSTANDARD LVCMOS33 [get_ports start_btn_r]
set_property PACKAGE_PIN T20 [get_ports start_btn_r]
set_property PULLTYPE PULLUP [get_ports start_btn_r]

set_property IOSTANDARD LVCMOS33 [get_ports start_btn_l]
set_property PACKAGE_PIN P19 [get_ports start_btn_l]
set_property PULLTYPE PULLUP [get_ports start_btn_l]


## LED

#set_property PACKAGE_PIN T19 [get_ports done_led_l]
#set_property IOSTANDARD LVCMOS33 [get_ports done_led_l]

#set_property PACKAGE_PIN U20 [get_ports done_led_r]
#set_property IOSTANDARD LVCMOS33 [get_ports done_led_r]

