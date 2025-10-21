FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY models/ ./models/
COPY data/ ./data/

RUN mkdir -p /app/logs && \
    chown -R appuser:appuser /app

EXPOSE 8000

USER appuser

ENV ENV=production
ENV HOST=0.0.0.0
ENV PORT=8000
ENV LOG_LEVEL=info

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD python src/healthcheck.py localhost 8000 || exit 1

CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
