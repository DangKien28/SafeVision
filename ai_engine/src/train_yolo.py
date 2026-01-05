import shutil
import os
from ultralytics import YOLO

# Import file cấu hình (giả sử train_yolo.py nằm cùng cấp với config.py)
# Nếu config.py nằm trong thư mục src, hãy đổi thành: from src import config
import config 

def main():
    # --- 1. CHUẨN BỊ MÔI TRƯỜNG ---
    print("🛠️ Đang khởi tạo các thư mục cần thiết...")
    config.ensure_directories()

    # --- 2. QUẢN LÝ MODEL PRETRAINED ---
    model_name = 'yolov8n.pt'
    # Kết hợp đường dẫn từ config (dùng / để nối path trong pathlib)
    pretrained_path = config.PRETRAINED_DIR / model_name 

    print(f"🔍 Kiểm tra model pretrained tại: {pretrained_path}")

    if not pretrained_path.exists():
        print(f"⬇️ Chưa thấy model, đang tải {model_name}...")
        
        # Tải model về thư mục hiện tại (root)
        YOLO(model_name) 
        
        # Đường dẫn file vừa tải về (ở thư mục gốc chạy lệnh)
        downloaded_file = model_name 
        
        if os.path.exists(downloaded_file):
            print(f"🚚 Đang di chuyển model vào {config.PRETRAINED_DIR}...")
            # shutil.move cần tham số là string hoặc path-like object
            shutil.move(str(downloaded_file), str(pretrained_path))
        else:
            print("⚠️ Không tìm thấy file tải về ở root. Có thể YOLO đã cache chỗ khác.")
    else:
        print("✅ Đã có sẵn model pretrained.")

    # --- 3. KIỂM TRA FILE DATASET.YAML ---
    if not config.YAML_PATH.exists():
        print(f"❌ Lỗi nghiêm trọng: Không tìm thấy file {config.YAML_PATH}")
        print("👉 Vui lòng kiểm tra lại file dataset.yaml trong thư mục data.")
        return

    # --- 4. HUẤN LUYỆN (TRAINING) ---
    print("🚀 Đang load model để training...")
    # Load model từ đường dẫn pretrained
    model = YOLO(str(pretrained_path)) 

    print(f"🔥 Bắt đầu training với cấu hình: {config.YAML_PATH}")
    
    # Bắt đầu train
    # Lưu ý: Convert các biến Path của config sang string (str) để đảm bảo tương thích tốt nhất
    results = model.train(
        data=str(config.YAML_PATH),   # Đường dẫn file data.yaml
        epochs=5,                     # Số epoch (vòng lặp)
        imgsz=config.IMG_SIZE,        # Kích thước ảnh từ config
        project=str(config.TRAINED_DIR), # Lưu kết quả vào folder trained
        name='yolo_run',              # Tên folder con
        exist_ok=True                 # Ghi đè nếu đã tồn tại
    )

    print("------------------------------------------------")
    print(f"✅ Training hoàn tất!")
    print(f"📂 Kết quả được lưu tại: {config.TRAINED_DIR / 'yolo_run'}")
    print("------------------------------------------------")

if __name__ == '__main__':
    main()