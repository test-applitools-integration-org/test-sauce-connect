#!/bin/bash

# Configure iptables with logging
iptables -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS queries to Docker DNS
iptables -A OUTPUT -p udp -d 127.0.0.11 --dport 53 -j ACCEPT
iptables -A INPUT -p udp -s 127.0.0.11 --sport 53 -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow traffic to proxy with container name
iptables -A OUTPUT -p tcp -d test-proxy --dport 3128 -j ACCEPT

# Log dropped packets
iptables -A INPUT -j LOG --log-prefix "Dropped Input: "
iptables -A OUTPUT -j LOG --log-prefix "Dropped Output: "

# Add these rules for port 8989
iptables -A INPUT -p tcp --dport 8989 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 8989 -j ACCEPT
iptables -A INPUT -i lo -p tcp --dport 8989 -j ACCEPT
iptables -A OUTPUT -o lo -p tcp --dport 8989 -j ACCEPT

echo "=== Network Isolation Tests ==="

echo "=== IPTables Rules ==="
iptables -L -v -n

echo "=== Testing DNS Resolution ==="
nslookup test-proxy

# Test direct connectivity (should fail)
echo "Testing direct connectivity (expected to fail)..."
if wget -q --timeout=5 --no-proxy https://www.google.com -O /dev/null; then
    echo "ERROR: Direct connection succeeded when it should be blocked"
    exit 1
else
    echo "SUCCESS: Direct connection blocked as expected"
fi

# Test proxy connectivity
echo -e "\n=== Proxy Connection Test ==="
if curl --proxy $APPLITOOLS_PROXY_URL -s -o /dev/null -w "%{http_code}" https://www.google.com | grep -q "200"; then
    echo "SUCCESS: Proxy connection working"
else
    echo "ERROR: Proxy connection failed"
    exit 1
fi

# Test DNS resolution through proxy
echo -e "\n=== DNS Resolution Test ==="
if host -T 5 www.google.com 2>/dev/null; then
    echo "ERROR: Direct DNS resolution should be blocked"
    exit 1
else
    echo "SUCCESS: Direct DNS resolution blocked as expected"
fi

# Network interface check
echo -e "\n=== Network Interface Configuration ==="
ip route
ip addr

# Verify proxy environment variables
echo -e "\n=== Proxy Environment Variables ==="
echo "HTTP_PROXY: $HTTP_PROXY"
echo "HTTPS_PROXY: $HTTPS_PROXY"
echo "APPLITOOLS_PROXY_URL: $APPLITOOLS_PROXY_URL"

# Test specific required endpoints through proxy
echo -e "\n=== Testing Required Endpoints ==="
for endpoint in "saucelabs.com" "applitools.com"; do
    echo "Testing connection to $endpoint..."
    if curl --proxy $APPLITOOLS_PROXY_URL -s -o /dev/null -w "%{http_code}" https://$endpoint | grep -q "200"; then
        echo "SUCCESS: Connection to $endpoint through proxy successful"
    else
        echo "ERROR: Failed to connect to $endpoint through proxy"
        exit 1
    fi
done

echo "=== Testing port 8989 availability ==="
if nc -z localhost 8989; then
    echo "SUCCESS: Port 8989 is available"
else
    echo "ERROR: Port 8989 is not available"
fi

echo -e "\n=== All tests completed successfully ==="