# scGPT Docker Container
# Build with: docker build -t scgpt .
# Run with: docker run -it --gpus all scgpt

FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast dependency resolution
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Copy project files
COPY pyproject.toml requirements.txt requirements-dev.txt ./
COPY scgpt/ ./scgpt/
COPY README.md LICENSE ./

# Install dependencies with uv
RUN uv pip install --system -r requirements.txt

# Install scGPT in development mode
RUN uv pip install --system -e .

# Set default command
CMD ["python", "-c", "import scgpt; print('scGPT installed successfully!')"]

# For development, you can override with:
# docker run -it --gpus all -v $(pwd):/app scgpt bash