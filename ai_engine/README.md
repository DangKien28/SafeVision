1. Các ảnh chỉ là minh họa

raw_images: ảnh gốc thu thập được
processed: ảnh đã qua xử lý (resize, augment)
dataset.yaml: File cấu hình đường dẫn data cho YOLO
train: tập huấn luyện
validation: tập kiểm thử
test: tập test thực tế
models: Nơi lưu trữ các file mô hình
notebooks: Jupyter Notebook để thử nghiệm nhanh
config.py: các cấu hình (hyperparameters, path)
data_preprocessing.py: script xử lý ảnh, chia tập tran/validation
train_yolo.py: script chính để train model
evaluate.py: script đánh giá độ chính xác (mAP)
export_tflite.py: script convert từ .pt sang .tflite
requirements.txt: các thư viện cần thiết

README.md: Hướng dẫn cách train và export model (ở đây chỉ làm rõ nội dung các folder và file, hướng dẫn sẽ thêm vào sau)