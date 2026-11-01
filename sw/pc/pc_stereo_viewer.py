import os
import sys
import time
import glob
import argparse
import threading
import urllib.request
import numpy as np
import cv2

from stereo_core import StereoDepthPipeline


FRAME_W, FRAME_H = 640, 480
RAW_FRAME_SIZE = FRAME_W * FRAME_H * 2
mouse_pos = (320, 240)


class HttpRawReader:
    """Non-blocking background reader for multipart/x-mixed-replace raw streams."""
    def __init__(self, url):
        self.url = url
        self.frame = None
        self.ok = False
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        while self.running:
            try:
                req = urllib.request.urlopen(self.url, timeout=5)
                buf = b''
                while self.running:
                    chunk = req.read(32768)
                    if not chunk:
                        break
                    buf += chunk
                    idx = buf.find(b'\r\n\r\n')
                    if idx != -1:
                        if len(buf) >= idx + 4 + RAW_FRAME_SIZE:
                            raw = buf[idx + 4 : idx + 4 + RAW_FRAME_SIZE]
                            self.frame = raw
                            self.ok = True
                            buf = buf[idx + 4 + RAW_FRAME_SIZE:]
            except Exception as e:
                self.ok = False
                time.sleep(1.0)

    def read(self):
        return self.ok, self.frame

    def stop(self):
        self.running = False




def on_mouse(event, x, y, flags, param):
    global mouse_pos
    if event == cv2.EVENT_MOUSEMOVE:
        mouse_pos = (x, y)

def main():
    parser = argparse.ArgumentParser(description="Stereo Viewer")
    parser.add_argument('--board-ip', type=str, default='10.0.0.2', help="Zynq board IP (default: 10.0.0.2)")
    parser.add_argument('--port', type=int, default=8080, help="Zynq board port (default: 8080)")
    parser.add_argument('--calib', type=str, default='stereo_calib.npz', help="Path to stereo_calib.npz")
    parser.add_argument('--swap', action='store_true', help="Swap Left and Right cameras")
    parser.add_argument('--mode', type=str, default='overlay', choices=['combo', 'depth', 'overlay'], help="Initial view mode")
    args = parser.parse_args()


    calib_path = args.calib
    if not os.path.exists(calib_path):
        os.path.join(CURRENT_DIR, 'stereo_calib.npz')
    if not os.path.exists(calib_path):
        print(f"[ERROR] Could not find calibration file '{args.calib}'")
        sys.exit(1)

    pipeline = StereoDepthPipeline(
        calib_file=calib_path,
        min_depth=0.4,
        max_depth=5.0,
        block_size=19,
        uniqueness_ratio=2,
        alpha=0.1,
        quant=0,
        scale=1
    )

        
    url_l = f"http://{args.board_ip}:{args.port}/raw_l"
    url_r = f"http://{args.board_ip}:{args.port}/raw_r"
    print(f"[Viewer] Connecting to Zynq streams: {url_l} and {url_r} ...")
    reader_l = HttpRawReader(url_l)
    reader_r = HttpRawReader(url_r)

    view_mode = args.mode
    show_osd = True
    swap_cams = args.swap
    temporal_median_filter_enable = False

    window_name = "Stereo Viewer"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)

    print("\nControls:")
    print("  [m]       : Toggle View Mode (Side-by-Side / Depth Only / Overlay)")
    print("  [o]       : Toggle OSD (Crosshair & Scale bar)")
    print("  [s]       : Toggle Left/Right camera swap")
    print("  [t]       : Toggle tempoaral median filter")
    print("  [p]       : Save snapshot")
    print("  [q / ESC] : Quit\n")

    cv2.setMouseCallback(window_name, on_mouse)
    t_prev = time.perf_counter()
    fps_smooth = 0.0

    while True:    
        ok_l, raw_l = reader_l.read()
        ok_r, raw_r = reader_r.read()
        if not (ok_l and ok_r):
            time.sleep(0.01)
            continue

        if swap_cams:
            raw_l, raw_r = raw_r, raw_l

        t_now = time.perf_counter()
        dt = t_now - t_prev
        t_prev = t_now
        instant_fps = 1.0 / max(1e-4, dt)
        fps_smooth = instant_fps if fps_smooth == 0.0 else 0.9 * fps_smooth + 0.1 * instant_fps

        res = pipeline.process(raw_l, raw_r)
        vis = pipeline.render_display(res, mode=view_mode, show_osd=show_osd, fps=fps_smooth, mouse_pos=mouse_pos)

        cv2.imshow(window_name, vis)

        key = cv2.waitKey(15) & 0xFF
        if key in (27, ord('q')):
            break
        elif key == ord('m'):
            modes = ['combo', 'depth', 'overlay']
            view_mode = modes[(modes.index(view_mode) + 1) % len(modes)]
            print(f"[Mode] View switched to: {view_mode}")
        elif key == ord('o'):
            show_osd = not show_osd
        elif key == ord('s'):
            swap_cams = not swap_cams
            print(f"[Config] Swap cameras: {swap_cams}")
        elif key == ord('p'):
            snap_path = f"depth_snap_{int(time.time())}.jpg"
            cv2.imwrite(snap_path, vis)
            print(f"[Snapshot] Saved -> {snap_path}")    
        elif key == ord('t'):
            temporal_median_filter_enable = not temporal_median_filter_enable
            pipeline.update_params(temporal_median_filter_enable = temporal_median_filter_enable)
            print(f"[Config] Temporal median filter: {temporal_median_filter_enable}")    
    reader_l.stop()
    reader_r.stop()
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
