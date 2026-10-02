#!/usr/bin/env python3

import http.server
import socketserver
import numpy as np
import cv2
import os
import time
import threading

FRAME_PATH = '/dev/shm/frame_l.raw'
W, H = 640, 480
FRAME_SIZE = W * H * 2

latest_jpeg = None
jpeg_lock = threading.Lock()


def rgb565_to_bgr(raw):
    img = np.frombuffer(raw, dtype=np.uint8).reshape((H, W, 2))
    return cv2.cvtColor(img, cv2.COLOR_BGR5652BGR)


class FPSCounter:
    def __init__(self, name, alpha=0.1):
        self.name = name
        self.alpha = alpha
        self.fps = 0.0
        self.last_time = None
        self.lock = threading.Lock()

    def tick(self):
        current_time = time.time()

        with self.lock:
            if self.last_time is None:
                self.last_time = current_time
                return

            dt = current_time - self.last_time
            if dt <= 0:
                return
            self.last_time = current_time
            instant_fps = 1 / dt

            if self.fps == 0.0:
                self.fps = instant_fps
            else:
                self.fps = self.alpha * instant_fps + (1 - self.alpha) * self.fps

    def get_fps(self):
        with self.lock:
            return self.fps
stream_fps = FPSCounter("Stream")


def encoder():
    global latest_jpeg
    last_mtime = 0
    while True:
        try:
            st = os.stat(FRAME_PATH)
            if st.st_mtime != last_mtime:
                last_mtime = st.st_mtime
                with open(FRAME_PATH, 'rb') as f:
                    t0 = time.perf_counter()
                    raw = f.read()
                if len(raw) == FRAME_SIZE:
                    t1 = time.perf_counter()
                    bgr = rgb565_to_bgr(raw)
                    cv2.putText(bgr, f"FPS: {stream_fps.get_fps():.1f}", (30,30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,0,0), 2)
                    t2 = time.perf_counter()
                    ret, jpeg = cv2.imencode('.jpg', bgr,
                        [int(cv2.IMWRITE_JPEG_QUALITY), 85])
                    t3 = time.perf_counter()
                    print(f"read={t1-t0:.3f} convert={t2-t1:.3f} encode={t3-t2:.3f}")
                    if ret:
                        with jpeg_lock:
                            latest_jpeg = jpeg.tobytes()
            time.sleep(0.015)
        except FileNotFoundError:
            time.sleep(0.05)
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
                    stream_fps.tick()
                    time.sleep(0.04)   # ~25 fps
                except (BrokenPipeError, ConnectionResetError):
                    break
        else:
            self.send_error(404)


if __name__ == '__main__':
    print("Waiting for /dev/shm/frame.raw ...")
    while not os.path.exists(FRAME_PATH):
        time.sleep(0.1)

    threading.Thread(target=encoder, daemon=True).start()
    time.sleep(0.2)

    with socketserver.ThreadingTCPServer(('10.0.0.2', 8080), Handler) as srv:
        print("Continuous MJPEG stream: http://10.0.0.2:8080/video")
        print("Open browser to:         http://<board-ip>:8080/")
        srv.serve_forever()
