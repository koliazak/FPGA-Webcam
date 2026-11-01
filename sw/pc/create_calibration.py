"""Stereo calibration for stereo pair 640x480 (cameras are rotated 90-deg clockwise!!!)."""

import glob
import numpy as np
import cv2

PHOTO_DIR    = './calib_photos'
SQUARE_M     = 0.026
RAW_W, RAW_H = 640, 480
PATTERN     = (7, 4)              # number of intersections on a chessboard
OUT_FILE     = 'stereo_calib.npz'
MODE = "RGB565"                   # "YUV422" | "RGB565"


def load_gray(path) -> np.ndarray | None:
    global MODE
    raw = np.fromfile(path, dtype=np.uint16)
    if raw.size != RAW_W * RAW_H:
        return None
    
    if MODE == "RGB565":
        raw = raw.reshape(RAW_H, RAW_W)
        r = ((raw & 0xF800) >> 11) << 3
        g = ((raw & 0x07E0) >> 5) << 2
        b = (raw & 0x001F) << 3
        img_bgr = np.stack([b, g, r], axis=-1).astype(np.uint8)
        gray_img = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        return gray_img.reshape(RAW_H, RAW_W)
    elif MODE == "YUV422":
        raw_u8 = raw.view(np.uint8)
        gray_img = raw_u8.reshape(RAW_H, RAW_W * 2)[:, 0::2].astype(np.float32)
        return gray_img

def make_objp(pattern):
    objp = np.zeros((pattern[0] * pattern[1], 3), np.float32)
    objp[:, :2] = np.mgrid[0:pattern[0], 0:pattern[1]].T.reshape(-1, 2) * SQUARE_M
    return objp

def find_corners(g):
    ok, corners = cv2.findChessboardCornersSB(g, PATTERN)
    if ok:
        return PATTERN, corners
    return None, None


objpoints, pts_l, pts_r = [], [], []
used = 0

for f_l in sorted(glob.glob(f'{PHOTO_DIR}/calib_*_L.raw')):
    f_r = f_l.replace('_L.raw', '_R.raw')
    g_l, g_r = load_gray(f_l), load_gray(f_r)
    if g_l is None or g_r is None:
        print(f'[skip] {f_l}: bad file'); continue

    pat_l, c_l = find_corners(g_l)
    pat_r, c_r = find_corners(g_r)
    if pat_l is None or pat_r is None or pat_l != pat_r:
        print(f'[skip] {f_l}: board L={pat_l} R={pat_r}'); continue

    objpoints.append(make_objp(pat_l))
    pts_l.append(c_l); pts_r.append(c_r)
    used += 1
    print(f'[ ok ] {f_l}  pattern={pat_l}')

print(f'\nused pairs: {used}')
if used < 6:
    raise SystemExit('not enough pairs (must be >= 6, better 15)')

IMG_SIZE = (RAW_W, RAW_H)

rms_l, K1, D1, _, _ = cv2.calibrateCamera(objpoints, pts_l, IMG_SIZE, None, None)
rms_r, K2, D2, _, _ = cv2.calibrateCamera(objpoints, pts_r, IMG_SIZE, None, None)
print(f'\nintrinsics rms: L={rms_l:.3f}  R={rms_r:.3f} px   (goal < 0.5)')

term = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 100, 1e-5)
rms_s, K1, D1, K2, D2, R, T, E, F = cv2.stereoCalibrate(
    objpoints, pts_l, pts_r, K1, D1, K2, D2, IMG_SIZE,
    criteria=term, flags=cv2.CALIB_FIX_INTRINSIC)
B = np.linalg.norm(T)

print(f'stereo rms = {rms_s:.3f} px')
print(f'baseline B = {B:.4f} m')
if rms_s > 0.8:
    print(f'WARNING: stereo rms {rms_s:.2f} px - result is dubious, make more photos of board.')

R1, R2, P1, P2, Q, roi1, roi2 = cv2.stereoRectify(
    K1, D1, K2, D2, IMG_SIZE, R, T,
    flags=cv2.CALIB_ZERO_DISPARITY, alpha=0)

mapL1, mapL2 = cv2.initUndistortRectifyMap(K1, D1, R1, P1, IMG_SIZE, cv2.CV_16SC2)
mapR1, mapR2 = cv2.initUndistortRectifyMap(K2, D2, R2, P2, IMG_SIZE, cv2.CV_16SC2)

fx  = P1[0, 0]
F_B = fx * B
print(f'\nfx = {fx:.1f} px,  F_B = {F_B:.1f} px*m')
print(f'disp: @0.5m={F_B/0.5:.0f}px  @1m={F_B:.0f}px  @2m={F_B/2:.0f}px')
print(f'recommended numDisparities = {int(np.ceil((F_B/0.5)/16))*16}')

np.savez(OUT_FILE, K1=K1, D1=D1, K2=K2, D2=D2, R=R, T=T,
         R1=R1, R2=R2, P1=P1, P2=P2, Q=Q,
         mapL1=mapL1, mapL2=mapL2, mapR1=mapR1, mapR2=mapR2,
         F_B=F_B, roi1=roi1, roi2=roi2, IMG_SIZE=IMG_SIZE)
print(f'\nsaved -> {OUT_FILE}')


