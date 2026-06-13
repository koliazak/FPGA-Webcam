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

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


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
JPEG_QUALITY = 60
DETECTION_TIMEOUT = 3
DETECTION_RETRY_INTERVAL = 5


class ShutdownEvent:
    def __init__(self):
        self._event = threading.Event()

    def signal(self):
        self._event.set()

    def is_set(self):
        return self._event.is_set()

    def wait(self, timeout=None):
        return self._event.wait(timeout)

shutdown_event = ShutdownEvent()

class SharedState:
    def __init__(self):
        self.latest_jpeg = None
        self.latest_bgr  = None
        self.frame_counter = 0

        self.latest_annotated_jpeg = None
        self.detect_counter = 0

        self.jpeg_lock = threading.Lock()
        self.detect_lock = threading.Lock()

        self.last_frame_time = time.time()

state = SharedState()


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

encoder_fps = FPSCounter("Encoder")
detector_fps = FPSCounter("Decoder")
stream_fps = FPSCounter("Stream")

def rgb565_to_bgr(raw):
    rgb565 = np.frombuffer(raw, dtype=np.uint16).reshape((H, W))
    r = ((rgb565 >> 11) & 0x1F)
    g = ((rgb565 >> 5) & 0x3F)
    b = (rgb565 & 0x1F)
    r = (r << 3) | (r >> 2)
    g = (g << 2) | (g >> 4)
    b = (b << 3) | (b >> 2)
    return np.dstack((b, g, r)).astype(np.uint8)

def create_http_session():
    session = requests.Session()
    retry_strategy = Retry(
        total=3,
        connect=0,
        backoff_factor=0.5,
        status_forcelist=[500, 502, 503, 504],
        allowed_methods=["POST"]
    )
    adapter = HTTPAdapter(
        max_retries=retry_strategy,
        pool_connections=1,
        pool_maxsize=1
    )
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session

def encoder(logger: Logger, state: SharedState, shutdown: ShutdownEvent):
    if not os.path.exists(FIFO_PATH):
        os.mkfifo(FIFO_PATH)

    logger.info("waiting for frames via FIFO")
    fd = os.open(FIFO_PATH, os.O_RDONLY | os.O_NONBLOCK)

    try:
        while not shutdown.is_set():
            ready, _, _ = select.select([fd], [], [], 0.1)

            if not ready:
                continue

            try:

                data = os.read(fd, 1)
                if not data:
                    time.sleep(0.01)
                    continue

                with open(FRAME_PATH, "rb") as f:
                    raw = f.read()

                if len(raw) != FRAME_SIZE:
                    logger.warning(f"bad frame size {len(raw)}, expected {FRAME_SIZE}")
                    continue

                bgr = rgb565_to_bgr(raw)
                ret, jpeg = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])

                if ret:
                    jpeg_bytes = jpeg.tobytes()
                    with state.jpeg_lock:
                        state.latest_jpeg = jpeg_bytes
                        state.latest_bgr = bgr
                        state.frame_counter += 1
                        state.last_frame_time = time.time()

                    encoder_fps.tick()
                    if encoder_fps.get_fps() > 0:
                        logger.debug(f"Encoder FPS: {encoder_fps.get_fps():.1f}")

                else:
                    logger.error("Failed to encode JPEG")

            except Exception as e:
                logger.error(e)

    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        try:
            os.close(fd)
        except:
            pass
        logger.info("Encoder stopped")

def detector(logger: Logger, state: SharedState, shutdown: ShutdownEvent):

    session = create_http_session()
    last_detect = -1
    last_retry = time.time()

    try:
        while not shutdown.is_set():

            try:

                with state.jpeg_lock:
                    if state.latest_bgr is None or state.latest_jpeg is None:
                        time.sleep(0.05)
                        continue

                    if last_detect == state.frame_counter:
                        time.sleep(0.01)
                        continue
                    bgr = state.latest_bgr
                    jpeg = state.latest_jpeg
                    last_detect = state.frame_counter

                coords = None
                connection_status = "No connection"
                if time.time() - last_retry > DETECTION_RETRY_INTERVAL:
                    try:
                        res = session.post(
                            DETECT_ADDR,
                            files={"file": jpeg},
                            timeout=DETECTION_TIMEOUT
                        )
                        if res.status_code == 200:
                            coords = res.json().get("coordinates")
                        else:
                            logger.warning(f"Detection returned status {res.status_code}")

                        connection_status = "Connected"

                    except Exception as e:
                        logger.error(f"Detection failed: {e}")
                        last_retry = time.time()

                bgr = bgr.copy()

                if coords:
                    coords = [
                        [tuple(box[:2]), tuple(box[2:])] for box in coords
                    ]
                    for i in coords:
                        cv2.rectangle(bgr, i[0], i[1], (255, 0, 0), 2)

                # cv2.putText(bgr, f"FPS[D]: {detector_fps.get_fps():.1f}", (30,30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,0,0), 2)
                cv2.putText(bgr, f"FPS: {stream_fps.get_fps():.1f}", (30,30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,0,0), 2)
                cv2.putText(bgr, f"Cloud status: {connection_status}", (30,60), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,0,0), 2)

                ret, jpeg_tmp = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])

                if ret:
                    jpeg_bytes = jpeg_tmp.tobytes()
                    with state.detect_lock:
                        state.detect_counter += 1
                        state.latest_annotated_jpeg = jpeg_bytes

                    detector_fps.tick()
                else:
                    logger.error("Couldn't compress jpeg")

            except (KeyboardInterrupt, SystemExit):
                break

            except Exception as e:
                logger.error(f"Detected error: {e}")
                time.sleep(0.05)
    finally:
        session.close()
        logger.info("Detector stopped")

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

            while not shutdown_event.is_set():
                try:
                    with state.detect_lock:
                        if state.detect_counter == last_seen:
                            shutdown_event.wait(0.01)
                            continue

                        jpeg = state.latest_annotated_jpeg
                        if jpeg is None:
                            shutdown_event.wait(0.01)
                            continue

                        last_seen = state.detect_counter

                    self.wfile.write(b'--frame\r\n')
                    self.wfile.write(b'Content-Type: image/jpeg\r\n')
                    self.wfile.write(f'Content-Length: {len(jpeg)}\r\n'.encode())
                    self.wfile.write(b'\r\n')
                    self.wfile.write(jpeg)
                    self.wfile.write(b'\r\n')

                    stream_fps.tick()

                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception as e:
                    logger.error(f"[http] stream error: {e}")
        else:
            self.send_error(404)



def signal_handler(signum, frame):
    logger.info(f"Received signal {signum}, initiating shutdown...")
    shutdown_event.signal()

def main():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    logger.info("Waiting for frame source at /dev/shm/frame.raw ...")

    while not os.path.exists(FRAME_PATH):
        if shutdown_event.is_set():
            logger.info("Shutdown requested, exiting")
            return
        time.sleep(0.1)

    logger.info("Frame source detected, starting threads...")

    # threading.Thread(target=encoder, args=[logger.getChild("encoder")], daemon=True).start()
    # threading.Thread(target=detector, args=[logger.getChild("detector")], daemon=True).start()

    encoder_thread = threading.Thread(
        target=encoder,
        args=[logger.getChild("encoder"), state, shutdown_event],
        name="encoder",
        daemon=False
    )
    encoder_thread.start()
    time.sleep(0.1)

    detector_thread = threading.Thread(
        target=detector,
        args=[logger.getChild("detector"), state, shutdown_event],
        name="detector",
        daemon=False
    )
    detector_thread.start()
    time.sleep(0.2)

    try:
        with socketserver.ThreadingTCPServer(('', 8080), Handler) as srv:
            srv.allow_reuse_address = True
            srv.daemon_threads = True
            srv.timeout = 1
            logger.info("Server started at port 8080")

            while not shutdown_event.is_set():
                srv.handle_request()

    except (KeyboardInterrupt, SystemExit):
        pass
    except Exception as e:
        logger.error(f"Server error: {e}")
    finally:
        logger.info("Initiating shutdown")
        shutdown_event.signal()

        logger.info("Waiting for encoder thread")
        encoder_thread.join(timeout=2)

        logger.info("Waiting for detector thread")
        detector_thread.join(timeout=4)

        logger.info(f"Final stats - Encoder: {encoder_fps.get_fps():.1f} FPS, "
                    f"Detector: {detector_fps.get_fps():.1f} FPS, "
                    f"Stream: {stream_fps.get_fps():.1f} FPS")
        logger.info("Shutdown complete")


if __name__ == "__main__":
    main()