"""
Stereo Core Processing Engine

!!! 90-degree rotation applied at the final
    visualization stage due to holder construction.
"""

import time
import numpy as np
import cv2


class StereoDepthPipeline:
    def __init__(
        self,
        calib_file='stereo_calib.npz',
        min_depth=0.4,
        max_depth=5.0,
        block_size=19,
        uniqueness_ratio=2,
        texture_threshold=0,
        alpha=0.25,
        colormap=cv2.COLORMAP_TURBO,
        scale=1.0,
        quant=0,
        temporal_median_filter_enable = False
    ):
        # Load stereo calibration
        calib = np.load(calib_file)
        self.scale = float(scale)
        self.raw_w, self.raw_h = tuple(np.asarray(calib['IMG_SIZE']).ravel().astype(int))
        self.F_B = float(calib['F_B'])  # focal_length_px * baseline_meters
        self.img_size = (int(self.raw_w * self.scale), int(self.raw_h * self.scale))
        self.w, self.h = self.img_size

        if self.scale != 1.0:
            self.F_B *= self.scale
            K1, D1, R1, P1 = calib['K1'].copy(), calib['D1'], calib['R1'], calib['P1'].copy()
            K2, D2, R2, P2 = calib['K2'].copy(), calib['D2'], calib['R2'], calib['P2'].copy()
            K1[:2] *= self.scale; P1[:2] *= self.scale
            K2[:2] *= self.scale; P2[:2] *= self.scale
            mapL1, mapL2 = cv2.initUndistortRectifyMap(K1, D1, R1, P1, (self.w, self.h), cv2.CV_16SC2)
            mapR1, mapR2 = cv2.initUndistortRectifyMap(K2, D2, R2, P2, (self.w, self.h), cv2.CV_16SC2)
            self.map_l = (mapL1, mapL2)
            self.map_r = (mapR1, mapR2)
        else:
            self.map_l = (calib['mapL1'], calib['mapL2'])
            self.map_r = (calib['mapR1'], calib['mapR2'])

        self.min_depth = float(min_depth)
        self.max_depth = float(max_depth)
        self.alpha = float(alpha)
        self.block_size = int(block_size)
        self.uniqueness_ratio = int(uniqueness_ratio)
        self.texture_threshold = int(texture_threshold)

        # Disparity range for metric working range [min_depth, max_depth]
        # d = F_B / Z
        self.min_disp = max(1, int(self.F_B / self.max_depth))
        max_disp = int(np.ceil(self.F_B / self.min_depth))
        n_disp = int(np.ceil((max_disp - self.min_disp) / 16.0)) * 16
        self.num_disp = max(16, min(256, n_disp))
        self.pad = self.num_disp

        self.lut = cv2.applyColorMap(np.arange(256, dtype=np.uint8).reshape(1, 256), colormap).reshape(256, 3)

        self._init_matcher()

        self.depth_smooth = None

        self._buf_rl = np.empty((self.h, self.w), dtype=np.uint8)
        self._buf_rr = np.empty((self.h, self.w), dtype=np.uint8)
        self._buf_rl_pad = np.empty((self.w, self.h + self.pad), dtype=np.uint8)
        self._buf_rr_pad = np.empty((self.w, self.h + self.pad), dtype=np.uint8)


        self.quant = quant

        self.temp_median_filter_en = temporal_median_filter_enable
        self.depth_ring = np.zeros((3, self.h, self.w), np.float32)
        self.ring_i = 0

    def _init_matcher(self):
        """Initializes Sum of Absolute Differences (SAD) block matcher."""
        self.matcher = cv2.StereoBM_create(
            numDisparities=self.num_disp,
            blockSize=self.block_size
        )
        self.matcher.setMinDisparity(self.min_disp)
        self.matcher.setPreFilterType(cv2.STEREO_BM_PREFILTER_XSOBEL)
        self.matcher.setPreFilterSize(9)
        self.matcher.setPreFilterCap(31)
        self.matcher.setTextureThreshold(self.texture_threshold)
        self.matcher.setUniquenessRatio(self.uniqueness_ratio)
        self.matcher.setSpeckleWindowSize(150)
        self.matcher.setSpeckleRange(2)

    def update_params(self, block_size=None, uniqueness_ratio=None, alpha=None, temporal_median_filter_enable=None):
        reinit = False
        if block_size is not None and block_size != self.block_size:
            # Must be odd and >= 5
            self.block_size = max(5, int(block_size) | 1)
            reinit = True
        if uniqueness_ratio is not None and uniqueness_ratio != self.uniqueness_ratio:
            self.uniqueness_ratio = int(uniqueness_ratio)
            reinit = True
        if alpha is not None:
            self.alpha = float(np.clip(alpha, 0.0, 1.0))
        if temporal_median_filter_enable is not None:
            self.temp_median_filter_en = bool(temporal_median_filter_enable)
        if reinit:
            self._init_matcher()


    def process(self, raw_l, raw_r):
        """
        Processes a raw stereo pair into a dense metric depth map.
        
        Args:
            raw_l: Left image or raw buffer (uint8 Luma 480x640 or YUYV 480x1280)
            raw_r: Right image or raw buffer (uint8 Luma 480x640 or YUYV 480x1280)
            
        Returns:
            dict containing:
                'depth': metric depth map in native sensor orientation (float32, meters)
                'disp': disparity map in native sensor orientation (float32, pixels)
                'valid': boolean mask of valid depth pixels in native orientation
                'colored': BGR color-mapped depth in native orientation (uint8, 480x640x3)
                'vis_depth': BGR color-mapped depth rotated right (uint8, 640x480x3)
                'vis_left': BGR rectified left camera frame rotated right (uint8, 640x480x3)
                'center_depth': metric depth at center crosshair (float, meters)
        """

        gl = self._extract_luma(raw_l)
        gr = self._extract_luma(raw_r)


        # Quantization if enabled
        if self.quant != 0:
            q = 8 - self.quant
            gl = (gl >> q) << q
            gr = (gr >> q) << q

        # Rectification in NATIVE sensor orientation (640x480)
        rl = cv2.remap(gl, *self.map_l, cv2.INTER_LINEAR, dst=self._buf_rl)
        rr = cv2.remap(gr, *self.map_r, cv2.INTER_LINEAR, dst=self._buf_rr)

        # Block Matching in NATIVE sensor orientation
        # Due to physical 90-deg CW mounting, the calibrated physical baseline is along
        # the sensor's vertical axis (columns).
        # So it's needed to align scanlines with cv2.StereoBM by transposing coordinates (.T).

        rl_t = rl.T  # shape (640, 480)
        rr_t = rr.T  # shape (640, 480)

        rl_pad = cv2.copyMakeBorder(rl_t, 0, 0, self.pad, 0, cv2.BORDER_REPLICATE, dst=self._buf_rl_pad)
        rr_pad = cv2.copyMakeBorder(rr_t, 0, 0, self.pad, 0, cv2.BORDER_REPLICATE, dst=self._buf_rr_pad)

        raw_disp_pad = self.matcher.compute(rl_pad, rr_pad)
        raw_disp = raw_disp_pad[:, self.pad:].T.astype(np.float32) / 16.0

        # Disparity filtering & metric depth calculation
        disp_filtered = cv2.medianBlur(raw_disp, 5)
        valid = (disp_filtered >= self.min_disp) & (disp_filtered <= (self.min_disp + self.num_disp))

        depth = np.zeros_like(disp_filtered)
        depth[valid] = self.F_B / disp_filtered[valid]
        valid = valid & (depth >= self.min_depth) & (depth <= self.max_depth)
        depth[~valid] = 0.0


        # temporal median filter if enabled
        if self.temp_median_filter_en:
            self.depth_ring[self.ring_i % 3] = depth
            self.ring_i += 1
            depth = np.median(self.depth_ring, axis=0)

        # EMA smoothing filter
        if self.depth_smooth is None or self.depth_smooth.shape != depth.shape:
            self.depth_smooth = depth.copy()
        else:
            update_mask = valid & (self.depth_smooth > 0)
            self.depth_smooth[update_mask] = ((1.0 - self.alpha) * self.depth_smooth[update_mask] + self.alpha * depth[update_mask])
            fresh_mask = valid & (self.depth_smooth <= 0)
            self.depth_smooth[fresh_mask] = depth[fresh_mask]
            self.depth_smooth[~valid] = 0.0

        active_depth = self.depth_smooth

        # Near = Hot (Red/Orange), Far = Cold (Blue/Purple), Invalid = Black
        z_norm = np.clip((active_depth - self.min_depth) / (self.max_depth - self.min_depth), 0.0, 1.0)
        lut_idx = (255 - z_norm * 255).astype(np.uint8)
        colored = self.lut[lut_idx]
        colored[~valid] = [0, 0, 0]


        vis_depth = cv2.rotate(colored, cv2.ROTATE_90_COUNTERCLOCKWISE)
        vis_left = cv2.rotate(rl, cv2.ROTATE_90_COUNTERCLOCKWISE)

        cy, cx = vis_depth.shape[0] // 2, vis_depth.shape[1] // 2
        rot_depth = cv2.rotate(active_depth, cv2.ROTATE_90_COUNTERCLOCKWISE)
        center_patch = rot_depth[cy - 2 : cy + 3, cx - 2 : cx + 3]
        valid_center = center_patch[center_patch > 0]
        center_dist = float(np.median(valid_center)) if len(valid_center) > 0 else 0.0

        return {
            'depth': active_depth,
            'disp': disp_filtered,
            'valid': valid,
            'colored': colored,
            'vis_depth': vis_depth,
            'vis_left': cv2.cvtColor(vis_left, cv2.COLOR_GRAY2BGR),
            'center_depth': center_dist,
        }

    def render_display(self, result, mode='combo', show_osd=True, fps=0.0, mouse_pos=None):
        """
        Renders the final visualization frame for web streaming and display.
        
        Args:
            result: dict returned from process()
            mode: 'depth', 'combo' (side-by-side), or 'overlay'
            show_osd: whether to draw metric crosshair, distance text, and colorbar
            fps: measured processing FPS to show on OSD
            
        Returns:
            BGR uint8 image ready for JPEG encoding / display
        """
        vis_depth = result['vis_depth']
        vis_left = result['vis_left']
        h, w = vis_depth.shape[:2]

        if mode == 'depth':
            canvas = vis_depth.copy()
        elif mode == 'overlay':
            valid_rot = cv2.rotate(result['valid'].astype(np.uint8), cv2.ROTATE_90_COUNTERCLOCKWISE).astype(bool)
            canvas = vis_left.copy()
            canvas[valid_rot] = cv2.addWeighted(vis_left[valid_rot], 0.35, vis_depth[valid_rot], 0.65, 0)
        else: # 'combo' 
            canvas = np.hstack([vis_left, vis_depth])

        if not show_osd:
            return canvas

        ox = w if mode == 'combo' else 0
        if mouse_pos is not None:
            cx, cy = mouse_pos
            cx = max(0, min(canvas.shape[1] - 1, cx))
            cy = max(0, min(canvas.shape[0] - 1, cy))
        else:
            cy, cx = h // 2, ox + w // 2

        rot_depth = cv2.rotate(result['depth'], cv2.ROTATE_90_COUNTERCLOCKWISE)
        depth_x = cx - ox if mode == 'combo' else cx

        target_d = 0.0
        if 0 <= depth_x < w and 0 <= cy < h:
            y1, y2 = max(0, cy - 2), min(h, cy + 3)
            x1, x2 = max(0, depth_x - 2), min(w, depth_x + 3)
            patch = rot_depth[y1:y2, x1:x2]
            valid_patch = patch[patch > 0]
            if len(valid_patch) > 0:
                target_d = float(np.median(valid_patch))

        ch_len = 12
        ch_color = (0, 255, 255)
        ch_thick = 2
        cv2.line(canvas, (cx - ch_len, cy), (cx + ch_len, cy), (0, 0, 0), ch_thick + 2)
        cv2.line(canvas, (cx, cy - ch_len), (cx, cy + ch_len), (0, 0, 0), ch_thick + 2)
        cv2.line(canvas, (cx - ch_len, cy), (cx + ch_len, cy), ch_color, ch_thick)
        cv2.line(canvas, (cx, cy - ch_len), (cx, cy + ch_len), ch_color, ch_thick)

        if target_d > 0.05:
            d_text = f"{target_d:.2f} m"
            badge_bg = (20, 20, 20)
            badge_fg = (0, 255, 255)
        else:
            d_text = "--.- m"
            badge_bg = (40, 40, 40)
            badge_fg = (160, 160, 160)

        t_size = cv2.getTextSize(d_text, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2)[0]
        bx1 = max(0, min(canvas.shape[1] - t_size[0] - 12, cx - t_size[0] // 2 - 6))
        by1 = max(0, cy - ch_len - 8 - t_size[1])
        bx2 = bx1 + t_size[0] + 12
        by2 = by1 + t_size[1] + 6
        
        cv2.rectangle(canvas, (bx1, by1), (bx2, by2), badge_bg, -1)
        cv2.rectangle(canvas, (bx1, by1), (bx2, by2), (80, 80, 80), 1)
        cv2.putText(canvas, d_text, (bx1 + 6, by2 - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.55, badge_fg, 2, cv2.LINE_AA)


        bar_w = 12
        bar_h = 160
        bar_x = (w if mode == 'combo' else canvas.shape[1]) - bar_w - 14
        bar_y = 20
        grad = np.linspace(255, 0, bar_h, dtype=np.uint8)
        grad_col = self.lut[grad]
        canvas[bar_y : bar_y + bar_h, bar_x : bar_x + bar_w] = np.repeat(grad_col[:, np.newaxis, :], bar_w, axis=1)
        cv2.rectangle(canvas, (bar_x - 1, bar_y - 1), (bar_x + bar_w, bar_y + bar_h), (255, 255, 255), 1)
        cv2.putText(canvas, f"{self.min_depth:.1f}m", (bar_x - 36, bar_y + 10), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1)
        cv2.putText(canvas, f"{(self.min_depth + self.max_depth)/2:.1f}m", (bar_x - 36, bar_y + bar_h // 2 + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1)
        cv2.putText(canvas, f"{self.max_depth:.1f}m", (bar_x - 36, bar_y + bar_h), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (255, 255, 255), 1)

        info_y = h - 12
        fps_str = f"{fps:.1f} FPS" if fps > 0.0 else ""
        info_text = f"SAD StereoBM | Range: {self.min_depth:.1f}-{self.max_depth:.1f}m | {fps_str}".strip(" |")
        cv2.putText(canvas, info_text, (10, info_y), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (0, 0, 0), 2, cv2.LINE_AA)
        cv2.putText(canvas, info_text, (10, info_y), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (0, 255, 200), 1, cv2.LINE_AA)

        if mode == 'combo':
            # Add camera label
            cv2.putText(canvas, "Rectified Left", (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(canvas, "Rectified Left", (10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
            cv2.putText(canvas, "Metric Depth", (ox + 10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(canvas, "Metric Depth", (ox + 10, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)

        return canvas

    def _extract_luma(self, frame):
        """Extracts 8-bit Luma channel from YUYV 4:2:2 raw or grayscale, handling scaling."""
        if isinstance(frame, np.ndarray):
            if frame.dtype == np.uint8:
                if frame.shape == (self.raw_h, self.raw_w):
                    return frame
                elif frame.shape == (self.raw_h, self.raw_w * 2):
                    return frame[:, 0::2]
                elif frame.shape == (self.h, self.w):
                    return frame
                elif frame.size == self.raw_h * self.raw_w * 2:
                    return frame.reshape(self.raw_h, self.raw_w * 2)[:, 0::2]
                elif frame.size == self.raw_h * self.raw_w:
                    return frame.reshape(self.raw_h, self.raw_w)

        buf = np.frombuffer(frame, dtype=np.uint8)
        if buf.size == self.raw_h * self.raw_w * 2:
            luma = buf.reshape(self.raw_h, self.raw_w * 2)[:, 0::2]
        elif buf.size == self.raw_h * self.raw_w:
            luma = buf.reshape(self.raw_h, self.raw_w)
        elif buf.size == self.h * self.w:
            return buf.reshape(self.h, self.w)
        else:
            raise ValueError(f"Unexpected frame byte length: {len(buf)}")

        if self.scale != 1.0 and luma.shape != (self.h, self.w):
            luma = cv2.resize(luma, (self.w, self.h), interpolation=cv2.INTER_NEAREST)

        return luma


