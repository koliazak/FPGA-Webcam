import http.server
from logging import Logger

import requests
import socketserver
import numpy as np
import cv2
import os
import time
import threading
import logging
import signal


"""MJPEG stream from /dev/shm/frame.raw"""

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - [%(name)s] - %(message)s",
    handlers=[
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

FIFO_PATH = '/tmp/frame_ready'
FRAME_PATH = '/dev/shm/frame.raw'
DETECT_ADDR = 'http://10.0.0.1:8000/detect/'
W, H = 640, 480
FRAME_SIZE = W * H * 2
STALE_THRESHOLD_S = 2.0   # warn if no new frame for 2 seconds

latest_jpeg = None
latest_bgr  = None
jpeg_lock = threading.Lock()
frame_counter = 0


def rgb565_to_bgr(raw):
    rgb565 = np.frombuffer(raw, dtype=np.uint16).reshape((H, W))
    r = ((rgb565 >> 11) & 0x1F)
    g = ((rgb565 >> 5) & 0x3F)
    b = (rgb565 & 0x1F)
    r = (r << 3) | (r >> 2)
    g = (g << 2) | (g >> 4)
    b = (b << 3) | (b >> 2)
    return np.dstack((b, g, r)).astype(np.uint8)


def encoder(logger: Logger):
    if not os.path.exists(FIFO_PATH):
        os.mkfifo(FIFO_PATH)

    logger.info("[encoder] waiting for frames via FIFO")

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
                    logger.warning(f"bad frame size {len(raw)}, expected {FRAME_SIZE}")
                    continue

                bgr = rgb565_to_bgr(raw)
                ret, jpeg = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 65])

                if ret:
                    with jpeg_lock:
                        global latest_jpeg, latest_bgr, frame_counter
                        latest_jpeg = jpeg.tobytes()
                        latest_bgr = bgr.copy()
                        frame_counter += 1

            except Exception as e:
                logger.error(e)
    except (KeyboardInterrupt, SystemExit):
        logger.info("Encoder stopped")
    finally:
        os.close(fd)


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

            last_seen = -1

            while True:
                session = requests.Session()
                try:
                    with jpeg_lock:
                        if frame_counter == last_seen:
                            time.sleep(0.01)
                            continue
                        jpeg = latest_jpeg
                        last_seen = frame_counter

                    with session as s:
                        res = s.post(DETECT_ADDR, files={"file": jpeg}, timeout=3)
                        res = res.json()
                    coords = res.get("coordinates")
                    if coords:
                        coords = [
                            [tuple(box[:2]), tuple(box[2:])] for box in coords
                        ]
                        for i in coords:
                            cv2.rectangle(latest_bgr, i[0], i[1], (255,0,0), 2)

                    ret, jpeg_tmp = cv2.imencode(".jpg", latest_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 65])

                    if ret:
                        jpeg = jpeg_tmp
                    else:
                        logger.error("Couldn't compress jpeg")
                    self.wfile.write(b'--frame\r\n')
                    self.wfile.write(b'Content-Type: image/jpeg\r\n')
                    self.wfile.write(f'Content-Length: {len(jpeg)}\r\n'.encode())
                    self.wfile.write(b'\r\n')
                    self.wfile.write(jpeg)
                    self.wfile.write(b'\r\n')


                except (BrokenPipeError, ConnectionResetError, KeyboardInterrupt, SystemExit):
                    break
                except Exception as e:
                    logger.error(f"[http] stream error: {e}", exc_info=True)
                    break
        else:
            self.send_error(404)


if __name__ == '__main__':
    # signal.signal(signal.SIGINT, signal_handler)
    # signal.signal(signal.SIGTERM, signal_handler)

    logger.info("Waiting for /dev/shm/frame.raw ...")
    while not os.path.exists(FRAME_PATH):
        time.sleep(0.1)

    threading.Thread(target=encoder, args=[logger.getChild("encoder")], daemon=True).start()
    time.sleep(0.2)


    with socketserver.ThreadingTCPServer(('', 8080), Handler) as srv:
        try:
            logger.info("Server started")
            srv.daemon_threads = True
            srv.serve_forever()
        except (KeyboardInterrupt, SystemExit):
            logger.error("Shutdown signal received")
        finally:
            logger.info('Stopping server')
            srv.server_close()
