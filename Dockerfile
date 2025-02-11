FROM python:3.11-slim

# Install basic tools and cleanup in single layer
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    curl \
    iproute2 \
    iputils-ping \
    iptables \
    dnsutils \
    net-tools \
    netcat-traditional \
    wget \
    && rm -rf /var/lib/apt/lists/*
 \
    # Install wheel and other dependencies
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install Sauce Connect
RUN curl -L -o /tmp/sauce-connect.deb \
    https://saucelabs.com/downloads/sauce-connect/5.2.2/sauce-connect_5.2.2.linux_amd64.deb && \
    dpkg -i /tmp/sauce-connect.deb && \
    rm -f /tmp/sauce-connect.deb

ENV SAUCE_CONNECT_BIN=/usr/bin/sc
ENV APPLITOOLS_LOG_DIR=./logs
ENV APPLITOOLS_PROXY_URL=http://test-proxy:3128

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Set working directory
WORKDIR /app

# Copy requirements first to leverage Docker cache
COPY pyproject.toml .
COPY requirements.lock .
COPY eyes_common-5.32.0-py2.py3-none-any.whl .

# Install Python dependencies
RUN PYTHONDONTWRITEBYTECODE=1 pip install --no-cache-dir -r requirements.lock
RUN PYTHONDONTWRITEBYTECODE=1 pip install eyes_common-5.32.0-py2.py3-none-any.whl

# Copy test files
COPY tests/ ./tests/
COPY setup_isolation.sh .

# Add container health verification script
RUN chmod +x /app/setup_isolation.sh

# Create directory for logs
RUN mkdir -p /app/logs
