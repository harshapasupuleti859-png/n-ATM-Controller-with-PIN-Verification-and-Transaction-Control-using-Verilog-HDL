FROM python:3.11-slim

# Install Icarus Verilog
RUN apt-get update && apt-get install -y --no-install-recommends \
    iverilog \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy fullstack application into container
COPY atm_fullstack/ /app/

ENV PORT=8000
ENV HOST=0.0.0.0

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/config')" || exit 1

CMD ["python3", "app.py"]
