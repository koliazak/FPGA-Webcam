from ultralytics import YOLO
import time

model = YOLO("yolo11n_ncnn_model")

img = input("Image: ")
start = time.time()
results = model(img)
print("Time:", time.time() - start)

boxes = results[0].boxes
for box in boxes:
    print("Coordinates: ")
    print(box.xyxy)
