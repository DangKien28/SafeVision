from ultralytics import YOLO
from flask import Flask, request, jsonify
import cv2
import numpy as np
import base64

app = Flask(__name__)

model = YOLO("models/trained/yolo_run_improved/weights/best.pt")

@app.route("/detect", methods=["POST"])
def detect():
    data = request.json
    img_base64 = data["image"]

    # decode base64 -> image
    img_bytes = base64.b64decode(img_base64)
    np_arr = np.frombuffer(img_bytes, np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

    results = model(img, conf=0.25)

    detections = []
    for r in results:
        for box in r.boxes:
            detections.append({
                "label": model.names[int(box.cls)],
                "confidence": float(box.conf),
                "x1": float(box.xyxy[0][0]),
                "y1": float(box.xyxy[0][1]),
                "x2": float(box.xyxy[0][2]),
                "y2": float(box.xyxy[0][3]),
            })

    return jsonify(detections)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
