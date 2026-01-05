import cv2
import os
import config
from pathlib import Path

def preprocess_images():
    # Đảm bảo thư mục tồn tại
    config.ensure_directories()
    
    raw_files = list(config.RAW_IMAGES_DIR.glob("*"))
    print(f"--> Tìm thấy {len(raw_files)} ảnh trong thư mục Raw.")

    count = 0
    for file_path in raw_files:
        if file_path.suffix.lower() in ['.jpg', '.jpeg', '.png', '.bmp']:
            try:
                # Đọc ảnh
                img = cv2.imread(str(file_path))
                if img is None:
                    continue
                
                # Resize ảnh về kích thước config (640x640)
                img_resized = cv2.resize(img, (config.IMG_SIZE, config.IMG_SIZE))
                
                # Lưu vào thư mục processed
                # Giữ nguyên tên file
                save_path = config.PROCESSED_DIR / file_path.name
                cv2.imwrite(str(save_path), img_resized)
                count += 1
            except Exception as e:
                print(f"Lỗi xử lý file {file_path.name}: {e}")

    print(f"--> Đã xử lý xong {count} ảnh. Kết quả lưu tại: {config.PROCESSED_DIR}")
    print("BƯỚC TIẾP THEO: Hãy dùng LabelImg để gán nhãn cho các ảnh trong thư mục 'processed'.")

if __name__ == "__main__":
    preprocess_images()