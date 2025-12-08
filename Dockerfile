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