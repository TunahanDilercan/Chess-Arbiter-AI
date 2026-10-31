ARG RUNTIME_BASE=python:3.11-slim
FROM ${RUNTIME_BASE}

USER root

WORKDIR /app

COPY requirements.txt .
RUN python -c "import torch" 2>/dev/null \
    || pip install --no-cache-dir "torch>=2.1.0" --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir -r requirements.txt
RUN python -c "import anthropic, cv2, pypdfium2, torch"

COPY . .

# Run as a non-root user; storage is the only writable path the app needs.
RUN if ! id -u arbiter >/dev/null 2>&1; then useradd --create-home --uid 1000 arbiter; fi \
    && mkdir -p /app/storage \
    && chown -R arbiter:arbiter /app/storage

USER arbiter

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
