import os
from pathlib import Path

# Lấy đường dẫn gốc của dự án (thư mục ai_engine)
# File này nằm trong src/, nên parent của nó là ai_engine
BASE_DIR = Path(__file__).resolve().parent.parent

# Các thư mục dữ liệu
DATA_DIR = BASE_DIR / "data"
RAW_IMAGES_DIR = DATA_DIR / "raw_images"
PROCESSED_DIR = DATA_DIR / "processed"

# Thư mục Train/Test/Val theo cấu trúc bạn cung cấp
TRAIN_DIR = DATA_DIR / "train"
VAL_DIR = DATA_DIR / "validation"
TEST_DIR = DATA_DIR / "test"

# File cấu hình YAML cho YOLO
YAML_PATH = DATA_DIR / "dataset.yaml"

# Các thư mục Models
MODELS_DIR = BASE_DIR / "models"
PRETRAINED_DIR = MODELS_DIR / "pretrained"
TRAINED_DIR = MODELS_DIR / "trained"
EXPORTED_DIR = MODELS_DIR / "exported"

# Tạo các thư mục nếu chưa tồn tại (để tránh lỗi)
def ensure_directories():
    directories = [
        RAW_IMAGES_DIR, PROCESSED_DIR,
        PRETRAINED_DIR, TRAINED_DIR, EXPORTED_DIR,
        TRAIN_DIR / "images", TRAIN_DIR / "labels",
        VAL_DIR / "images", VAL_DIR / "labels",
        TEST_DIR / "images", TEST_DIR / "labels"
    ]
    for d in directories:
        d.mkdir(parents=True, exist_ok=True)

# Cấu hình tham số
IMG_SIZE = 640  # Kích thước ảnh chuẩn cho YOLOv8