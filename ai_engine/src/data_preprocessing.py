import os
import time
from pathlib import Path

# Import class xử lý ảnh từ file cũ (yolo_preprocess.py)
# Đảm bảo file yolo_preprocess.py nằm cùng thư mục với file này
try:
    from yolo_preprocess import YoloPreprocessor
except ImportError:
    print("LỖI: Không tìm thấy file 'yolo_preprocess.py'. Hãy đặt 2 file cùng một chỗ.")
    exit()

def xu_ly_hang_loat(input_dir, output_dir):
    """
    Hàm quét thư mục và xử lý toàn bộ ảnh.
    """
    # 1. Kiểm tra và tạo thư mục đầu ra nếu chưa có
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"Đã tạo thư mục mới: {output_dir}")

    # 2. Khởi tạo bộ xử lý (Gọi từ file cũ)
    # Bạn có thể chỉnh target_size=(640, 640) hoặc (1280, 1280) tùy ý
    processor = YoloPreprocessor(target_size=(640, 640))

    # Các đuôi file ảnh hợp lệ
    valid_extensions = ('.jpg', '.jpeg', '.png', '.bmp', '.webp')

    # Lấy danh sách file
    files = os.listdir(input_dir)
    total_files = len(files)
    count = 0

    print(f"--- Bắt đầu quét thư mục: {input_dir} ---")

    for filename in files:
        # Kiểm tra xem có phải file ảnh không
        if filename.lower().endswith(valid_extensions):
            count += 1
            
            # Tạo đường dẫn đầy đủ
            input_path = os.path.join(input_dir, filename)
            output_path = os.path.join(output_dir, f"{filename}")

            print(f"[{count}/{total_files}] Đang xử lý: {filename}...")
            
            # GỌI HÀM XỬ LÝ TỪ FILE CŨ
            processor.process(input_path, output_path)
        else:
            print(f"[Bỏ qua] File không phải ảnh: {filename}")

    print(f"\n--- HOÀN TẤT! ---")
    print(f"Đã xử lý {count} ảnh.")
    print(f"Kiểm tra kết quả tại: {output_dir}")

# ==============================================================================
# PHẦN CẤU HÌNH ĐƯỜNG DẪN (BẠN CHỈ CẦN SỬA Ở DƯỚI ĐÂY)
# ==============================================================================

if __name__ == "__main__":
    cur = Path(__file__).resolve().parent.parent
    raw_images = cur / "data" / "raw_images"
    processed = cur / "data" / "processed"
    print(raw_images)
    print(processed)
    # 1. Đường dẫn đến thư mục chứa ảnh gốc của bạn
    THU_MUC_NGUON = raw_images  # <--- [BẠN THAY ĐỔI ĐƯỜNG DẪN TẠI ĐÂY]

    # 2. Đường dẫn đến thư mục bạn muốn lưu ảnh sau khi xử lý
    THU_MUC_DICH = processed # <--- [BẠN THAY ĐỔI ĐƯỜNG DẪN TẠI ĐÂY]

    # # Chạy quy trình
    if os.path.exists(THU_MUC_NGUON):
        xu_ly_hang_loat(THU_MUC_NGUON, THU_MUC_DICH)
    else:
        print(f"Lỗi: Không tìm thấy thư mục nguồn: {THU_MUC_NGUON}")
        print("Vui lòng kiểm tra lại đường dẫn trong phần cấu hình.")