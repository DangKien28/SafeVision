import numpy as np
import tensorflow as tf
import cv2
import os

# --- CẤU HÌNH ---
# Đường dẫn đến file tflite vừa xuất (bạn sửa lại tên file nếu khác)
MODEL_PATH = "../models/exported/best_float32.tflite" 
IMAGE_PATH = "../data/test/images/ghe.png" # Lấy tạm 1 ảnh test có sẵn

def verify():
    # 1. Load Model TFLite
    print(f"Loading model: {MODEL_PATH}...")
    if not os.path.exists(MODEL_PATH):
        print("LỖI: Không tìm thấy file model!")
        # Thử tìm file có đuôi .tflite bất kỳ trong thư mục exported
        exported_dir = os.path.dirname(MODEL_PATH)
        files = [f for f in os.listdir(exported_dir) if f.endswith('.tflite')]
        if files:
            print(f"-> Tìm thấy file khác: {files[0]}. Hãy sửa lại MODEL_PATH.")
        return

    interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
    interpreter.allocate_tensors()

    # 2. Lấy thông tin đầu vào/đầu ra
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    
    input_shape = input_details[0]['shape'] # Thường là [1, 640, 640, 3]
    print(f"Input Shape yêu cầu: {input_shape}")

    # 3. Chuẩn bị ảnh đầu vào
    img = cv2.imread(IMAGE_PATH)
    if img is None:
        print("LỖI: Không đọc được ảnh test.")
        return

    # Resize ảnh về đúng kích thước model yêu cầu (640x640)
    img_resized = cv2.resize(img, (input_shape[1], input_shape[2]))
    
    # Chuẩn hóa ảnh: YOLO thường training với pixel 0-1 (chia cho 255)
    # Nếu model là float32
    input_data = np.array(img_resized, dtype=np.float32) / 255.0
    input_data = np.expand_dims(input_data, axis=0) # Thêm chiều batch -> [1, 640, 640, 3]

    # 4. Chạy Inference (Dự đoán)
    interpreter.set_tensor(input_details[0]['index'], input_data)
    interpreter.invoke()

    # 5. Lấy kết quả
    output_data = interpreter.get_tensor(output_details[0]['index'])
    print("\n--- KẾT QUẢ KIỂM TRA ---")
    print(f"Output Shape: {output_data.shape}")
    # Output của YOLOv8 thường là [1, 5, 8400] (hoặc [1, 84, 8400] tùy số class)
    # Trong đó: 8400 là số boxes dự đoán, 5 = (x, y, w, h, confidence)
    
    if output_data.shape[1] > 0:
        print("✅ Model chạy THÀNH CÔNG! Đã ra kết quả dự đoán.")
    else:
        print("⚠️ Model chạy được nhưng không ra output mong muốn.")

if __name__ == "__main__":
    verify()