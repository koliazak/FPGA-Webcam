import sys
import http.server
import socketserver
import numpy as np
import cv2
import os
import time
import threading


W, H = 640, 480
SOBEL_EN = True
FRAME_SIZE = W * H * 2
FRAME_L = '/dev/shm/frame_l'
FRAME_R = '/dev/shm/frame_r'
DEFAULT_PORT = 8080
shift_lock = threading.Lock()
sobel_lock = threading.Lock()


THRESH = 10               # intencity threshhold (6 bit, 0-63)
GAIN   = 4                # increading for visuality
SHIFT_Y, SHIFT_X = 0, 0

latest_jpeg = None
jpeg_lock = threading.Lock()
frame_ready = threading.Event()
clients = 0
clients_lock = threading.Lock()


def load(path):
    with open(path, 'rb') as f:
        return f.read()

def compute_diff() -> bytes | None:
    global SHIFT_X, SHIFT_Y, SOBEL_EN
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
    local_SHIFT_X, local_SHIFT_Y = 0,0
    with shift_lock:
        if SHIFT_Y or SHIFT_X:
            local_SHIFT_X = SHIFT_X
            local_SHIFT_Y = SHIFT_Y
    gb = np.roll(gb, (local_SHIFT_Y, local_SHIFT_X), axis=(0, 1))

    d = np.abs(ga.astype(np.int16) - gb.astype(np.int16))
    d = np.where(d < THRESH, 0, d * GAIN).astype(np.uint8)

    d = cv2.rotate(d, cv2.ROTATE_90_COUNTERCLOCKWISE)
    d = cv2.flip(d,1)

    with sobel_lock:
        local_SOBEL_EN = SOBEL_EN

    if local_SOBEL_EN:
        sobelx = cv2.Sobel(d, cv2.CV_32F, 1, 0, ksize=3)
        sobely = cv2.Sobel(d, cv2.CV_32F, 0, 1, ksize=3)

        sobel = cv2.magnitude(sobelx, sobely)
        d_edges = cv2.convertScaleAbs(sobel)

        ret, jpeg = cv2.imencode('.jpg', d_edges, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
        return jpeg.tobytes() if ret else None

    else:
        ret, jpeg = cv2.imencode('.jpg', d, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
        return jpeg.tobytes() if ret else None        


def encoder():
    global latest_jpeg
    last_l = last_r = 0

    while True:
        with clients_lock:
           if clients == 0:
               time.sleep(0.1)
               continue
        try:
            st_l, st_r = os.stat(FRAME_L), os.stat(FRAME_R)
            if st_l.st_mtime != last_l and st_r.st_mtime != last_r:
                last_l = st_l.st_mtime
                last_r = st_r.st_mtime

                t1 = time.perf_counter()
                jpeg = compute_diff()
                t2 = time.perf_counter()
                #print(f"time for computing diff: {t2-t1:.3f}")

                if jpeg:
                    with jpeg_lock:
                        latest_jpeg = jpeg
            time.sleep(0.015)
        except FileNotFoundError:
            time.sleep(0.1)
        except Exception as e:
            print(f"[encoder] {e}")
            time.sleep(0.1)



HTML = b'''<!DOCTYPE html>
<html><body style="background:#111;text-align:center;">
<img src="/video" width="480" height="640" style="border:2px solid #444;">
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
            with clients_lock:
                clients += 1
            try:
                self.send_response(200)
                self.send_header('Content-Type',
                    'multipart/x-mixed-replace; boundary=frame')
                self.end_headers()
                while True:
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
                pass
            finally:
                with clients_lock:
                    clients -= 1
        else:
            self.send_error(404)


def run_server(port):
    """Runs HTTP-Server in background"""
    socketserver.TCPServer.allow_reuse_address = True

    with socketserver.ThreadingTCPServer(('0.0.0.0', port), Handler) as srv:
        print(f"\n[Server] Stream started: http://<board-ip>:{port}/video")
        srv.serve_forever()

def auto_calibrate():
    global SHIFT_X, SHIFT_Y

    raw_l = load(FRAME_L)
    raw_r = load(FRAME_R)

    if len(raw_l) != FRAME_SIZE or len(raw_r) != FRAME_SIZE:
        print(f"[AutoCalib] Failed, try again")
        return None

    img_l = np.frombuffer(raw_l, dtype=np.uint16).reshape((H, W))
    img_r = np.frombuffer(raw_r, dtype=np.uint16).reshape((H, W)).astype(np.float32)


    # take left center part as a reference
    h, w = img_l.shape
    crop_h, crop_w = h // 2, w // 2
    y1, x1 = h // 4, w // 4
    template = img_l[y1:y1+crop_h, x1:x1+crop_w].astype(np.float32)


    res = cv2.matchTemplate(img_r, template, cv2.TM_SQDIFF)
    _, _, min_loc, _ = cv2.minMaxLoc(res)
    with shift_lock:
        SHIFT_Y = y1 - min_loc[1]
        SHIFT_X = x1 - min_loc[0]
        print(f"[AutoCalib] Success, new shifts are: {SHIFT_X=}, {SHIFT_Y=}")

def print_menu():
    print("\n--- Interactive Menu ---")
    print("Commands:")
    print("  help         - print this menu")
    print("  set <x> <y>  - manually set offsets (for example: set 10 -2)")
    print("  auto         - launch autocalibration")
    print("  show         - show current offset")
    print("  sobel        - toggle Sobel filter")
    print("  exit         - exit program\n")


if __name__ == '__main__':

    port = DEFAULT_PORT
    if len(sys.argv) >= 3:
        p = sys.argv[2]
        if not p.isdigit() or int(p) < 0:
            print("Invalid port. Exiting...")
            exit(1)
        port = int(p)

    threading.Thread(target=encoder, daemon=True).start()
    threading.Thread(target=run_server, args=[port], daemon=True).start()

    time.sleep(0.5)


    print_menu()
    while True:
        try:
            cmd = input("> ").strip().split()
            if not cmd:
                continue
            action = cmd[0].lower()

            match action:
                case "help":
                    print_menu()
                case "set":
                    if len(cmd) != 3:
                        print("wrong arguments! Usage: set <shiftX> <shiftY>")
                        continue
                    with shift_lock:
                        SHIFT_X = int(cmd[1])
                        SHIFT_Y = int(cmd[2])
                    print(f"Success: {SHIFT_X=} {SHIFT_Y}")
                case "auto":
                    auto_calibrate()
                case "show":
                    with shift_lock:
                        print(f"Current shifts are: {SHIFT_X=} {SHIFT_Y}")
                case "exit":
                    print("Exiting...")
                    break
                case "sobel":
                    
                    with sobel_lock:
                        SOBEL_EN = not SOBEL_EN
                        print(f"Sobel filter status: {SOBEL_EN}")
                case _:
                    print("Unknown command or wrong arguments. Use help for list of available commands.")

        except KeyboardInterrupt:
            print("Exiting...")
            break
        except Exception as e:
            print(f"Unexpected error: {e}")
