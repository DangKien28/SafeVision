import math
from PIL import Image, ImageOps, ImageStat, ImageEnhance, ImageFilter

class YoloPreprocessor:
    def __init__(self, target_size=(640, 640), padding_color=(114, 114, 114)):
        """
        Khởi tạo bộ xử lý ảnh cho YOLO.
        :param target_size: Kích thước mong muốn (width, height), bội số của 32.
        :param padding_color: Màu nền padding (YOLO thường dùng màu xám 114).
        """
        self.target_size = target_size
        self.padding_color = padding_color

    def _letterbox_image(self, image):
        """
        1. Kích thước & Tỷ lệ: Resize giữ tỷ lệ và thêm padding (Letterbox).
        """
        iw, ih = image.size
        w, h = self.target_size
        
        # Tính tỷ lệ scale để ảnh vừa khít khung mà không bị méo
        scale = min(w / iw, h / ih)
        nw = int(iw * scale)
        nh = int(ih * scale)

        # Resize ảnh gốc
        image = image.resize((nw, nh), Image.Resampling.BICUBIC)
        
        # Tạo ảnh nền mới (màu xám)
        new_image = Image.new('RGB', self.target_size, self.padding_color)
        
        # Dán ảnh đã resize vào chính giữa
        paste_coords = ((w - nw) // 2, (h - nh) // 2)
        new_image.paste(image, paste_coords)
        
        return new_image

    def _convert_color_space(self, image):
        """
        2. Không gian màu: Chuyển về RGB 8-bit. Xử lý kênh Alpha.
        """
        # Nếu ảnh có kênh Alpha (Transparency), thay nền trong suốt bằng màu đen hoặc trắng
        if image.mode in ('RGBA', 'LA'):
            background = Image.new('RGB', image.size, (255, 255, 255)) # Nền trắng
            # Paste ảnh gốc lên nền trắng dựa trên kênh Alpha
            background.paste(image, mask=image.split()[-1]) 
            return background
        
        # Chuyển đổi các dạng khác (Grayscale, CMYK...) về RGB
        if image.mode != 'RGB':
            return image.convert('RGB')
        
        return image

    def _adjust_brightness_contrast(self, image):
        """
        3. Độ sáng & Độ tương phản: Đưa pixel về vùng an toàn.
        """
        # Chuyển sang Grayscale tạm thời để tính toán thống kê
        stat = ImageStat.Stat(image.convert('L'))
        mean_brightness = stat.mean[0] # Giá trị trung bình pixel (0-255)

        # Xử lý Độ sáng (Brightness) - Mục tiêu: 80 - 150
        if mean_brightness < 80:
            # Ảnh tối -> Tăng sáng (Gamma correction giả lập)
            enhancer = ImageEnhance.Brightness(image)
            image = enhancer.enhance(1.2) # Tăng 20%
            print(f"-> Đã tăng độ sáng (Gốc: {mean_brightness:.1f})")
        elif mean_brightness > 180:
            # Ảnh quá cháy -> Giảm sáng
            enhancer = ImageEnhance.Brightness(image)
            image = enhancer.enhance(0.8) # Giảm 20%
            print(f"-> Đã giảm độ sáng (Gốc: {mean_brightness:.1f})")

        # Xử lý Độ tương phản (Contrast) - Dùng AutoContrast an toàn
        # CLAHE không có sẵn trong PIL, ta dùng AutoContrast với cutoff nhẹ
        image = ImageOps.autocontrast(image, cutoff=1) 
        
        return image

    def _check_sharpness_and_noise(self, image):
        """
        4. Độ nét & Nhiễu: Kiểm tra biên cạnh và lọc nhiễu.
        """
        # Kiểm tra độ mờ bằng cách tìm biên (Edges)
        # Chuyển sang ảnh xám -> Lọc biên -> Tính phương sai (Variance)
        gray = image.convert('L')
        edges = gray.filter(ImageFilter.FIND_EDGES)
        stat = ImageStat.Stat(edges)
        variance = stat.var[0] # Phương sai của Laplacian giả lập

        # Ngưỡng mờ (Threshold) phụ thuộc dataset, ví dụ < 500 với PIL filter là mờ
        # Lưu ý: Số này khác với cv2.Laplacian, cần tinh chỉnh thực tế
        if variance < 150: 
            print(f"-> Cảnh báo: Ảnh có thể bị mờ (Variance: {variance:.1f}). Đang làm nét...")
            enhancer = ImageEnhance.Sharpness(image)
            image = enhancer.enhance(1.5) # Làm nét

        # Khử nhiễu nhẹ (Dùng MedianFilter tốt cho nhiễu muối tiêu)
        # Chỉ áp dụng nếu cần thiết, ở đây ta áp dụng bộ lọc nhẹ để an toàn
        # image = image.filter(ImageFilter.MedianFilter(size=3)) 
        
        return image

    def process(self, image_path, output_path):
        try:
            print(f"--- Đang xử lý: {image_path} ---")
            img = Image.open(image_path)

            # Bước 1: Xử lý màu sắc & Bit depth trước
            img = self._convert_color_space(img)

            # Bước 2: Resize Letterbox (Quan trọng nhất cho YOLO)
            img = self._letterbox_image(img)

            # Bước 3: Cân bằng sáng/tương phản
            img = self._adjust_brightness_contrast(img)

            # Bước 4: Xử lý độ nét
            img = self._check_sharpness_and_noise(img)

            # Lưu kết quả
            img.save(output_path, quality=95)
            print(f"Hoàn tất! Đã lưu tại: {output_path} (Size: {img.size})\n")
            
        except Exception as e:
            print(f"Lỗi khi xử lý {image_path}: {e}")

