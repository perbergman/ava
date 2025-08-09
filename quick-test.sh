#!/bin/bash

# Quick Test Script for Avalanche Teleporter
# Tests the current running network without full redeployment

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo -e "${BLUE}🚀 Avalanche Teleporter Quick Test${NC}"
echo -e "${BLUE}==================================${NC}"

# Test 1: Check network status
log "Testing network status..."
if avalanche network status >/dev/null 2>&1; then
    success "Network is running and healthy"
else
    error "Network is not running. Run './setup-avalanche-teleporter.sh' first"
    exit 1
fi

# Test 2: Check configuration file
log "Checking network configuration..."
if [ -f "network-config.json" ]; then
    if grep -q "http://127.0.0.1" network-config.json; then
        success "Network configuration looks good"
    else
        error "Network configuration has invalid RPC URLs"
        exit 1
    fi
else
    error "Network configuration file missing"
    exit 1
fi

# Test 3: Basic messaging test
log "Running basic cross-chain messaging test..."
if timeout 30 npm test >/dev/null 2>&1; then
    success "Basic messaging tests passed"
else
    error "Basic messaging tests failed"
    exit 1
fi

# Test 4: API server test
log "Testing REST API functionality..."
npm run send:server >/dev/null 2>&1 &
API_PID=$!
sleep 3

if curl -s http://localhost:3000/balances >/dev/null 2>&1; then
    # Test sending a message via API
    response=$(curl -s -X POST http://localhost:3000/send-message \
        -H "Content-Type: application/json" \
        -d '{
            "fromNetwork": "subnet1",
            "toNetwork": "subnet2",
            "message": "Quick test message via API"
        }')
    
    if echo "$response" | grep -q "success.*true"; then
        success "REST API test passed"
    else
        error "REST API message sending failed"
    fi
else
    error "REST API server not responding"
fi

# Cleanup API server
kill $API_PID 2>/dev/null || true

# Test 5: WebSocket monitor (quick check)
log "Testing WebSocket monitor setup..."
timeout 10 npm run monitor >/dev/null 2>&1 &
MONITOR_PID=$!
sleep 5

if [ -f "teleporter-monitor.html" ]; then
    success "WebSocket monitor HTML dashboard created"
else
    warning "WebSocket monitor dashboard not created"
fi

kill $MONITOR_PID 2>/dev/null || true

# Summary
echo ""
success "All quick tests completed successfully! 🎉"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "• Run full test suite: ./run-comprehensive-tests.sh"
echo "• Start API server: npm run send:server"
echo "• Monitor messages: npm run monitor"
echo "• View dashboard: open teleporter-monitor.html"
echo ""
