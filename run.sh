#!/bin/bash

# Stop and remove existing containers and network
docker stop test-proxy network-gateway appium-proxy-test 2>/dev/null
docker rm test-proxy network-gateway appium-proxy-test 2>/dev/null
docker network rm isolated-test-net 2>/dev/null

# Create isolated network
docker network create --driver bridge \
    --internal \
    --subnet=172.20.0.0/16 \
    --gateway=172.20.0.1 \
    isolated-test-net

# Create public network for proxy DNS resolution
docker network create public-net

# Launch proxy with fixed IP and access to both networks
docker run -d --name test-proxy \
    --network isolated-test-net \
    --network public-net \
    --ip 172.20.0.2 \
    --cap-add=NET_ADMIN \
    -p 3128:3128 \
    ubuntu/squid

# Wait for proxy to initialize
echo "Waiting for proxy to initialize..."
sleep 10

# Run test container with proper network configuration
docker build -t appium-proxy-test .
docker run --rm \
    --network isolated-test-net \
    --ip 172.20.0.4 \
    -v $(pwd)/logs:/app/logs \
    --cap-drop=NET_RAW \
    --cap-drop=NET_ADMIN \
    --privileged \
    -e SAUCE_USERNAME \
    -e SAUCE_ACCESS_KEY \
    -e SAUCE_TUNNEL_ID \
    -e SAUCE_SERVER_URL \
    -e APP_APK_URL \
    -e APPLITOOLS_API_KEY \
    -e APPLITOOLS_PROXY_URL="http://test-proxy:3128" \
    -e HTTP_PROXY="http://test-proxy:3128" \
    -e HTTPS_PROXY="http://test-proxy:3128" \
    -e NO_PROXY="localhost,127.0.0.1" \
    --entrypoint /bin/bash \
    appium-proxy-test \
    -c '
    /app/setup_isolation.sh || {
        echo "Test failed. Checking container networking:"
        ip route
        netstat -tulpn
        dmesg | grep "Dropped"
        exit 1
    }
    bundle exec rspec spec/test_appium_proxy.rb --format documentation
    '