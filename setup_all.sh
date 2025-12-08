#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "Starting Langflow OCR System setup..."

# Create directories
mkdir -p flows database scripts uploads/processed uploads/failed logs .github/workflows

# Create .env file from example if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    echo ""
    echo "***********************************************************************************"
    echo "* IMPORTANT: .env file created. Please open it and add your OPENAI_API_KEY if   *"
    echo "* needed for your Langflow flows.                                                 *"
    echo "* Run: nano .env                                                                  *"
    echo "***********************************************************************************"
    echo ""
fi

# Install Python dependencies
echo "Installing Python dependencies..."
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

# Initialize the database
echo "Initializing database..."
python3 -c "from scripts.process_ocr import init_db; init_db()"

# Check and install Tesseract OCR
echo "Checking for Tesseract OCR installation..."
if ! command -v tesseract &> /dev/null
then
    echo "Tesseract OCR is not installed. Please install it manually based on your OS:"
    echo "  - For Termux (Android): pkg install tesseract"
    echo "  - For Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y tesseract-ocr tesseract-ocr-eng"
    echo "  - For macOS: brew install tesseract"
    echo "  - For Windows: Download from https://tesseract-ocr.github.io/tessdoc/Installation.html"
    echo "Please install Tesseract and then re-run this script, or continue if you are using Docker."
    # Optionally, exit here if Tesseract is strictly required for local execution
    # exit 1
else
    echo "Tesseract OCR is already installed."
fi

# Create files - Ensure this part is consistent with initial generation
# flows/ocr_data_entry.json
cat <<EOF > flows/ocr_data_entry.json
{
  "name": "OCR Data Entry System",
  "description": "A Langflow flow for processing OCR data entry.",
  "nodes": [
    {
      "id": "textInput",
      "type": "Input",
      "data": {
        "text": "Please upload an image for OCR."
      }
    },
    {
      "id": "ocrProcessor",
      "type": "PythonFunction",
      "data": {
        "code": "from scripts.process_ocr import process_image\\ndef run(image_path):\\n    result = process_image(image_path)\\n    return result"
      }
    },
    {
      "id": "outputDisplay",
      "type": "Output",
      "data": {
        "text": "{ocrProcessor.result}"
      }
    }
  ],
  "edges": [
    {
      "source": "textInput",
      "target": "ocrProcessor"
    },
    {
      "source": "ocrProcessor",
      "target": "outputDisplay"
    }
  ]
}
EOF

# database/schema.sql
cat <<EOF > database/schema.sql
CREATE TABLE IF NOT EXISTS ocr_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL,
    ocr_text TEXT,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL
);
EOF

# scripts/process_ocr.py
cat <<EOF > scripts/process_ocr.py
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
EOF

# .github/workflows/deploy.yml
cat <<EOF > .github/workflows/deploy.yml
name: Deploy Langflow OCR System

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v3

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt
        sudo apt-get update
        sudo apt-get install -y tesseract-ocr tesseract-ocr-eng

    - name: Set up Docker Compose
      run: |
        docker compose pull
        docker compose build

    - name: Run Docker Compose
      run: docker compose up -d

    - name: Verify deployment (optional)
      run: |
        sleep 10
        docker compose ps
EOF

# docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  langflow:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "7860:7860"
    volumes:
      - ./flows:/app/flows
      - ./database:/app/database
      - ./scripts:/app/scripts
      - ./uploads:/app/uploads
      - ./logs:/app/logs
      - ./.env:/app/.env
    environment:
      - LANGFLOW_PORT=7860
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    command: ["langflow", "--log-level", "info", "--host", "0.0.0.0", "--port", "7860"]
    depends_on:
      - tesseract_ocr
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7860/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  tesseract_ocr:
    image: arm64v8/tesseract-ocr:latest
    command: ["tail", "-f", "/dev/null"]
EOF

# Makefile
cat <<EOF > Makefile
.PHONY: setup run docker clean test

setup:
	@echo "Setting up environment..."
	pip install -r requirements.txt
	@echo "Initializing database..."
	python -c "from scripts.process_ocr import init_db; init_db()"

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
EOF

# README_OCR.md
cat <<EOF > README_OCR.md
# OCR Data Entry System with Langflow

This project implements an OCR (Optical Character Recognition) data entry system using Langflow to create a visual pipeline for processing images and extracting text.

## Features

- **Image Upload:** Users can upload images containing text.
- **OCR Processing:** Utilizes Tesseract OCR to extract text from images.
- **Database Storage:** Stores OCR results (filename, extracted text, status) in an SQLite database.
- **Categorization:** Automatically moves processed images to 'processed/' or 'failed/' directories.
- **Langflow Integration:** A Langflow flow orchestrates the image processing.
- **Docker Support:** Easily deployable using Docker and Docker Compose.
- **GitHub Actions:** Automated deployment workflow.

## Project Structure

\`\`\`
.
├── flows/
│   └── ocr_data_entry.json          # Langflow flow definition
├── database/
│   ├── schema.sql                   # Database schema for OCR results
│   └── ocr_data.db                  # SQLite database (generated)
├── scripts/
│   └── process_ocr.py               # Python script for OCR processing and database interaction
├── uploads/
│   ├── processed/                   # Directory for successfully processed images
│   └── failed/                      # Directory for images that failed OCR
├── logs/                            # Application logs
├── .github/workflows/
│   └── deploy.yml                   # GitHub Actions workflow for deployment
├── docker-compose.yml               # Docker Compose configuration
├── Dockerfile                       # Dockerfile for the Langflow application
├── Makefile                         # Utility commands for setup, run, clean, test
├── README_OCR.md                    # This documentation file
├── .env.example                     # Example environment variables file
└── .gitignore                       # Specifies files/directories to ignore in Git
\`\`\`

## Setup and Installation

### Prerequisites

- Python 3.8+
- pip
- Langflow (
\`pip install langflow\
)
- Tesseract OCR engine (installation varies by OS, e.g., \`sudo apt install tesseract-ocr\` on Debian/Ubuntu, \`pkg install tesseract\` on Termux)
- Docker and Docker Compose (if using Docker)

### Local Setup

1.  **Clone the repository:**
    \`\`\`bash
    git clone https://github.nssuwan186-dev/langflow.git
    cd langflow
    \`\`\`

2.  **Run the setup script:**
    This script will create all necessary directories and placeholder files.
    \`\`\`bash
    bash setup_all.sh
    \`\`\`

3.  **Install Python dependencies:**
    \`\`\`bash
    pip install -r requirements.txt
    \`\`\`
    *(Note: The \`requirements.txt\` file will be created by this process with basic dependencies.)*

4.  **Set up Environment Variables:**
    Copy the example environment file and add your OpenAI API key (if you're using LLMs in your Langflow flow, though not strictly required for basic OCR).
    \`\`\`bash
    cp .env.example .env
    # Open .env with a text editor and add your OPENAI_API_KEY
    nano .env
    \`\`\`

5.  **Initialize the database:**
    \`\`\`bash
    make setup
    \`\`\`

### Running the Application

#### Local (without Docker)

\`\`\`bash
make run
\`\`\`
This will start the Langflow UI, typically accessible at \`http://localhost:7860\`.

#### Using Docker Compose

\`\`\`bash
make docker
\`\`\`
This will build the Docker images and start the containers in detached mode. Langflow will be accessible at \`http://localhost:7860\`.

## Usage

1.  **Access Langflow UI:** Open your web browser and navigate to \`http://localhost:7860\`.
2.  **Load the Flow:** Import the \`flows/ocr_data_entry.json\` file into Langflow.
3.  **Upload Image:** Interact with the flow by providing an image.
4.  **View Results:** The OCR extracted text and processing status will be displayed in the Langflow UI and stored in \`database/ocr_data.db\`.

## Testing

\`\`\`bash
make test
\`\`\`
This command will run the \`process_ocr.py\` script directly with a dummy image (if created successfully) and display the last OCR result from the database.

## Cleaning Up

To remove generated files and databases:

\`\`\`bash
make clean
\`\`\`

## Deployment

The \`.github/workflows/deploy.yml\` defines a GitHub Actions workflow to automatically deploy your Langflow OCR system on push to \`main\` or manually via workflow dispatch. Ensure your repository is correctly configured for deployment (e.g., secrets for cloud providers if deploying beyond just Docker on a server).
EOF

# .env.example
cat <<EOF > .env.example
# Example .env file
# Replace with your actual API keys or sensitive information
OPENAI_API_KEY="your_openai_api_key_here"
# Add other environment variables as needed
EOF

# .gitignore
cat <<EOF > .gitignore
# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
env/
virtualenv/
.env

# Database
*.db

# Uploads (processed images, etc.)
uploads/processed/
uploads/failed/

# Logs
logs/

# Docker
.dockerignore

# Langflow specific
.langflow/

# OS generated files
.DS_Store
.vscode/

# Build artifacts
build/
dist/
*.egg-info/

# Misc
*.zip
*.tar.gz
*.log
EOF

# Dockerfile for Langflow (needed for docker-compose build)
cat <<EOF > Dockerfile
# Use a base image that includes Python and is compatible with your architecture (ARM64 for Android/Termux)
FROM python:3.10-slim-bullseye-arm64v8

# Set working directory
WORKDIR /app

# Install system dependencies for Langflow and Tesseract
# Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Tesseract OCR and its language packs
# Ensure apt-get update is run before install
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    tesseract-ocr-eng \
    libgl1-mesa-glx \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Copy the rest of the application code
COPY . .

# Expose the port Langflow runs on
EXPOSE 7860

# Command to run Langflow (entrypoint might be better for real apps)
CMD ["langflow", "--log-level", "info", "--host", "0.0.0.0", "--port", "7860"]
EOF

# requirements.txt
cat <<EOF > requirements.txt
langflow
pytesseract
Pillow
# sqlite3 is built-in, no need to list
# Add other Python dependencies here as your Langflow flow or scripts evolve
EOF
# flows/ocr_data_entry.json
cat <<EOF > flows/ocr_data_entry.json
{
  "name": "OCR Data Entry System",
  "description": "A Langflow flow for processing OCR data entry.",
  "nodes": [
    {
      "id": "textInput",
      "type": "Input",
      "data": {
        "text": "Please upload an image for OCR."
      }
    },
    {
      "id": "ocrProcessor",
      "type": "PythonFunction",
      "data": {
        "code": "from scripts.process_ocr import process_image\ndef run(image_path):\n    result = process_image(image_path)\n    return result"
      }
    },
    {
      "id": "outputDisplay",
      "type": "Output",
      "data": {
        "text": "{ocrProcessor.result}"
      }
    }
  ],
  "edges": [
    {
      "source": "textInput",
      "target": "ocrProcessor"
    },
    {
      "source": "ocrProcessor",
      "target": "outputDisplay"
    }
  ]
}
EOF

# database/schema.sql
cat <<EOF > database/schema.sql
CREATE TABLE IF NOT EXISTS ocr_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL,
    ocr_text TEXT,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL
);
EOF

# scripts/process_ocr.py
cat <<EOF > scripts/process_ocr.py
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
EOF

# .github/workflows/deploy.yml
cat <<EOF > .github/workflows/deploy.yml
name: Deploy Langflow OCR System

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v3

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt
        sudo apt-get update
        sudo apt-get install -y tesseract-ocr tesseract-ocr-eng

    - name: Set up Docker Compose
      run: |
        docker compose pull
        docker compose build

    - name: Run Docker Compose
      run: docker compose up -d

    - name: Verify deployment (optional)
      run: |
        sleep 10
        docker compose ps
EOF

# docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  langflow:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "7860:7860"
    volumes:
      - ./flows:/app/flows
      - ./database:/app/database
      - ./scripts:/app/scripts
      - ./uploads:/app/uploads
      - ./logs:/app/logs
      - ./.env:/app/.env
    environment:
      - LANGFLOW_PORT=7860
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    command: ["langflow", "--log-level", "info", "--host", "0.0.0.0", "--port", "7860"]
    depends_on:
      - tesseract_ocr
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7860/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  tesseract_ocr:
    image: arm64v8/tesseract-ocr:latest
    command: ["tail", "-f", "/dev/null"]
EOF

# Makefile
cat <<EOF > Makefile
.PHONY: setup run docker clean test

setup:
	@echo "Setting up environment..."
	pip install -r requirements.txt
	@echo "Initializing database..."
	python -c "from scripts.process_ocr import init_db; init_db()"

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
EOF

# README_OCR.md
cat <<EOF > README_OCR.md
# OCR Data Entry System with Langflow

This project implements an OCR (Optical Character Recognition) data entry system using Langflow to create a visual pipeline for processing images and extracting text.

## Features

- **Image Upload:** Users can upload images containing text.
- **OCR Processing:** Utilizes Tesseract OCR to extract text from images.
- **Database Storage:** Stores OCR results (filename, extracted text, status) in an SQLite database.
- **Categorization:** Automatically moves processed images to 'processed/' or 'failed/' directories.
- **Langflow Integration:** A Langflow flow orchestrates the image processing.
- **Docker Support:** Easily deployable using Docker and Docker Compose.
- **GitHub Actions:** Automated deployment workflow.

## Project Structure

\`\`\`
.
├── flows/
│   └── ocr_data_entry.json          # Langflow flow definition
├── database/
│   ├── schema.sql                   # Database schema for OCR results
│   └── ocr_data.db                  # SQLite database (generated)
├── scripts/
│   └── process_ocr.py               # Python script for OCR processing and database interaction
├── uploads/
│   ├── processed/                   # Directory for successfully processed images
│   └── failed/                      # Directory for images that failed OCR
├── logs/                            # Application logs
├── .github/workflows/
│   └── deploy.yml                   # GitHub Actions workflow for deployment
├── docker-compose.yml               # Docker Compose configuration
├── Dockerfile                       # Dockerfile for the Langflow application
├── Makefile                         # Utility commands for setup, run, clean, test
├── README_OCR.md                    # This documentation file
├── .env.example                     # Example environment variables file
└── .gitignore                       # Specifies files/directories to ignore in Git
\`\`\`

## Setup and Installation

### Prerequisites

- Python 3.8+
- pip
- Langflow (
\`pip install langflow\
)
- Tesseract OCR engine (installation varies by OS, e.g., \`sudo apt install tesseract-ocr\` on Debian/Ubuntu, \`pkg install tesseract\` on Termux)
- Docker and Docker Compose (if using Docker)

### Local Setup

1.  **Clone the repository:**
    \`\`\`bash
    git clone https://github.com/nssuwan186-dev/langflow.git
    cd langflow
    \`\`\`

2.  **Run the setup script:**
    This script will create all necessary directories and placeholder files.
    \`\`\`bash
    bash setup_all.sh
    \`\`\`

3.  **Install Python dependencies:**
    \`\`\`bash
    pip install -r requirements.txt
    \`\`\`
    *(Note: The \`requirements.txt\` file will be created by this process with basic dependencies.)*

4.  **Set up Environment Variables:**
    Copy the example environment file and add your OpenAI API key (if you're using LLMs in your Langflow flow, though not strictly required for basic OCR).
    \`\`\`bash
    cp .env.example .env
    # Open .env with a text editor and add your OPENAI_API_KEY
    nano .env
    \`\`\`

5.  **Initialize the database:**
    \`\`\`bash
    make setup
    \`\`\`

### Running the Application

#### Local (without Docker)

\`\`\`bash
make run
\`\`\`
This will start the Langflow UI, typically accessible at \`http://localhost:7860\`.

#### Using Docker Compose

\`\`\`bash
make docker
\`\`\`
This will build the Docker images and start the containers in detached mode. Langflow will be accessible at \`http://localhost:7860\`.

## Usage

1.  **Access Langflow UI:** Open your web browser and navigate to \`http://localhost:7860\`.
2.  **Load the Flow:** Import the \`flows/ocr_data_entry.json\` file into Langflow.
3.  **Upload Image:** Interact with the flow by providing an image.
4.  **View Results:** The OCR extracted text and processing status will be displayed in the Langflow UI and stored in \`database/ocr_data.db\`.

## Testing

\`\`\`bash
make test
\`\`\`
This command will run the \`process_ocr.py\` script directly with a dummy image (if created successfully) and display the last OCR result from the database.

## Cleaning Up

To remove generated files and databases:

\`\`\`bash
make clean
\`\`\`

## Deployment

The \`.github/workflows/deploy.yml\` defines a GitHub Actions workflow to automatically deploy your Langflow OCR system on push to \`main\` or manually via workflow dispatch. Ensure your repository is correctly configured for deployment (e.g., secrets for cloud providers if deploying beyond just Docker on a server).
EOF

# .env.example
cat <<EOF > .env.example
# Example .env file
# Replace with your actual API keys or sensitive information
OPENAI_API_KEY="your_openai_api_key_here"
# Add other environment variables as needed
EOF

# .gitignore
cat <<EOF > .gitignore
# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
env/
virtualenv/
.env

# Database
*.db

# Uploads (processed images, etc.)
uploads/processed/
uploads/failed/

# Logs
logs/

# Docker
.dockerignore

# Langflow specific
.langflow/

# OS generated files
.DS_Store
.vscode/

# Build artifacts
build/
dist/
*.egg-info/

# Misc
*.zip
*.tar.gz
*.log
EOF

# Dockerfile for Langflow (needed for docker-compose build)
cat <<EOF > Dockerfile
# Use a base image that includes Python and is compatible with your architecture (ARM64 for Android/Termux)
FROM python:3.10-slim-bullseye-arm64v8

# Set working directory
WORKDIR /app

# Install system dependencies for Langflow and Tesseract
# Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Tesseract OCR and its language packs
# Ensure apt-get update is run before install
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    tesseract-ocr-eng \
    libgl1-mesa-glx \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Copy the rest of the application code
COPY . .

# Expose the port Langflow runs on
EXPOSE 7860

# Command to run Langflow (entrypoint might be better for real apps)
CMD ["langflow", "--log-level", "info", "--host", "0.0.0.0", "--port", "7860"]
EOF

# requirements.txt
cat <<EOF > requirements.txt
langflow
pytesseract
Pillow
# sqlite3 is built-in, no need to list
# Add other Python dependencies here as your Langflow flow or scripts evolve
EOF