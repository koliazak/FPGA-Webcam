SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../../rtl/stereo/rectifier/stereo_rectify_top.v
VERILOG_SOURCES += $(PWD)/../../rtl/stereo/rectifier/bilinear_interp_core.v 
VERILOG_SOURCES += $(PWD)/../../rtl/stereo/rectifier/rect_addr_gen.v
VERILOG_SOURCES += $(PWD)/../../rtl/stereo/rectifier/dual_port_rom.v

TOPLEVEL = stereo_rectify_top

COCOTB_TEST_MODULES = interp_tb

include $(shell cocotb-config --makefiles)/Makefile.sim
