import http.server
import socketserver
import numpy as np
import cv2
import os
import time
import threading

"""MJPEG stream from /dev/shm/frame.raw"""

FIFO_PATH = '/tmp/frame_ready'
FRAME_PATH = '/dev/shm/frame.raw'
W, H = 640, 480
FRAME_SIZE = W * H * 2
STALE_THRESHOLD_S = 2.0   # warn if no new frame for 2 seconds

latest_jpeg = None
jpeg_lock = threading.Lock()
frame_ready = threading.Event()

last_sent_id = 0
frame_id = 0

def rgb565_to_bgr(raw):
    rgb565 = np.frombuffer(raw, dtype=np.uint16).reshape((H, W))
    r = ((rgb565 >> 11) & 0x1F)
    g = ((rgb565 >> 5) & 0x3F)
    b = (rgb565 & 0x1F)
    r = (r << 3) | (r >> 2)
    g = (g << 2) | (g >> 4)
    b = (b << 3) | (b >> 2)
    return np.dstack((b, g, r)).astype(np.uint8)



def encoder():
    global latest_jpeg
    global frame_id

    if not os.path.exists(FIFO_PATH):
        os.mkfifo(FIFO_PATH);

    print("[encoder] waiting for frames via FIFO")

    fd = os.open(FIFO_PATH, os.O_RDONLY)

    try:
        while True:
            data = os.read(fd, 1)

            if not data:
                break

            try:
                with open(FRAME_PATH, "rb") as f:
                    raw = f.read()

                if len(raw) != FRAME_SIZE:
                    print(f"[encoder] bad frame size {len(raw)}, expected {FRAME_SIZE}")
                    continue 

                bgr = rgb565_to_bgr(raw)
                ret, jpeg = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
                
                if ret:
                    with jpeg_lock:
                        latest_jpeg = jpeg.tobytes()
                        frame_id += 1
                        frame_ready.set()
           
            except Exception as e:
                print(f"[encoder] {e}")
    finally:
        os.close(fd)


HTML = b'''<!DOCTYPE html>
<html><body style="background:#111;text-align:center;">
<img src="/video" width="640" height="480" style="border:2px solid #444;">
</body></html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        global frame_id, last_sent_id
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
                        current_id = frame_id

                    if jpeg is None or current_id == last_sent_id:
                        # Wait up to 1s for a frame instead of busy-loop
                        if not frame_ready.wait(timeout=0.05):
                            continue

                    last_sent_id = current_id

                    self.wfile.write(b'--frame\r\n')
                    self.wfile.write(b'Content-Type: image/jpeg\r\n')
                    self.wfile.write(
                        f'Content-Length: {len(jpeg)}\r\n'.encode())
                    self.wfile.write(b'\r\n')
                    self.wfile.write(jpeg)
                    self.wfile.write(b'\r\n')
                    time.sleep(0.04)

                except (BrokenPipeError, ConnectionResetError):
                    break
                except Exception as e:
                    print(f"[http] stream error: {e}")
                    break
        else:
            self.send_error(404)


if __name__ == '__main__':
    print("Waiting for /dev/shm/frame.raw ...")
    while not os.path.exists(FRAME_PATH):
        time.sleep(0.1)

    threading.Thread(target=encoder, daemon=True).start()
    time.sleep(0.2)

    with socketserver.ThreadingTCPServer(('', 8080), Handler) as srv:
        print("Continuous MJPEG: http://0.0.0.0:8080/video")
        srv.serve_forever()
