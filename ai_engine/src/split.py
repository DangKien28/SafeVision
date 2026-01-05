import shutil
import random
import config
from pathlib import Path

def clear_folder(folder_path):
    """Hàm dọn dẹp thư mục đích trước khi copy để tránh trùng lặp"""
    for item in folder_path.glob('*'):
        if item.is_file():
            item.unlink()

def split_dataset(train_ratio=0.7, val_ratio=0.15, test_ratio=0.15):
    # 1. Đảm bảo các thư mục tồn tại
    config.ensure_directories()

    # 2. Lấy danh sách file ảnh và file nhãn từ thư mục PROCESSED
    # Lưu ý: Chỉ lấy những ảnh có file nhãn (.txt) đi kèm để tránh lỗi khi train
    all_images = []
    
    # Các đuôi ảnh hỗ trợ
    valid_extensions = ['.jpg', '.jpeg', '.png', '.bmp']
    
    print(f"--> Đang quét dữ liệu từ: {config.PROCESSED_DIR}")
    
    files_in_processed = list(config.PROCESSED_DIR.glob("*"))
    
    for file_path in files_in_processed:
        if file_path.suffix.lower() in valid_extensions:
            # Kiểm tra xem có file .txt tương ứng không
            label_path = file_path.with_suffix('.txt')
            if label_path.exists():
                all_images.append(file_path)
            else:
                print(f"Bỏ qua {file_path.name} (Chưa gán nhãn/Không tìm thấy file .txt)")

    total_images = len(all_images)
    print(f"--> Tổng số cặp (Ảnh + Nhãn) hợp lệ: {total_images}")

    if total_images < 3:
        print("LỖI: Dữ liệu quá ít (< 3 ảnh). Không thể chia đủ cho Train, Val, Test.")
        return

    # 3. Xáo trộn ngẫu nhiên
    random.shuffle(all_images)

    # 4. Tính toán số lượng (Logic đảm bảo luôn có ít nhất 1 file)
    val_count = int(total_images * val_ratio)
    test_count = int(total_images * test_ratio)

    # BẮT BUỘC: Nếu tính ra 0 thì gán bằng 1 (để tránh lỗi thư mục rỗng)
    if val_count < 1: val_count = 1
    if test_count < 1: test_count = 1
    
    # Train nhận phần còn lại
    train_count = total_images - val_count - test_count

    # Nếu sau khi chia mà Train < 1 (trường hợp chỉ có 2 ảnh), cảnh báo
    if train_count < 1:
        print("Cảnh báo: Số lượng ảnh Train quá ít. Hãy thêm dữ liệu!")
        # Fallback: Reset về tối thiểu
        # Nếu chỉ có 3 ảnh: Train=1, Val=1, Test=1
        train_count = 1
        val_count = 1
        test_count = 1
        # Cập nhật lại list lấy đúng 3 ảnh đầu (nếu tổng < 3 đã return ở trên rồi)

    print(f"--> Kế hoạch chia: Train={train_count}, Val={val_count}, Test={test_count}")

    # 5. Chia danh sách
    train_imgs = all_images[:train_count]
    val_imgs = all_images[train_count : train_count + val_count]
    test_imgs = all_images[train_count + val_count :]

    # 6. Hàm copy file
    def copy_files(files_list, dest_root):
        # Dọn dẹp thư mục đích trước
        clear_folder(dest_root / "images")
        clear_folder(dest_root / "labels")

        count = 0
        for img_path in files_list:
            # Copy ảnh
            shutil.copy(img_path, dest_root / "images" / img_path.name)
            
            # Copy nhãn
            label_src = img_path.with_suffix('.txt')
            shutil.copy(label_src, dest_root / "labels" / label_src.name)
            count += 1
        return count

    # 7. Thực thi copy
    print("Đang copy vào thư mục Train...")
    c_train = copy_files(train_imgs, config.TRAIN_DIR)
    
    print("Đang copy vào thư mục Validation...")
    c_val = copy_files(val_imgs, config.VAL_DIR)
    
    print("Đang copy vào thư mục Test...")
    c_test = copy_files(test_imgs, config.TEST_DIR)

    print("-" * 30)
    print(f"HOÀN TẤT! Kết quả thực tế:")
    print(f"   - Train: {c_train} ảnh")
    print(f"   - Val:   {c_val} ảnh")
    print(f"   - Test:  {c_test} ảnh")
    print("Dữ liệu gốc trong 'processed' vẫn được giữ nguyên.")

if __name__ == "__main__":
    split_dataset()