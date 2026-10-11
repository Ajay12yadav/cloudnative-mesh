FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run as a non-root user
RUN useradd --uid 10001 --no-create-home appuser
USER 10001

EXPOSE 8000

# ONE worker process (several threads): prometheus_client keeps metrics in
# memory per process, so multiple workers would give inconsistent counters.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "8", "--access-logfile", "-", "app:app"]
