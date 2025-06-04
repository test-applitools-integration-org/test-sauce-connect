#!/bin/bash

echo "=== Enhanced Debug Test Runner ==="
echo "This script runs tests specifically designed to reproduce and debug the ETIMEDOUT context switching issue"

# Stop and remove existing containers and network
docker stop test-proxy network-gateway appium-debug-test 2>/dev/null
docker rm test-proxy network-gateway appium-debug-test 2>/dev/null
docker network rm isolated-test-net public-net 2>/dev/null

# Create isolated network
docker network create --driver bridge \
    --internal \
    --subnet=172.20.0.0/16 \
    --gateway=172.20.0.1 \
    isolated-test-net

# Create public network for proxy DNS resolution
docker network create public-net

# Launch proxy with fixed IP and access to both networks
echo "Starting proxy server..."
docker run -d --name test-proxy \
    --network isolated-test-net \
    --ip 172.20.0.2 \
    ubuntu/squid

# Add proxy to public network for external connectivity
docker network connect public-net test-proxy

# Wait for proxy to initialize
echo "Waiting for proxy to initialize..."
sleep 10

# Test proxy connectivity
echo "Testing proxy connectivity..."
if ! docker exec test-proxy curl -s -o /dev/null https://www.google.com; then
    echo "ERROR: Proxy cannot reach external internet"
    exit 1
fi

# Build test container with debug enhancements
echo "Building debug test container..."
docker build -t appium-debug-test .

# Create logs directory if it doesn't exist
mkdir -p $(pwd)/logs
mkdir -p $(pwd)/debug_output

# Run debug test container with enhanced networking and monitoring
echo "Running debug tests with enhanced isolation..."
docker run --rm \
    --network isolated-test-net \
    --ip 172.20.0.4 \
    -v $(pwd)/logs:/app/logs \
    -v $(pwd)/debug_output:/tmp \
    --cap-add=NET_ADMIN \
    --cap-add=SYS_ADMIN \
    --cap-add=NET_RAW \
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
    -e NO_PROXY="localhost,127.0.0.1,test-proxy" \
    -e DEBUG="webdriver:*,appium:*" \
    --entrypoint /bin/bash \
    appium-debug-test \
    -c '
    echo "=== Debug Test Execution ==="
    
    # Run enhanced isolation setup
    echo "Setting up enhanced network isolation..."
    chmod +x /app/setup_enhanced_isolation.sh
    /app/setup_enhanced_isolation.sh || {
        echo "Enhanced isolation setup failed"
        exit 1
    }
    
    # Run the original proxy test first
    echo ""
    echo "=== Running Original Proxy Test ==="
    timeout 600 bundle exec rspec spec/test_appium_proxy.rb --format documentation || echo "Original test completed with exit code $?"
    
    # Run the new debug tests
    echo ""
    echo "=== Running Context Switching Debug Tests ==="
    timeout 900 bundle exec rspec spec/test_context_switching_debug.rb --format documentation || echo "Debug tests completed with exit code $?"
    
    # Analyze captured network traffic
    echo ""
    echo "=== Network Traffic Analysis ==="
    if [ -f /tmp/network_traffic.pcap ]; then
        echo "Network traffic captured:"
        tcpdump -r /tmp/network_traffic.pcap -n | head -20
        echo "Full traffic saved to debug_output/network_traffic.pcap"
        cp /tmp/network_traffic.pcap /tmp/network_traffic_$(date +%Y%m%d_%H%M%S).pcap
    else
        echo "No network traffic captured"
    fi
    
    # Save kernel logs
    echo ""
    echo "=== Kernel Firewall Logs ==="
    dmesg | grep -E "(Dropped|BLOCKED)" | tail -20
    dmesg | grep -E "(Dropped|BLOCKED)" > /tmp/firewall_logs_$(date +%Y%m%d_%H%M%S).log
    
    # Generate test report
    echo ""
    echo "=== Test Summary ==="
    echo "Debug test execution completed"
    echo "Check debug_output/ directory for:"
    echo "  - network_traffic_*.pcap: Captured network traffic"
    echo "  - firewall_logs_*.log: Firewall block logs"
    echo "  - Various test outputs and logs"
    
    echo ""
    echo "If the test reproduced the ETIMEDOUT error, you should see:"
    echo "  1. Error message containing \"ETIMEDOUT\" and \"66.85.52.224:443\""
    echo "  2. Network traffic showing blocked connections to that IP"
    echo "  3. Firewall logs showing dropped packets"
    '

# Clean up
echo ""
echo "=== Cleanup ==="
docker stop test-proxy 2>/dev/null
docker rm test-proxy 2>/dev/null
docker network rm isolated-test-net public-net 2>/dev/null

echo ""
echo "=== Debug Test Run Complete ==="
echo "Check the following for results:"
echo "  - logs/: Application and Sauce Connect logs"
echo "  - debug_output/: Network captures and debug information"
echo ""
echo "Key files to examine:"
echo "  - debug_output/network_traffic_*.pcap: Network traffic during context switching"
echo "  - debug_output/firewall_logs_*.log: Blocked connection attempts"
echo "  - logs/sc.log: Sauce Connect tunnel logs"