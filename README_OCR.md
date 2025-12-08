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

```
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
```

## Setup and Installation

### Prerequisites

- Python 3.8+
- pip
- Langflow (
`pip install langflow)
- Tesseract OCR engine (installation varies by OS, e.g., `sudo apt install tesseract-ocr` on Debian/Ubuntu, `pkg install tesseract` on Termux)
- Docker and Docker Compose (if using Docker)

### Local Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/nssuwan186-dev/langflow.git
    cd langflow
    ```

2.  **Run the setup script:**
    This script will create all necessary directories and placeholder files.
    ```bash
    bash setup_all.sh
    ```

3.  **Install Python dependencies:**
    ```bash
    pip install -r requirements.txt
    ```
    *(Note: The `requirements.txt` file will be created by this process with basic dependencies.)*

4.  **Set up Environment Variables:**
    Copy the example environment file and add your OpenAI API key (if you're using LLMs in your Langflow flow, though not strictly required for basic OCR).
    ```bash
    cp .env.example .env
    # Open .env with a text editor and add your OPENAI_API_KEY
    nano .env
    ```

5.  **Initialize the database:**
    ```bash
    make setup
    ```

### Running the Application

#### Local (without Docker)

```bash
make run
```
This will start the Langflow UI, typically accessible at `http://localhost:7860`.

#### Using Docker Compose

```bash
make docker
```
This will build the Docker images and start the containers in detached mode. Langflow will be accessible at `http://localhost:7860`.

## Usage

1.  **Access Langflow UI:** Open your web browser and navigate to `http://localhost:7860`.
2.  **Load the Flow:** Import the `flows/ocr_data_entry.json` file into Langflow.
3.  **Upload Image:** Interact with the flow by providing an image.
4.  **View Results:** The OCR extracted text and processing status will be displayed in the Langflow UI and stored in `database/ocr_data.db`.

## Testing

```bash
make test
```
This command will run the `process_ocr.py` script directly with a dummy image (if created successfully) and display the last OCR result from the database.

## Cleaning Up

To remove generated files and databases:

```bash
make clean
```

## Deployment

The `.github/workflows/deploy.yml` defines a GitHub Actions workflow to automatically deploy your Langflow OCR system on push to `main` or manually via workflow dispatch. Ensure your repository is correctly configured for deployment (e.g., secrets for cloud providers if deploying beyond just Docker on a server).
