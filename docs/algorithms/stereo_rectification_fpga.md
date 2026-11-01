# Hardware Stereo Camera Rectification

## Problem

`cv2.initUndistortRectifyMap` generates maps for X and Y coordinates of image
rectification. For a 640x480 image each map holds 307 200 `float32` values
(1.2 MB); the stereo pair needs four of them. This is far too much for the
internal PL memory (BRAM) of the Xilinx Zynq-7010.

## Solution

Instead of storing every pixel, only reference nodes are kept: a sparse
grid with a 16-pixel step (41x31 nodes per map). Values for all pixels in
between are computed in real time by **bilinear interpolation**. This reduces
memory by a factor of ~250 (4.9 MB of float maps -> ~10 KB of nodes) while
keeping subpixel accuracy.

## Measured accuracy

Full frame 640x480, current calibration (can be created with `sw/pc/create_calibration.py`).
"Inside" = frame without the outer 16-px border.

| Model | Camera | Max Euclidean, full | Max Euclidean, inside |
|---|---|---|---|
| float nodes | Left  | 0.1148 px | 0.0873 px |
| float nodes | Right | 0.0838 px | 0.0646 px |
| Q11.7 nodes | Left  | 0.1315 px | 0.0969 px |
| Q11.7 nodes | Right | 0.1019 px | 0.0775 px |

Quantization to Q11.7 adds ~0.02 px. For reference: the previous on-board
path (16SC2 maps, integer pixel rounding) has ~0.98 px error.

## Node data format

- Signed fixed-point **Q11.7** in an 18-bit word - one node per native BRAM
  cell (18 or 36-bit); an x/y pair also packs into one 36-bit word.
- Observed node range requires numbers to be fitted to +/-1024; resolution 1/128 px.
- Interpolation weights are exact 4-bit (grid step 16); Therefore no multipliers are needed, only shifts and adds.


## Files

| Path | Description |
|---|---|
| `docs/algorithms/bilinear_interpolation.md` | This document |
| `sw/models/bilinear_interpolation.py` | Accuracy check of the sparse-grid + bilinear model (floating-point nodes) |
| `sw/models/bilinear_interpolation_quant.py` | Same, with Q11.7 fixed-point nodes; validates node range and serves as reference for the PL rectifier testbench |
| `sw/pc/stereo_calib.npz` | Calibration input for both cameras |


## Reproduce

```bash
python3 sw/models/bilinear_interpolation.py
python3 sw/models/bilinear_interpolation_quant.py
```
