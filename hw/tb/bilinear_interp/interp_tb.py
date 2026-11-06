import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
import numpy as np
import sys
from pathlib import Path

from numpy._core.numeric import exp


sys.path.append(str(Path(__file__).resolve().parents[3] / "sw/models"))
from bilinear_interpolation_quant import map_uv_to_xy_q, CALIB_PATH, STEP, build_maps, bilinear_model

async def reset_dut(dut):

    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_rectification_pipeline(dut):
    
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    await reset_dut(dut)
    


    calib = np.load(CALIB_PATH)
    xL, yL, _, _ = build_maps(calib)

    _, grid_xL = bilinear_model(xL[0::STEP, 0::STEP])
    _, grid_yL = bilinear_model(yL[0::STEP, 0::STEP])
    

    test_coords = [
        (0, 0),       
        (10, 5),      
        (16, 16),     
        (639, 479)
    ]
    
    for u, v in test_coords:
        dut.s_axis_u.value = u
        dut.s_axis_v.value = v
        dut.s_axis_tvalid.value = 1
        
        await RisingEdge(dut.clk)
        dut.s_axis_tvalid.value = 0
        

        expected_x, expected_y = map_uv_to_xy_q(u, v, grid_xL, grid_yL) 
        
        timeout = 0
        while True:
            await ReadOnly()
            if dut.m_axis_tvalid.value == 1:
                break
            
            await RisingEdge(dut.clk)
            timeout += 1
            if timeout > 10:
                assert False, f"Timeout! Didn't receive ({u},{v})"


        data = int(dut.m_axis_tdata.value) # 36-bit data

        rtl_x = data & 0x3FFFF
        if rtl_x & 0x20000:
            rtl_x -= 0x40000

        rtl_y = (data >> 18) & 0x3FFFF
        if rtl_y & 0x20000:
            rtl_y -= 0x40000

        assert rtl_x == expected_x and rtl_y == expected_y, f"Expected: ({expected_x}, {expected_y}), got ({rtl_x}, {rtl_y}) instead."       
        dut._log.info(f"Pass: u={u}, v={v} -> RTL(X:{rtl_x >> 7}, Y:{rtl_y >> 7}) == GM(X:{expected_x >> 7}, Y:{expected_y >> 7})")
        
        await RisingEdge(dut.clk)
