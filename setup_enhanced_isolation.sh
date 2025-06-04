#!/bin/bash

# Enhanced isolation setup with specific focus on reproducing client environment issues

# Configure iptables with detailed logging
iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS queries to Docker DNS and through proxy
iptables -A OUTPUT -p udp -d 127.0.0.11 --dport 53 -j ACCEPT
iptables -A INPUT -p udp -s 127.0.0.11 --sport 53 -j ACCEPT

# Allow DNS resolution through the proxy
iptables -A OUTPUT -p tcp -d test-proxy --dport 3128 -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# CRITICAL: Block the specific IP that causes ETIMEDOUT in client environments
echo "=== Blocking Problematic IPs ==="
iptables -A OUTPUT -d 66.85.52.224 -j LOG --log-prefix "BLOCKED_SAUCELABS_IP: "
iptables -A OUTPUT -d 66.85.52.224 -j DROP

# Block common SauceLabs IP ranges to simulate client firewall
iptables -A OUTPUT -d 66.85.0.0/16 -j LOG --log-prefix "BLOCKED_SAUCELABS_RANGE: "
iptables -A OUTPUT -d 66.85.0.0/16 -j DROP

# Log all other dropped packets for analysis
iptables -A INPUT -j LOG --log-prefix "Dropped Input: "
iptables -A OUTPUT -j LOG --log-prefix "Dropped Output: "

# Add specific rules for port 8989 (Sauce Connect status)
iptables -A INPUT -p tcp --dport 8989 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 8989 -j ACCEPT
iptables -A INPUT -i lo -p tcp --dport 8989 -j ACCEPT
iptables -A OUTPUT -o lo -p tcp --dport 8989 -j ACCEPT

echo "=== Enhanced Network Isolation Tests ==="

echo "=== IPTables Rules ==="
iptables -L -v -n

echo "=== Testing DNS Resolution ==="
nslookup test-proxy

# Test direct connectivity to problematic IPs (should fail)
echo "=== Testing Direct Connectivity to Problematic IPs ==="
for ip in "66.85.52.224" "66.85.52.0/24"; do
    echo "Testing direct connection to $ip (expected to fail)..."
    if timeout 5 wget -q --timeout=3 --no-proxy "https://$ip" -O /dev/null 2>/dev/null; then
        echo "ERROR: Direct connection to $ip succeeded when it should be blocked"
        exit 1
    else
        echo "SUCCESS: Direct connection to $ip blocked as expected"
    fi
done

# Test direct connectivity to general internet (should fail)
echo "=== Testing General Internet Connectivity ==="
if timeout 5 wget -q --timeout=3 --no-proxy https://www.google.com -O /dev/null 2>/dev/null; then
    echo "ERROR: Direct internet connection succeeded when it should be blocked"
    exit 1
else
    echo "SUCCESS: Direct internet connection blocked as expected"
fi

# Test proxy connectivity
echo "=== Enhanced Proxy Connection Tests ==="
echo "Testing basic proxy connectivity..."
if curl --proxy $APPLITOOLS_PROXY_URL -s -o /dev/null -w "%{http_code}" https://www.google.com | grep -q "200"; then
    echo "SUCCESS: Basic proxy connection working"
else
    echo "ERROR: Basic proxy connection failed"
    exit 1
fi

# Test proxy connectivity to specific problematic domains
echo "=== Testing Proxy Access to Problematic Domains ==="
problematic_domains=("66.85.52.224" "ondemand.us-west-1.saucelabs.com" "saucelabs.com")

for domain in "${problematic_domains[@]}"; do
    echo "Testing proxy connection to $domain..."
    http_code=$(curl --proxy $APPLITOOLS_PROXY_URL -s -o /dev/null -w "%{http_code}" "https://$domain" --connect-timeout 10 --max-time 30)
    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "404" ]] || [[ "$http_code" == "403" ]]; then
        echo "SUCCESS: Proxy can reach $domain (HTTP $http_code)"
    else
        echo "WARNING: Proxy cannot reach $domain (HTTP $http_code) - this simulates client firewall"
    fi
done

# Test DNS resolution through proxy (should be blocked directly)
echo "=== DNS Resolution Tests ==="
if timeout 5 host -T 5 www.google.com 2>/dev/null; then
    echo "ERROR: Direct DNS resolution should be blocked"
    exit 1
else
    echo "SUCCESS: Direct DNS resolution blocked as expected"
fi

# Network interface and routing check
echo "=== Network Configuration ==="
echo "Routes:"
ip route
echo ""
echo "Addresses:"
ip addr show
echo ""
echo "Network interfaces:"
netstat -i

# Verify proxy environment variables
echo "=== Environment Variables ==="
echo "HTTP_PROXY: $HTTP_PROXY"
echo "HTTPS_PROXY: $HTTPS_PROXY"
echo "APPLITOOLS_PROXY_URL: $APPLITOOLS_PROXY_URL"
echo "NO_PROXY: $NO_PROXY"

# Test specific environment variable configurations
echo "=== Testing Environment Variable Configurations ==="

# Test with various proxy format configurations
proxy_formats=(
    "$HTTP_PROXY"
    "$HTTPS_PROXY" 
    "$APPLITOOLS_PROXY_URL"
    "http://test-proxy:3128"
    "test-proxy:3128"
)

for proxy_format in "${proxy_formats[@]}"; do
    if [[ -n "$proxy_format" ]]; then
        echo "Testing proxy format: $proxy_format"
        if timeout 10 curl --proxy "$proxy_format" -s -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null | grep -q "200"; then
            echo "  ✅ Format works: $proxy_format"
        else
            echo "  ❌ Format failed: $proxy_format"
        fi
    fi
done

# Start network traffic monitoring
echo "=== Starting Network Traffic Monitoring ==="
tcpdump -i any -n -s 0 'host 66.85.52.224 or host 66.85.0.0/16 or port 443' -w /tmp/network_traffic.pcap &
TCPDUMP_PID=$!
echo "Network monitoring started (PID: $TCPDUMP_PID)"
echo "Traffic will be captured to /tmp/network_traffic.pcap"

# Set up cleanup trap
trap "echo 'Stopping network monitoring...'; kill $TCPDUMP_PID 2>/dev/null; wait $TCPDUMP_PID 2>/dev/null" EXIT

# Test WebDriver-specific environment variables
echo "=== WebDriver Environment Variables ==="
export WEBDRIVER_HTTP_PROXY="$HTTP_PROXY"
export WEBDRIVER_HTTPS_PROXY="$HTTPS_PROXY"
export WEBDRIVER_PROXY="$APPLITOOLS_PROXY_URL"

# Test skipping deprecated JWP commands (potential workaround)
echo "=== Testing Workaround Environment Variables ==="
export SKIP_DEPRECATED_JWP_COMMANDS="true"
echo "Set SKIP_DEPRECATED_JWP_COMMANDS=true"

# Test Universal SDK specific environment variables
export EYES_NETWORK_RETRY_LIMIT="2"
export EYES_NETWORK_RETRY_TIMEOUT="5000"
export EYES_NETWORK_CONNECTION_TIMEOUT="30000"
export EYES_NETWORK_REQUEST_TIMEOUT="15000"
echo "Set Eyes SDK network timeout configurations"

# Test Undici proxy configuration (for Node.js SEA binaries)
echo "=== Testing Undici Proxy Configuration ==="
if command -v node >/dev/null 2>&1; then
    echo "Node.js available, testing Undici global dispatcher..."
    node -e "
    try {
        const { setGlobalDispatcher, ProxyAgent } = require('undici');
        if (process.env.HTTP_PROXY) {
            setGlobalDispatcher(new ProxyAgent(process.env.HTTP_PROXY));
            console.log('✅ Undici global dispatcher configured with proxy:', process.env.HTTP_PROXY);
        } else {
            console.log('❌ No HTTP_PROXY environment variable set');
        }
    } catch (e) {
        console.log('❌ Undici configuration failed:', e.message);
    }
    " 2>/dev/null || echo "❌ Undici test failed"
else
    echo "❌ Node.js not available for Undici testing"
fi

echo ""
echo "=== Enhanced isolation setup completed successfully ==="
echo "The environment now simulates client firewall restrictions that cause ETIMEDOUT errors"
echo "Blocked IPs: 66.85.52.224, 66.85.0.0/16"
echo "All traffic must go through proxy: $APPLITOOLS_PROXY_URL"
echo "Network monitoring active - check /tmp/network_traffic.pcap after tests"