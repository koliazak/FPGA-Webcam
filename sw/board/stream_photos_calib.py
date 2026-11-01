import sys
import http.server
import socketserver
import numpy as np
import cv2
import os
import time
import threading


W, H = 640, 480
FRAME_SIZE = W * H * 2
FRAME_L = '/dev/shm/frame_l'
FRAME_R = '/dev/shm/frame_r'
DEFAULT_PORT = 8080
SAVE_DIR = './calib_photos'
save_counter = 0
save_lock = threading.Lock()


latest_jpeg_l, latest_jpeg_r = None, None
jpeg_lock = threading.Lock()
frame_ready = threading.Event()
clients_l, clients_r = 0, 0
clients_lock = threading.Lock()
clients_raw_l, clients_raw_r = 0, 0


def load(path):
    with open(path, 'rb') as f:
        return f.read()

def save_snapshot():
    global save_counter
    raw_l = load(FRAME_L)
    raw_r = load(FRAME_R)
    if len(raw_l) != FRAME_SIZE or len(raw_r) != FRAME_SIZE:
        return None

    os.makedirs(SAVE_DIR, exist_ok=True)
    with save_lock:
        save_counter += 1
        n = save_counter

    for suffix, data in (('_L.raw', raw_l), ('_R.raw', raw_r)):
        path = f'{SAVE_DIR}/calib_{n:03d}{suffix}'
        tmp = path + '.tmp'
        with open(tmp, 'wb') as f:
            f.write(data)
        os.rename(tmp, path)

    with jpeg_lock:
        jpg_l, jpg_r = latest_jpeg_l, latest_jpeg_r
    for suffix, jpg in (('_L.jpg', jpg_l), ('_R.jpg', jpg_r)):
        if jpg:
            with open(f'{SAVE_DIR}/calib_{n:03d}{suffix}', 'wb') as f:
                f.write(jpg)

    print(f"[save] pair #{n} -> {SAVE_DIR}/calib_{n:03d}_*.*")
    return n


def render():
    global SHIFT_X, SHIFT_Y, SOBEL_EN
    raw_l = load(FRAME_L)
    raw_r = load(FRAME_R)

    if len(raw_l) != FRAME_SIZE or len(raw_r) != FRAME_SIZE:
        return None


    
    l8 = np.frombuffer(raw_l, np.uint8).reshape(H,W*2)
    r8 = np.frombuffer(raw_r, np.uint8).reshape(H,W*2)
    gl  = l8[:, 0::2]
    gr  = r8[:, 0::2]


    ret_l, jpeg_l = cv2.imencode('.jpg', gl, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
    ret_r, jpeg_r = cv2.imencode('.jpg', gr, [int(cv2.IMWRITE_JPEG_QUALITY), 95])


    if ret_l and ret_r:
        return jpeg_l.tobytes(), jpeg_r.tobytes()
    else:
        return None, None


def encoder():
    global latest_jpeg_l, latest_jpeg_r
    global clients_l, clients_r
    last_l = last_r = 0

    while True:
        with clients_lock:
           if clients_l == 0 and clients_r == 0:
               time.sleep(0.1)
               continue
        try:
            st_l, st_r = os.stat(FRAME_L), os.stat(FRAME_R)
            if st_l.st_mtime != last_l and st_r.st_mtime != last_r:
                last_l = st_l.st_mtime
                last_r = st_r.st_mtime

                jpeg_l, jpeg_r = render()
                if jpeg_l and jpeg_r:
                    with jpeg_lock:
                        latest_jpeg_l = jpeg_l
                        latest_jpeg_r = jpeg_r
            time.sleep(0.015)
        except FileNotFoundError:
            time.sleep(0.1)
        except Exception as e:
            print(f"[encoder] {e}")
            time.sleep(0.1)



HTML = b'''<!DOCTYPE html>
<html>
  <body style="background:#111;text-align:center;">
    <img src="/video_l" width="640" height="480" style="border:2px solid #444;">
    <img src="/video_r" width="640" height="480" style="border:2px solid #444;">
    <br>
    <button onclick="fetch('/save').then(r=>r.text()).then(t=>alert(t))"
            style="font-size:20px;padding:10px 20px;">&#128247; Save pair</button>
  </body>
</html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(HTML)

        elif self.path == '/video_l':
            global clients_l
            with clients_lock:
                clients_l += 1
            print("Client connected to /video_l")
            try:
                self.send_response(200)
                self.send_header('Content-Type',
                    'multipart/x-mixed-replace; boundary=frame')
                self.end_headers()
                while True:
                    with jpeg_lock:
                        jpeg = latest_jpeg_l
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
                pass
            finally:
                with clients_lock:
                    clients_l -= 1
                print("Client disconnected from /video_l")

    
        elif self.path == '/video_r':
            global clients_r
            with clients_lock:
                clients_r += 1
            print("Client connected to /video_r")
            try:
                self.send_response(200)
                self.send_header('Content-Type',
                    'multipart/x-mixed-replace; boundary=frame')
                self.end_headers()
                while True:
                    with jpeg_lock:
                        jpeg = latest_jpeg_r
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
                pass
            finally:
                with clients_lock:
                    clients_r -= 1
                print("Client disconnected from /video_r")

        
        elif self.path == '/save':
            n = save_snapshot()
            body = (f"saved pair #{n}" if n else "error: frames not ready").encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        
        else:
            self.send_error(404)


def run_server(port):
    """Runs HTTP-Server in background"""
    socketserver.TCPServer.allow_reuse_address = True

    with socketserver.ThreadingTCPServer(('0.0.0.0', port), Handler) as srv:
        print(f"\n[Server] JPEG Streams: http://<board-ip>:{port}/video_l | /video_r")
        print(f"[Server] RAW Streams:  http://<board-ip>:{port}/raw_l | /raw_r")
        srv.serve_forever()


if __name__ == '__main__':

    port = DEFAULT_PORT
    if len(sys.argv) >= 2:
        p = sys.argv[1]
        if not p.isdigit() or int(p) < 0:
            print("Invalid port. Exiting...")
            exit(1)
        port = int(p)

    threading.Thread(target=encoder, daemon=True).start()
    run_server(port)
