import os
import sqlite3
from datetime import datetime
from PIL import Image
import pytesseract

# Ensure tesseract is installed and in your PATH
# For example, on Ubuntu: sudo apt install tesseract-ocr
# On Termux: pkg install tesseract

def init_db(db_path="database/ocr_data.db"):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS ocr_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            ocr_text TEXT,
            processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status TEXT NOT NULL
        );
    """)
    conn.commit()
    conn.close()

def save_ocr_result(filename, ocr_text, status, db_path="database/ocr_data.db"):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO ocr_results (filename, ocr_text, status) VALUES (?, ?, ?)",
        (filename, ocr_text, status)
    )
    conn.commit()
    conn.close()

def process_image(image_path):
    print(f"Processing image: {image_path}")
    init_db()

    try:
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")

        img = Image.open(image_path)
        text = pytesseract.image_to_string(img)
        print(f"OCR result for {os.path.basename(image_path)}: {text[:100]}...")

        save_ocr_result(os.path.basename(image_path), text, "success")

        processed_dir = "uploads/processed"
        os.makedirs(processed_dir, exist_ok=True)
        os.rename(image_path, os.path.join(processed_dir, os.path.basename(image_path)))
        print(f"Image moved to {processed_dir}")

        return {"status": "success", "ocr_text": text, "filename": os.path.basename(image_path)}
    except Exception as e:
        print(f"Error processing image {image_path}: {e}")
        save_ocr_result(os.path.basename(image_path), str(e), "failed")

        failed_dir = "uploads/failed"
        os.makedirs(failed_dir, exist_ok=True)
        os.rename(image_path, os.path.join(failed_dir, os.path.basename(image_path)))
        print(f"Image moved to {failed_dir}")

        return {"status": "failed", "error": str(e), "filename": os.path.basename(image_path)}

if __name__ == "__main__":
    test_image_path = "uploads/test_image.png"
    if not os.path.exists(test_image_path):
        from PIL import ImageDraw, ImageFont
        try:
            img = Image.new('RGB', (200, 50), color = (255, 255, 255))
            d = ImageDraw.Draw(img)
            try:
                fnt = ImageFont.truetype("FreeMono.ttf", 20)
                d.text((10,10), "Hello OCR", font=fnt, fill=(0,0,0))
            except IOError:
                d.text((10,10), "Hello OCR", fill=(0,0,0))
            img.save(test_image_path)
            print(f"Created dummy image at {test_image_path} for testing.")
        except Exception as e:
            print(f"Could not create dummy image: {e}. Please ensure you have Pillow and a font available, or manually place a test_image.png in 'uploads/'.")
            
    if os.path.exists(test_image_path):
        result = process_image(test_image_path)
        print(f"Test result: {result}")
    else:
        print(f"Skipping test run as {test_image_path} does not exist.")
