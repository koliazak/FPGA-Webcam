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
import select


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
latest_annotated_jpeg = None
jpeg_lock = threading.Lock()
detect_lock = threading.Lock()
frame_counter = 0
detect_counter = 0


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

    logger.info("waiting for frames via FIFO")

    fd = os.open(FIFO_PATH, os.O_RDONLY | os.O_NONBLOCK)

    try:
        while True:
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
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

def detector(logger: Logger):
    while True:
        try:
            timeout_retry = time.time()
            last_detect = -1
            session = requests.Session()

            while True:
                with jpeg_lock:
                    if latest_bgr is None or latest_jpeg is None:
                        time.sleep(0.05)
                        continue
                    if last_detect == frame_counter:
                        time.sleep(0.01)
                        continue
                    bgr = latest_bgr.copy()
                    jpeg = latest_jpeg
                    last_detect = frame_counter

                coords = None
                if time.time() - timeout_retry > 5:
                    try:
                        with session as s:
                                res = s.post(DETECT_ADDR, files={"file": jpeg}, timeout=3)
                                res = res.json()
                                coords = res.get("coordinates")
                    except Exception as e:
                        logger.error(f"Couldn't reach detection endpoint, retrying in 5 seconds \n{e}")
                        timeout_retry = time.time()

                if coords:
                    coords = [
                        [tuple(box[:2]), tuple(box[2:])] for box in coords
                    ]
                    for i in coords:
                        cv2.rectangle(bgr, i[0], i[1], (255, 0, 0), 2)

                ret, jpeg_tmp = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 65])

                with detect_lock:
                    global latest_annotated_jpeg, detect_counter
                    if not latest_annotated_jpeg:
                        latest_annotated_jpeg = jpeg

                    if ret:
                        detect_counter += 1
                        latest_annotated_jpeg = jpeg_tmp.tobytes()
                    else:
                        logger.error("Couldn't compress jpeg")

        except (KeyboardInterrupt, SystemExit):
            logger.info("Detector stopped")

        except Exception as ex:
            logger.error(ex)
            time.sleep(0.05)

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
                try:
                    with detect_lock:
                        if detect_counter == last_seen:
                            time.sleep(0.01)
                            continue
                        jpeg = latest_annotated_jpeg
                        last_seen = detect_counter

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
    time.sleep(0.1)
    threading.Thread(target=detector, args=[logger.getChild("detector")], daemon=True).start()

    time.sleep(0.2)


    with socketserver.ThreadingTCPServer(('', 8080), Handler) as srv:
        try:
            logger.info("Server started")
            srv.daemon_threads = True
            srv.allow_reuse_address = True
            srv.serve_forever()
        except (KeyboardInterrupt, SystemExit):
            logger.error("Shutdown signal received")
        finally:
            logger.info('Stopping server')
            srv.server_close()
