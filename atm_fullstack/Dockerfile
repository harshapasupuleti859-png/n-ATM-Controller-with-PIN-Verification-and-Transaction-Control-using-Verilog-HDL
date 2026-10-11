# Multi-stage / lightweight image with Python 3 and Icarus Verilog
FROM python:3.11-slim

# Install Icarus Verilog and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    iverilog \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy application files
COPY . /app

# Ensure correct permissions
RUN chmod +x run_mac_linux.sh || true

# Default port
ENV PORT=8000
ENV HOST=0.0.0.0

EXPOSE 8000

# Health check using python urllib
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/config')" || exit 1

# Start the fullstack ATM bank application
CMD ["python3", "app.py"]
