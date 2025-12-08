.PHONY: setup run docker clean test

setup:
	@echo "Setting up environment..."
	python3 -m pip install --upgrade pip
	python3 -m pip install -r requirements.txt
	@echo "Initializing database..."
	python3 -c "from scripts.process_ocr import init_db; init_db()"
	@echo "Checking for Tesseract OCR installation..."
	if ! command -v tesseract &> /dev/null; then \
		echo "Tesseract OCR is not installed. Please install it manually based on your OS:"; \
		echo "  - For Termux (Android): pkg install tesseract"; \
		echo "  - For Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y tesseract-ocr tesseract-ocr-eng"; \
		echo "  - For macOS: brew install tesseract"; \
		echo "  - For Windows: Download from https://tesseract-ocr.github.io/tessdoc/Installation.html"; \
		echo "Please install Tesseract and then re-run this setup step, or continue if you are using Docker."; \
	else \
		echo "Tesseract OCR is already installed."; \
	fi

run:
	@echo "Starting Langflow..."
	langflow --log-level info --host 0.0.0.0 --port 7860

docker:
	@echo "Building and running Docker containers..."
	docker compose up --build -d

clean:
	@echo "Cleaning up..."
	find . -name "__pycache__" -exec rm -rf {} +
	rm -f database/ocr_data.db
	rm -rf uploads/processed/* uploads/failed/*
	@echo "Cleanup complete."

test:
	@echo "Running tests..."
	python scripts/process_ocr.py
	@echo "Checking database for test results..."
	sqlite3 database/ocr_data.db "SELECT * FROM ocr_results ORDER BY id DESC LIMIT 1;"
