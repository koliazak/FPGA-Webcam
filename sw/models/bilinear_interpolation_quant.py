# import cv2
from pathlib import Path

import cv2
import numpy as np


CALIB_PATH = Path(__file__).resolve().parents[2] / "stereo_calib.npz"
calib = np.load(CALIB_PATH)
W, H = 640, 480
F = 7



xL, yL = cv2.initUndistortRectifyMap(calib['K1'], calib['D1'], calib['R1'], calib['P1'], (W+16, H+16), cv2.CV_32FC1)
xR, yR = cv2.initUndistortRectifyMap(calib['K2'], calib['D2'], calib['R2'], calib['P2'], (W+16, H+16), cv2.CV_32FC1)

u, v = np.meshgrid(np.arange(W, dtype=np.float64), np.arange(H, dtype=np.float64))


grid_xL = np.round(xL[0::16, 0::16] * (1 << F)).astype(np.int32)
grid_yL = np.round(yL[0::16, 0::16] * (1 << F)).astype(np.int32)



idx_u, idx_v = (u // 16).astype(int), (v // 16).astype(int)
dx, dy = (u % 16).astype(np.int32), (v % 16).astype(np.int32)



idx_u_next = np.clip(idx_u + 1, 0, 40).astype(int)
idx_v_next = np.clip(idx_v + 1, 0, 30).astype(int)


V00 = grid_xL[idx_v, idx_u]             # top-left
V01 = grid_xL[idx_v, idx_u_next]        # top-right
V10 = grid_xL[idx_v_next, idx_u]        # bot-left
V11 = grid_xL[idx_v_next, idx_u_next]   # bot-right

top_x = V00 + dx*(V01-V00) // 16 # top-x
bot_x = V10 + dx*(V11-V10) // 16 # bot-x



#xL_approx = top_x + dy * (bot_x - top_x)
xL_approx = top_x * (16 - dy) // 16 +  dy * bot_x // 16


V00 = grid_yL[idx_v, idx_u]             # top-left
V01 = grid_yL[idx_v, idx_u_next]        # top-right
V10 = grid_yL[idx_v_next, idx_u]        # bot-left
V11 = grid_yL[idx_v_next, idx_u_next]   # bot-right

top_x = V00 + dx*(V01-V00) //16 # top-x
bot_x = V10 + dx*(V11-V10) //16 # bot-x

#xL_approx = top_x + dy * (bot_x - top_x)
yL_approx = top_x * (16 - dy) // 16 +  dy * bot_x // 16


xL= xL[:-16, :-16]
yL= yL[:-16, :-16]

err_xL = np.abs(xL - xL_approx / (1 << F))
err_yL = np.abs(yL - yL_approx / (1 << F))
euclidean_err = np.sqrt(err_xL**2 + err_yL**2)


print(f"Q factor: {F}")
print(f"Max err X: {err_xL.max():.4f} px")
print(f"Max err Y: {err_yL.max():.4f} px")
print(f"Max Euclidean err  16x16: {euclidean_err.max():.4f} px")
print(f"Max Euclidean err (inside): {euclidean_err[:-16, :-16].max():.4f} px")



xL_max = np.partition(grid_xL.flatten(), -5)[-5:] / (1 << F)
yL_max = np.partition(grid_yL.flatten(), -5)[-5:] / (1 << F)

xL_min = np.partition(grid_xL.flatten(), 5)[:5] / (1 << F)
yL_min = np.partition(grid_yL.flatten(), 5)[:5] / (1 << F)
print(f"{xL_max=} \n{yL_max=} \n{xL_min=} \n{yL_min=}")
