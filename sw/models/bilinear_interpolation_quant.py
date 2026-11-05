# import cv2
from pathlib import Path

import cv2
import numpy as np


CALIB_PATH = Path(__file__).resolve().parents[2] / "stereo_calib.npz"
calib = np.load(CALIB_PATH)
W, H = 640, 480
STEP, BORDER = 16, 16
F = 7
Q_MAX = 1 << (18 - 1 - F) # Q11.7: |value| < 1024


def build_maps(calib):
    xL, yL = cv2.initUndistortRectifyMap(calib['K1'], calib['D1'], calib['R1'], calib['P1'], (W+STEP, H+STEP), cv2.CV_32FC1)
    xR, yR = cv2.initUndistortRectifyMap(calib['K2'], calib['D2'], calib['R2'], calib['P2'], (W+STEP, H+STEP), cv2.CV_32FC1)
    return (xL, yL, xR, yR)


def bilinear_model(grid_f):
    grid = np.round(grid_f * (1 << F)).astype(np.int64)
    u, v = np.meshgrid(np.arange(W, dtype=np.float64), np.arange(H, dtype=np.float64))

    idx_u, idx_v = (u // STEP).astype(int), (v // STEP).astype(int)
    dx, dy = (u % STEP).astype(np.int32), (v % STEP).astype(np.int32)

    num_u, num_v = grid.shape[1], grid.shape[0]

    idx_u_next = np.clip(idx_u + 1, 0, num_u-1).astype(int)
    idx_v_next = np.clip(idx_v + 1, 0, num_v-1).astype(int)


    V00 = grid[idx_v, idx_u]             # top-left
    V01 = grid[idx_v, idx_u_next]        # top-right
    V10 = grid[idx_v_next, idx_u]        # bot-left
    V11 = grid[idx_v_next, idx_u_next]   # bot-right    
    
    top = V00 + dx*(V01-V00) // STEP
    bot = V10 + dx*(V11-V10) // STEP
    out = top * (STEP - dy) // STEP + dy * bot // STEP
    return out / float(1 << F), grid


def report(name, ref, approx, grid):
    err_x = np.abs(ref[0] - approx[0])
    err_y = np.abs(ref[1] - approx[1])
    euclid = np.hypot(err_x, err_y)
    print(f"--- {name} ---")
    print(f"node value range: [{grid.min() / (1 << F):.4f}, {grid.max() / (1 << F):.4f}] (must fit |v| < {Q_MAX} for Q{18-F}.{F})")
    print(f"Max err X: {err_x.max():.4f} px")
    print(f"Max err Y: {err_y.max():.4f} px")
    print(f"Max Euclidean err (full)  : {euclid.max():.4f} px")
    print(f"Max Euclidean err (inside): {euclid[:-BORDER, :-BORDER].max():.4f} px")


def export_hex_map(grid_x, grid_y, filename="rect_map.hex"):
    assert(grid_x.shape == grid_y.shape)

    with open(filename, "w") as f:
        for v in range(grid_y.shape[0]):
            for u in range(grid_y.shape[1]):
                x_val = int(grid_x[v, u]) & 0x3FFFF
                y_val = int(grid_y[v, u]) & 0x3FFFF

                word_36 = (y_val << 18) | x_val
                f.write(f"{word_36:09x}\n")



def main():
    print(f"Q factor: {F}  (signed Q{18-F}.{F}")
    calib = np.load(CALIB_PATH)
    xL, yL, xR, yR = build_maps(calib)


    approx_xL, g_xL = bilinear_model(xL[0::STEP, 0::STEP])
    approx_yL, g_yL = bilinear_model(yL[0::STEP, 0::STEP])
    report("Left", (xL[:H, :W], yL[:H, :W]), (approx_xL, approx_yL), np.maximum(np.abs(g_xL), np.abs(g_yL)))

    
    approx_xR, g_xR = bilinear_model(xR[0::STEP, 0::STEP])
    approx_yR, g_yR = bilinear_model(yR[0::STEP, 0::STEP])
    report("Right", (xR[:H, :W], yR[:H, :W]), (approx_xR, approx_yR), np.maximum(np.abs(g_xR), np.abs(g_yR)))

    export_hex_map(g_xL, g_yL, "rect_nodes_L.hex")
    export_hex_map(g_xR, g_yR, "rect_node_R.hex")

if __name__ == '__main__':
    main()