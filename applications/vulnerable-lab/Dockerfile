# SENTINEL-X – Test Web Application
# Minimal Flask app designed to trigger WAF rules during security testing.
# NOT for production use. Intentional vulnerability patterns exist for testing only.

FROM python:3.12-alpine

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App source
COPY src/ .

# Ownership
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

# Use python to avoid needing wget/curl in Alpine
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "app.py"]
