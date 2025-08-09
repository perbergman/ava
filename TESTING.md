# Avalanche Teleporter Testing Guide

This document explains how to test the Avalanche Teleporter cross-chain messaging system using the provided test scripts and sequences.

## Quick Start

### 1. Deploy and Test in One Command
```bash
# Complete setup and basic test
npm run setup && npm test
```

### 2. Quick Health Check (Current Network)
```bash
# Test current running network without redeployment
npm run test:quick
```

### 3. Comprehensive Test Suite
```bash
# Run all 9 test phases with detailed reporting
npm run test:comprehensive
```

## Test Scripts Overview

### 🚀 `quick-test.sh` - Fast Verification
**Purpose:** Quickly verify that the current network is working  
**Duration:** ~30 seconds  
**Use Case:** Regular health checks, CI/CD pipelines

```bash
./quick-test.sh
# or
npm run test:quick
```

**What it tests:**
- Network health status
- Configuration validity
- Basic cross-chain messaging
- REST API functionality
- WebSocket monitor setup

### 📊 `run-comprehensive-tests.sh` - Full Test Suite
**Purpose:** Complete system validation with detailed reporting  
**Duration:** 5-10 minutes  
**Use Case:** Full system validation, pre-deployment testing

```bash
# Run all test phases
./run-comprehensive-tests.sh
# or
npm run test:comprehensive

# Run specific phase only
./run-comprehensive-tests.sh --phase=3
# or 
npm run test:phase=3
```

**Test Phases:**
1. **Network Deployment** - Deploy fresh network from scratch
2. **Basic Messaging** - Cross-chain message tests
3. **REST API** - API endpoints and functionality
4. **Real-time Monitoring** - WebSocket and dashboard
5. **Event Listener** - Message capture and logging
6. **Interactive CLI** - Command-line interface
7. **Performance Testing** - Batch message handling
8. **Error Handling** - Invalid input handling
9. **Health Verification** - Final network health check

### 📋 `TEST_SEQUENCE.md` - Manual Testing Guide
**Purpose:** Step-by-step manual testing instructions  
**Use Case:** Development, debugging, learning

Contains detailed manual test procedures for each component.

## Test Outputs and Reports

### Automated Reports
The comprehensive test script generates multiple output files:

```bash
# JSON results for programmatic analysis
test-report-YYYYMMDD-HHMMSS.json

# Human-readable markdown report
test-report-YYYYMMDD-HHMMSS.md

# Detailed test logs
test-results-YYYYMMDD-HHMMSS.log
```

### Example Report Structure
```markdown
# Avalanche Teleporter Test Report

**Date:** 2025-08-09 11:07:58
**Overall Result:** 9/9 phases passed (100.0%)

- [✅] Phase 1: Network Deployment - PASS
- [✅] Phase 2: Basic Messaging - PASS
- [✅] Phase 3: REST API - PASS
- [✅] Phase 4: Real-time Monitoring - PASS
- [✅] Phase 5: Event Listener - PASS
- [✅] Phase 6: Interactive CLI - PASS
- [✅] Phase 7: Performance Testing - PASS
- [✅] Phase 8: Error Handling - PASS
- [✅] Phase 9: Health Verification - PASS
```

## Testing Workflows

### Development Workflow
```bash
# 1. Initial setup
npm run setup

# 2. Quick verification during development
npm run test:quick

# 3. Test specific functionality
npm run test:phase=3  # Test just the REST API

# 4. Final validation before commit
npm run test:comprehensive
```

### CI/CD Pipeline
```bash
# Automated testing sequence
npm run setup
npm run test:quick
if [ $? -eq 0 ]; then
    npm run test:comprehensive
fi
npm run shutdown
```

### Debugging Workflow
```bash
# 1. Check current state
npm run test:quick

# 2. Run specific failing phase
npm run test:phase=5  # If event listener is failing

# 3. Check network health
avalanche network status
avalanche blockchain describe subnet1

# 4. Check logs
tail -f ~/.avalanche-cli/runs/network_*/icm-relayer.log
```

## Test Environment Requirements

### System Requirements
- **macOS** (tested on macOS)
- **Avalanche CLI** v1.8.10+
- **Node.js** v16+
- **Available ports:** 3000 (API), 8080 (WebSocket), 9650 (C-Chain), dynamic ports for L1s

### Optional Tools (Enhanced Experience)
```bash
# For better JSON output formatting
brew install jq

# For numerical calculations in reports
brew install bc

# For network port checking
# netcat (usually pre-installed)
```

### Network Resources
- **Disk Space:** ~500MB for network data
- **Memory:** ~2GB RAM for all components
- **CPU:** Moderate usage during message processing

## Troubleshooting Common Issues

### Port Conflicts
```bash
# Kill all teleporter processes
pkill -f teleporter
pkill -f avalanche

# Check what's using ports
lsof -i :3000
lsof -i :8080
```

### Network Issues
```bash
# Clean restart
npm run shutdown
npm run setup

# Check network health
avalanche network status
```

### Test Failures
```bash
# Check test logs
cat test-results-*.log

# Run individual phases
npm run test:phase=1  # Start with network deployment
```

### Message Delivery Issues
```bash
# Check relayer logs
tail -f ~/.avalanche-cli/runs/network_*/icm-relayer.log

# Verify accounts have sufficient balance
curl -s http://localhost:3000/balances
```

## Advanced Testing Scenarios

### Load Testing
```bash
# Modify performance test for higher load
# Edit run-comprehensive-tests.sh, change loop count in phase7_performance_testing
for i in {1..20}; do  # Increase from 3 to 20
```

### Custom Message Formats
```bash
# Test binary messages
curl -X POST http://localhost:3000/send-message \
  -H "Content-Type: application/json" \
  -d '{"fromNetwork":"subnet1","toNetwork":"subnet2","message":"0x48656c6c6f"}'
```

### Multi-hop Messaging
```bash
# Test C-Chain -> Subnet1 -> Subnet2 (requires custom logic)
# See teleporter-sender.js for implementation examples
```

## Test Data and Cleanup

### Test Data Locations
```bash
# Network configuration
./network-config.json

# Message logs (if event listener used)
./message-logs.json

# HTML dashboard
./teleporter-monitor.html

# Test reports
./test-report-*.md
./test-report-*.json
./test-results-*.log
```

### Cleanup After Testing
```bash
# Complete cleanup
npm run shutdown

# Remove test artifacts
rm -f test-report-* test-results-* message-logs.json teleporter-monitor.html

# Verify clean state
avalanche network status  # Should show "network is not running"
```

## Integration with External Tools

### Monitoring Integration
```bash
# Export test results to monitoring systems
cat test-report-*.json | jq '.test_run.success_rate'

# WebSocket integration for real-time monitoring
# Connect to ws://localhost:8080 from external tools
```

### API Integration
```bash
# Use REST API in external applications
curl -X POST http://localhost:3000/send-message \
  -H "Content-Type: application/json" \
  -d '{"fromNetwork":"subnet1","toNetwork":"subnet2","message":"External app message"}'
```

## Next Steps

After successful testing:

1. **Review Reports** - Analyze test results and performance metrics
2. **Customize Components** - Modify listeners and senders for your use case
3. **Deploy to Testnet** - Adapt configuration for Fuji testnet
4. **Production Planning** - Review security and scaling considerations

For production deployment guidance, see [REAL_WORLD_USAGE.md](./REAL_WORLD_USAGE.md).
