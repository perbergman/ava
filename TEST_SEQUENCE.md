# Avalanche Teleporter Test Sequence Guide

## Overview
This document provides a comprehensive testing sequence for the Avalanche Teleporter cross-chain messaging system. It covers all components, integration patterns, and verification steps.

## Prerequisites Verification

### 1. Environment Check
```bash
# Verify required tools are installed
avalanche --version    # Should be v1.8.10+
node --version         # Should be v16+
npm --version          # Should be v8+

# Check project dependencies
npm list --depth=0
```

### 2. Clean State Verification
```bash
# Ensure no existing network is running
avalanche network status
# Should show "Error: network is not running" for clean state

# Check for any running processes
ps aux | grep avalanche
ps aux | grep node
```

## Test Sequence

### Phase 1: Network Deployment
```bash
# 1.1 Deploy the complete network
./setup-avalanche-teleporter.sh

# 1.2 Verify network configuration
cat network-config.json
# Should contain valid RPC URLs and blockchain IDs

# 1.3 Check network health
avalanche network status
# Should show "Network Healthy: true"
```

**Expected Results:**
- ✅ 2 L1 blockchains created (subnet1, subnet2)
- ✅ ICM Relayer deployed and running
- ✅ Teleporter contracts at same address on all chains
- ✅ Pre-funded accounts with 1M tokens each

### Phase 2: Basic Cross-Chain Messaging
```bash
# 2.1 Run basic message tests
npm test

# 2.2 Verify test results
# Expected delivery times:
# - L1 to L1: 100-500ms
# - C-Chain to L1: 4-6 seconds
```

**Test Cases Covered:**
- ✅ Subnet1 → Subnet2 messaging
- ✅ Subnet2 → Subnet1 messaging  
- ✅ C-Chain → Subnet1 messaging
- ✅ Account balance verification
- ✅ Message delivery confirmation

### Phase 3: REST API Testing
```bash
# 3.1 Start API server
npm run send:server &
API_PID=$!
sleep 3

# 3.2 Test balance endpoint
curl -s http://localhost:3000/balances | jq

# 3.3 Send test message via API
curl -X POST http://localhost:3000/send-message \
  -H "Content-Type: application/json" \
  -d '{
    "fromNetwork": "subnet1",
    "toNetwork": "subnet2",
    "message": "API Test Message"
  }' | jq

# 3.4 Cleanup
kill $API_PID
```

**Expected Results:**
- ✅ API server starts on port 3000
- ✅ Balance endpoint returns current balances
- ✅ Message sending returns transaction hash and message ID
- ✅ Message delivered within 5 seconds

### Phase 4: Real-Time Monitoring
```bash
# 4.1 Start WebSocket monitor
npm run monitor &
MONITOR_PID=$!
sleep 5

# 4.2 Verify WebSocket server
curl -s http://localhost:8080 || echo "WebSocket server running on ws://localhost:8080"

# 4.3 Check HTML dashboard was created
ls -la teleporter-monitor.html

# 4.4 Send test message while monitoring
npm run send:server &
API_PID=$!
sleep 3

curl -X POST http://localhost:3000/send-message \
  -H "Content-Type: application/json" \
  -d '{
    "fromNetwork": "subnet2",
    "toNetwork": "subnet1",
    "message": "Monitor Test - Real-time message"
  }'

# 4.5 Cleanup
kill $MONITOR_PID $API_PID 2>/dev/null || true
```

**Expected Results:**
- ✅ WebSocket server starts on port 8080
- ✅ HTML dashboard generated
- ✅ Real-time message broadcasting
- ✅ Message history tracking

### Phase 5: Event Listener Testing
```bash
# 5.1 Start event listener in background
timeout 15 npm run listen &
LISTENER_PID=$!

# 5.2 Send messages to trigger events
npm run send:server &
API_PID=$!
sleep 3

# Send multiple test messages
for i in {1..3}; do
  curl -X POST http://localhost:3000/send-message \
    -H "Content-Type: application/json" \
    -d "{
      \"fromNetwork\": \"subnet1\",
      \"toNetwork\": \"subnet2\",
      \"message\": \"Listener Test Message #$i\"
    }"
  sleep 2
done

# 5.3 Check message logs
sleep 10
cat message-logs.json 2>/dev/null || echo "No message logs yet"

# 5.4 Cleanup
kill $API_PID $LISTENER_PID 2>/dev/null || true
```

**Expected Results:**
- ✅ Event listener monitors all chains
- ✅ Messages logged to message-logs.json
- ✅ Message processing and archival

### Phase 6: Interactive CLI Testing
```bash
# 6.1 Prepare test inputs
cat << EOF > test_inputs.txt
subnet1
subnet2
CLI Test Message - Interactive Mode
0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC
exit
EOF

# 6.2 Run interactive CLI with prepared inputs
npm run send < test_inputs.txt

# 6.3 Cleanup
rm test_inputs.txt
```

**Expected Results:**
- ✅ Interactive CLI accepts inputs
- ✅ Message sent successfully
- ✅ Transaction hash and confirmation received

### Phase 7: Network Performance Testing
```bash
# 7.1 Start API server for batch testing
npm run send:server &
API_PID=$!
sleep 3

# 7.2 Send batch of messages for performance testing
echo "Sending batch messages..."
START_TIME=$(date +%s)

for i in {1..5}; do
  curl -X POST http://localhost:3000/send-message \
    -H "Content-Type: application/json" \
    -d "{
      \"fromNetwork\": \"subnet1\",
      \"toNetwork\": \"subnet2\",
      \"message\": \"Performance Test #$i - $(date)\"
    }" &
done

wait
END_TIME=$(date +%s)
echo "Batch of 5 messages sent in $((END_TIME - START_TIME)) seconds"

# 7.3 Cleanup
kill $API_PID
```

**Expected Results:**
- ✅ Multiple concurrent messages handled
- ✅ No message delivery failures
- ✅ Performance metrics within acceptable range

### Phase 8: Error Handling Testing
```bash
# 8.1 Test invalid network names
curl -X POST http://localhost:3000/send-message \
  -H "Content-Type: application/json" \
  -d '{
    "fromNetwork": "invalid_network",
    "toNetwork": "subnet2",
    "message": "This should fail"
  }'

# 8.2 Test empty message
curl -X POST http://localhost:3000/send-message \
  -H "Content-Type: application/json" \
  -d '{
    "fromNetwork": "subnet1",
    "toNetwork": "subnet2",
    "message": ""
  }'
```

**Expected Results:**
- ✅ Proper error handling for invalid inputs
- ✅ Descriptive error messages returned
- ✅ System remains stable after errors

### Phase 9: Network Health Verification
```bash
# 9.1 Check overall network status
avalanche network status

# 9.2 Verify individual blockchain health
avalanche blockchain describe subnet1
avalanche blockchain describe subnet2

# 9.3 Check relayer logs for any issues
tail -20 ~/.avalanche-cli/runs/network_*/icm-relayer.log 2>/dev/null || echo "No relayer logs found"

# 9.4 Verify account balances after all tests
curl -s http://localhost:3000/balances 2>/dev/null || {
  npm run send:server &
  API_PID=$!
  sleep 3
  curl -s http://localhost:3000/balances
  kill $API_PID
}
```

**Expected Results:**
- ✅ All nodes healthy and responsive
- ✅ Blockchains producing blocks normally
- ✅ Relayer processing messages without errors
- ✅ Account balances reflect gas usage from tests

## Test Results Verification

### Success Criteria
- [ ] Network deploys without errors
- [ ] All basic message tests pass
- [ ] REST API endpoints respond correctly
- [ ] WebSocket monitoring works
- [ ] Event listener captures messages
- [ ] Interactive CLI functions properly
- [ ] Performance is within acceptable limits
- [ ] Error handling works correctly
- [ ] Network remains healthy throughout testing

### Common Issues and Solutions

#### Issue: RPC URL extraction fails
**Solution:** Manually update network-config.json with correct URLs from setup output

#### Issue: Port conflicts (8080, 3000)
**Solution:** Kill existing processes or modify port numbers in scripts

#### Issue: Message delivery timeout
**Solution:** Wait longer (ICM relayer can take 4-6 seconds), check relayer logs

#### Issue: "EADDRINUSE" errors
**Solution:** Run `pkill -f "node.*teleporter"` to clean up processes

## Automated Test Execution

To run the complete test sequence automatically:
```bash
# Run the automated test script
./run-comprehensive-tests.sh

# Or run individual test phases
./run-comprehensive-tests.sh --phase=1  # Network deployment only
./run-comprehensive-tests.sh --phase=2  # Basic messaging only
```

## Cleanup

After completing all tests:
```bash
# Stop all processes
pkill -f "teleporter"
pkill -f "avalanche"

# Clean shutdown
npm run shutdown

# Verify clean state
avalanche network status  # Should show "network is not running"
```

## Test Report Template

```markdown
# Avalanche Teleporter Test Report

**Date:** $(date)
**Tester:** [Your Name]
**Network Version:** $(avalanche --version)

## Test Results Summary
- [ ] Phase 1: Network Deployment
- [ ] Phase 2: Basic Messaging
- [ ] Phase 3: REST API
- [ ] Phase 4: Real-time Monitoring
- [ ] Phase 5: Event Listener
- [ ] Phase 6: Interactive CLI
- [ ] Phase 7: Performance Testing
- [ ] Phase 8: Error Handling
- [ ] Phase 9: Health Verification

## Issues Encountered
[Document any issues and their resolutions]

## Performance Metrics
- Average message delivery time: [X]ms
- API response time: [X]ms
- Network stability: [Stable/Unstable]
- Resource usage: [Acceptable/High]

## Recommendations
[Any suggestions for improvements or optimizations]
```
