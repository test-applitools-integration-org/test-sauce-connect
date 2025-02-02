FROM node:16-slim

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

# Install Sauce Connect
RUN curl -L -o /tmp/sauce-connect.deb \
    https://saucelabs.com/downloads/sauce-connect/5.2.2/sauce-connect_5.2.2.linux_amd64.deb && \
    dpkg -i /tmp/sauce-connect.deb && \
    rm -f /tmp/sauce-connect.deb

ENV SAUCE_CONNECT_BIN=/usr/bin/sc
ENV APPLITOOLS_LOG_DIR=./logs
ENV APPLITOOLS_PROXY_URL="http://test-proxy:3128"

# Set working directory
WORKDIR /app

# Copy test files
COPY spec ./spec/
COPY package.json .
COPY setup_isolation.sh .

# Install dependencies
RUN npm install

# Add container health verification script
RUN chmod +x /app/setup_isolation.sh

# Default command to verify isolation and run tests
CMD ["/bin/bash", "-c", "/app/setup_isolation.sh && npx mocha spec/test-appium-spec.js"]
