FROM python:3.11-slim

# Set working directory
WORKDIR /app
WORKDIR /app/bus_tracking_backend

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn

# Copy application code
COPY . .

# Create uploads directory
RUN mkdir -p /app/bus_tracking_backend/uploads

# Expose port
EXPOSE 8000

# Run with Uvicorn (not Gunicorn - Gunicorn doesn't support WebSockets well)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]