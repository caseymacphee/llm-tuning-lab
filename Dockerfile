FROM python:3.12-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIPENV_VENV_IN_PROJECT=1 \
    PIPENV_NOSPIN=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install pipenv
RUN pip install pipenv

# Set working directory
WORKDIR /workspace

# Copy dependency files
COPY Pipfile Pipfile.lock* ./

# Install dependencies
RUN pipenv install --dev --deploy || pipenv install --dev

# Copy project files
COPY . .

# Install package in editable mode
RUN pipenv run pip install -e .

# Default command
CMD ["tail", "-f", "/dev/null"]
