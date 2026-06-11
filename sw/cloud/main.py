import uvicorn
import numpy as np
from typing import Annotated
from fastapi import FastAPI, File, UploadFile
from ultralytics import YOLO
import cv2
import time
import logging


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - [%(name)s] - %(message)s",
    handlers=[
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)


model = YOLO("yolo11n_ncnn_model", task="detect")
app = FastAPI()


@app.get("/ping")
async def health_check():
    return {
        "status": "online",
        "system": "Detect Objects Server",
        "message": "Welcome! Use /docs for API documentation."
    }

@app.post("/detect/")
async def detect(file: Annotated[UploadFile, File(...)]):
    contents = await file.read()

    nparr = np.frombuffer(contents, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if img is None:
        return {"error": "Could not decode image"}

    start = time.time()

    results = model(img)
    logger.info(f"Time: {(time.time() - start):.2f}s")

    response = {"coordinates": []}

    for box in results[0].boxes.xyxy:
        response["coordinates"].append(box.tolist())

    return response

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=False
    )
