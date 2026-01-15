import os
import yaml
from ultralytics import YOLO

# --- Cấu hình đường dẫn Tuyệt Đối ---
# Lấy thư mục hiện tại (src)
current_dir = os.path.dirname(os.path.abspath(__file__))
# Lấy thư mục gốc (ai_engine)
base_dir = os.path.dirname(current_dir)

# Đường dẫn đến thư mục chứa data (quan trọng để sửa lỗi path)
data_dir = os.path.join(base_dir, 'data')

# Các đường dẫn file
dataset_yaml_path = os.path.join(data_dir, 'dataset.yaml')
pretrained_model = os.path.join(base_dir, 'models', 'pretrained', 'yolov8n.pt')
output_dir = os.path.join(base_dir, 'models', 'trained')

def fix_dataset_yaml():
    """
    Hàm này tự động sửa file dataset.yaml để chèn đường dẫn tuyệt đối (path).
    Giúp YOLO tìm thấy ảnh bất kể chạy từ đâu.
    """
    print(f"--- Đang cấu hình lại dataset.yaml ---")
    
    if not os.path.exists(dataset_yaml_path):
        print(f"Lỗi: Không tìm thấy file {dataset_yaml_path}")
        return False

    try:
        # 1. Đọc nội dung hiện tại
        with open(dataset_yaml_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            if config is None: config = {}

        # 2. Cập nhật đường dẫn tuyệt đối
        # 'path' là từ khóa YOLO dùng để xác định thư mục gốc của dataset
        config['path'] = data_dir 
        config['train'] = 'train/images'
        config['val'] = 'validation/images'
        
        # (Nếu file cũ chưa có names/nc, đảm bảo giữ nguyên nếu đã có, hoặc thêm mẫu nếu thiếu)
        # Ở đây ta chỉ sửa path, giữ nguyên các cấu hình class (names) của bạn

        # 3. Ghi đè lại file yaml
        with open(dataset_yaml_path, 'w', encoding='utf-8') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
            
        print(f"Đã cập nhật đường dẫn tuyệt đối vào: {dataset_yaml_path}")
        return True
    except Exception as e:
        print(f"Lỗi khi sửa file YAML: {e}")
        return False

def train_model():
    # Bước 1: Sửa lỗi đường dẫn dataset trước
    if not fix_dataset_yaml():
        return

    print(f"--- Bắt đầu huấn luyện ---")
    print(f"Dataset: {dataset_yaml_path}")
    print(f"Output: {output_dir}")

    # Bước 2: Khởi tạo model
    model = YOLO(pretrained_model)

    # Bước 3: Huấn luyện
    try:
        results = model.train(
            data=dataset_yaml_path,
            epochs=50,
            imgsz=640,
            batch=16,
            project=output_dir,
            name='yolo_run',
            exist_ok=True,
            patience=10,
            device='cpu' # Chip thường
        )

        print("--- Huấn luyện hoàn tất ---")
        best_weight = os.path.join(output_dir, 'yolo_run', 'weights', 'best.pt')
        print(f"Mô hình tốt nhất: {best_weight}")
        
    except Exception as e:
        print("\n--- CÓ LỖI XẢY RA KHI TRAIN ---")
        print(e)
        print("Gợi ý: Hãy kiểm tra xem thư mục 'ai_engine/data/train/images' có chứa ảnh không.")

if __name__ == '__main__':
    train_model()