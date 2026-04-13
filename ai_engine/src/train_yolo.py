import os
import yaml
from ultralytics import YOLO

current_dir = os.path.dirname(os.path.abspath(__file__))
base_dir = os.path.dirname(current_dir)

data_dir = os.path.join(base_dir, 'data')

dataset_yaml_path = os.path.join(data_dir, 'dataset.yaml')
pretrained_model = os.path.join(base_dir, 'models', 'pretrained', 'yolov8n.pt')
output_dir = os.path.join(base_dir, 'models', 'trained')

def fix_dataset_yaml():
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

        config['path'] = data_dir 
        config['train'] = 'train/images'
        config['val'] = 'validation/images'
    
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
            epochs=150,        
            imgsz=640,
            batch=8,           
            project=output_dir,
            name='yolo_run_improved',
            exist_ok=True,
            patience=50,      
            device='cpu',    
            lr0=0.01,         
            augment=True    
        )

        print("--- Huấn luyện hoàn tất ---")
        best_weight = os.path.join(output_dir, 'yolo_run', 'weights', 'best.pt')
        print(f"Mô hình tốt nhất: {best_weight}")
        
    except Exception as e:
        print("\n--- CÓ LỖI XẢY RA KHI TRAIN ---")
        print(e)

if __name__ == '__main__':
    train_model()