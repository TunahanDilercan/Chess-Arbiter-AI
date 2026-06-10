FROM python:3.11-slim

WORKDIR /app

# Install system dependencies required by OpenCV (libgl1) and GLib (libglib2.0-0).
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run as a non-root user; storage is the only writable path the app needs.
RUN useradd --create-home --uid 1000 arbiter \
    && mkdir -p /app/storage \
    && chown -R arbiter:arbiter /app/storage

USER arbiter

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
