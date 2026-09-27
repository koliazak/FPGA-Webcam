import http.server
import socketserver
import numpy as np
import cv2
import os
import time
import threading


W, H = 640, 480
FRAME_SIZE = W * H * 2
FRAME_L = '/dev/shm/frame_l.raw'
FRAME_R = '/dev/shm/frame_r.raw'
PORT = 8082


THRESH = 10               # intencity threshhold (6 bit, 0-63)
GAIN   = 4                # increading for visuality
SHIFT_Y, SHIFT_X = 0, 0

latest_jpeg = None
jpeg_lock = threading.Lock()
frame_ready = threading.Event()


def load(path):
    with open(path, 'rb') as f:
        return f.read()


def compute_diff() -> bytes | None:
    raw_l = load(FRAME_L)
    raw_r = load(FRAME_R)

    if len(raw_l) != FRAME_SIZE or len(raw_r) != FRAME_SIZE:
        return None

    a = np.frombuffer(raw_l, dtype=np.uint16).reshape((H, W))
    b = np.frombuffer(raw_r, dtype=np.uint16).reshape((H, W))

    ga = (a >> 5) & 0x3F
    gb = (b >> 5) & 0x3F

    # RRRRR GGGGGG BBBBB >> 5
    # 00000 0RRRRG GGGGG &
    # 00000 000001 11111

    if SHIFT_Y or SHIFT_X:
        gb = np.roll(gb, (SHIFT_Y, SHIFT_X), axis=(0, 1))

    d = np.abs(ga.astype(np.int16) - gb.astype(np.int16))
    d = np.where(d < THRESH, 0, d * GAIN).astype(np.uint8)

    ret, jpeg = cv2.imencode('.jpg', d, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
    return jpeg.tobytes() if ret else None


def encoder():
    global latest_jpeg
    last_l = last_r = 0

    while True:
        try:
            st_l, st_r = os.stat(FRAME_L), os.stat(FRAME_R)
            current_time_l = getattr(st_l, 'st_mtime_ns', 0)
            current_time_r = getattr(st_r, 'st_mtime_ns', 0)
            if current_time_l == last_l or current_time_r == last_r:
                time.sleep(0.01)
                continue
            last_l,last_r = current_time_l, current_time_r
            t1 = time.perf_counter()
            jpeg = compute_diff()
            t2 = time.perf_counter()
            print(f"time for computing diff: {t2-t1:.3f}")
            if jpeg:
                with jpeg_lock:
                    latest_jpeg = jpeg
                frame_ready.set()
        except FileNotFoundError:
            time.sleep(0.1)
        except Exception as e:
            print(f"[encoder] {e}")
            time.sleep(0.1)


HTML = b'''<!DOCTYPE html>
<html><body style="background:#111;text-align:center;">
<img src="/video" width="640" height="480" style="border:2px solid #444;">
</body></html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(HTML)

        elif self.path == '/video':
            self.send_response(200)
            self.send_header('Content-Type',
                'multipart/x-mixed-replace; boundary=frame')
            self.end_headers()
            while True:
                try:
                    with jpeg_lock:
                        jpeg = latest_jpeg
                    if jpeg is None:
                        time.sleep(0.02)
                        continue
                    self.wfile.write(b'--frame\r\n')
                    self.wfile.write(b'Content-Type: image/jpeg\r\n')
                    self.wfile.write(f'Content-Length: {len(jpeg)}\r\n'.encode())
                    self.wfile.write(b'\r\n')
                    self.wfile.write(jpeg)
                    self.wfile.write(b'\r\n')
                    #stream_fps.tick()
                    time.sleep(0.04)   # ~25 fps
                except (BrokenPipeError, ConnectionResetError):
                    break
        else:
            self.send_error(404)


if __name__ == '__main__':
    threading.Thread(target=encoder, daemon=True).start()
    with socketserver.ThreadingTCPServer(('10.0.0.2', PORT), Handler) as srv:
        print(f"Diff stream: http://<board-ip>:{PORT}/video")
        srv.serve_forever()

