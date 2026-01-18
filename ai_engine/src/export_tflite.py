import os
import shutil
import sys
from ultralytics import YOLO

# Import cấu hình từ file config.py (vì file này nằm cùng thư mục src)
try:
    import config
except ImportError:
    # Xử lý trường hợp chạy sai thư mục, thêm đường dẫn hiện tại vào sys.path
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    import config

def export_model():
    print("--- BẮT ĐẦU QUÁ TRÌNH EXPORT TFLITE ---")

    # 1. Xác định đường dẫn file best.pt
    # Dựa trên train_yolo.py: project=output_dir, name='yolo_run'
    # Đường dẫn sẽ là: models/trained/yolo_run/weights/best.pt
    input_model_path = config.TRAINED_DIR / 'yolo_run' / 'weights' / 'best.pt'

    if not os.path.exists(input_model_path):
        print(f"LỖI: Không tìm thấy file trọng số tại: {input_model_path}")
        print("Gợi ý: Hãy chắc chắn bạn đã chạy 'train_yolo.py' thành công trước.")
        return

    print(f"Đang tải model từ: {input_model_path}")
    
    try:
        # 2. Load model YOLO
        model = YOLO(str(input_model_path))

        # 3. Thực hiện Export
        # format='tflite': Chuyển sang định dạng TensorFlow Lite
        # int8=False: Sử dụng Float32 (mặc định) để giữ độ chính xác tốt nhất cho SafeVision ban đầu
        # imgsz=640: Kích thước ảnh đầu vào (khớp với config.IMG_SIZE)
        print("Đang chuyển đổi sang TFLite... (Quá trình này có thể mất vài phút)")
        
        # Hàm export sẽ trả về đường dẫn tới file kết quả
        exported_path = model.export(format='tflite', imgsz=config.IMG_SIZE)
        
        print(f"Export thành công! File gốc được tạo tại: {exported_path}")

        # 4. Di chuyển file vào thư mục models/exported để dễ quản lý
        # Lưu ý: Ultralytics thường export ra file 'best_float32.tflite' hoặc nằm trong folder
        
        # Đảm bảo thư mục đích tồn tại
        if not os.path.exists(config.EXPORTED_DIR):
            os.makedirs(config.EXPORTED_DIR)
            print(f"Đã tạo thư mục: {config.EXPORTED_DIR}")

        # Xác định tên file đích
        destination_file = config.EXPORTED_DIR / "yolov8n_safevision.tflite"
        
        # exported_path có thể là string, ta copy file đó sang đích
        shutil.copy(exported_path, destination_file)
        
        print(f"\n--- HOÀN TẤT ---")
        print(f"File TFLite đã sẵn sàng tại: {destination_file}")
        print("Bạn hãy copy file này vào thư mục 'assets/models/' của dự án Flutter.")

    except Exception as e:
        print(f"\n--- CÓ LỖI XẢY RA KHI EXPORT ---")
        print(e)
        print("Gợi ý: Kiểm tra xem đã cài đặt tensorflow chưa (pip install tensorflow).")

if __name__ == "__main__":
    export_model()