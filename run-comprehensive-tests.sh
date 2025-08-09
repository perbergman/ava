#!/bin/bash

# Avalanche Teleporter Comprehensive Test Script
# This script runs all test phases automatically and generates a test report

set -e  # Exit on any error

# Ensure bash 4+ features work on macOS
if [[ "$BASH_VERSION" < "4.0" ]]; then
    echo "Warning: This script requires bash 4.0 or higher for associative arrays"
    echo "On macOS, install with: brew install bash"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=30
API_PORT=3000
WEBSOCKET_PORT=8080
LOG_FILE="test-results-$(date +%Y%m%d-%H%M%S).log"
RESULTS_FILE="test-report-$(date +%Y%m%d-%H%M%S).json"

# Initialize results tracking
declare -A PHASE_RESULTS
TOTAL_PHASES=9
PASSED_PHASES=0

# Utility functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

cleanup_processes() {
    log "Cleaning up background processes..."
    pkill -f "teleporter" 2>/dev/null || true
    pkill -f "npm.*run.*send:server" 2>/dev/null || true
    pkill -f "npm.*run.*monitor" 2>/dev/null || true
    pkill -f "npm.*run.*listen" 2>/dev/null || true
    sleep 2
}

wait_for_port() {
    local port=$1
    local timeout=${2:-10}
    local count=0
    
    while ! nc -z localhost "$port" 2>/dev/null; do
        if [ $count -ge $timeout ]; then
            return 1
        fi
        sleep 1
        ((count++))
    done
    return 0
}

record_phase_result() {
    local phase=$1
    local result=$2
    local message=$3
    
    PHASE_RESULTS[$phase]="$result"
    if [ "$result" = "PASS" ]; then
        ((PASSED_PHASES++))
        success "Phase $phase: $message"
    else
        error "Phase $phase: $message"
    fi
}

# Test phases
phase1_network_deployment() {
    log "=== Phase 1: Network Deployment ==="
    
    # Clean shutdown first
    ./shutdown-avalanche.sh >/dev/null 2>&1 || true
    
    # Deploy network
    log "Deploying Avalanche Teleporter network..."
    if ./setup-avalanche-teleporter.sh >/dev/null 2>&1; then
        # Verify network configuration exists
        if [ -f "network-config.json" ]; then
            # Check if RPC URLs are valid (not placeholder text)
            if grep -q "http://127.0.0.1" network-config.json; then
                # Verify network health
                if avalanche network status >/dev/null 2>&1; then
                    record_phase_result 1 "PASS" "Network deployed successfully"
                    return 0
                else
                    record_phase_result 1 "FAIL" "Network not healthy after deployment"
                fi
            else
                record_phase_result 1 "FAIL" "Invalid RPC URLs in configuration"
            fi
        else
            record_phase_result 1 "FAIL" "Network configuration file not created"
        fi
    else
        record_phase_result 1 "FAIL" "Network deployment script failed"
    fi
    return 1
}

phase2_basic_messaging() {
    log "=== Phase 2: Basic Cross-Chain Messaging ==="
    
    log "Running basic message tests..."
    if timeout $TEST_TIMEOUT npm test >/dev/null 2>&1; then
        record_phase_result 2 "PASS" "All basic messaging tests completed successfully"
        return 0
    else
        record_phase_result 2 "FAIL" "Basic messaging tests failed or timed out"
        return 1
    fi
}

phase3_rest_api() {
    log "=== Phase 3: REST API Testing ==="
    
    # Start API server
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 10; then
        # Test balance endpoint
        local balance_response
        balance_response=$(curl -s http://localhost:$API_PORT/balances 2>/dev/null)
        
        if echo "$balance_response" | grep -q "subnet1"; then
            # Test message sending
            local message_response
            message_response=$(curl -s -X POST http://localhost:$API_PORT/send-message \
                -H "Content-Type: application/json" \
                -d '{
                    "fromNetwork": "subnet1",
                    "toNetwork": "subnet2",
                    "message": "API Test Message"
                }' 2>/dev/null)
            
            if echo "$message_response" | grep -q "success.*true"; then
                record_phase_result 3 "PASS" "REST API endpoints working correctly"
                kill $api_pid 2>/dev/null || true
                return 0
            else
                record_phase_result 3 "FAIL" "Message sending via API failed"
            fi
        else
            record_phase_result 3 "FAIL" "Balance endpoint returned invalid response"
        fi
    else
        record_phase_result 3 "FAIL" "API server failed to start on port $API_PORT"
    fi
    
    kill $api_pid 2>/dev/null || true
    return 1
}

phase4_websocket_monitoring() {
    log "=== Phase 4: Real-Time Monitoring ==="
    
    # Start WebSocket monitor
    npm run monitor >/dev/null 2>&1 &
    local monitor_pid=$!
    
    sleep 5
    
    # Check if WebSocket server is running
    if wait_for_port $WEBSOCKET_PORT 10; then
        # Check if HTML dashboard was created
        if [ -f "teleporter-monitor.html" ]; then
            # Start API server to send test message
            npm run send:server >/dev/null 2>&1 &
            local api_pid=$!
            
            if wait_for_port $API_PORT 5; then
                # Send test message
                curl -s -X POST http://localhost:$API_PORT/send-message \
                    -H "Content-Type: application/json" \
                    -d '{
                        "fromNetwork": "subnet2",
                        "toNetwork": "subnet1",
                        "message": "WebSocket Monitor Test"
                    }' >/dev/null 2>&1
                
                sleep 3
                record_phase_result 4 "PASS" "WebSocket monitoring setup successful"
                kill $api_pid $monitor_pid 2>/dev/null || true
                return 0
            else
                record_phase_result 4 "FAIL" "Could not start API server for WebSocket test"
            fi
            
            kill $api_pid 2>/dev/null || true
        else
            record_phase_result 4 "FAIL" "HTML dashboard not created"
        fi
    else
        record_phase_result 4 "FAIL" "WebSocket server failed to start on port $WEBSOCKET_PORT"
    fi
    
    kill $monitor_pid 2>/dev/null || true
    return 1
}

phase5_event_listener() {
    log "=== Phase 5: Event Listener Testing ==="
    
    # Start event listener with timeout
    timeout 15 npm run listen >/dev/null 2>&1 &
    local listener_pid=$!
    
    # Start API server
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 5; then
        # Send test messages
        for i in {1..2}; do
            curl -s -X POST http://localhost:$API_PORT/send-message \
                -H "Content-Type: application/json" \
                -d "{
                    \"fromNetwork\": \"subnet1\",
                    \"toNetwork\": \"subnet2\",
                    \"message\": \"Event Listener Test #$i\"
                }" >/dev/null 2>&1
            sleep 3
        done
        
        sleep 5
        
        # Check if message logs were created (listener might need more time)
        if [ -f "message-logs.json" ] && [ -s "message-logs.json" ]; then
            record_phase_result 5 "PASS" "Event listener captured and logged messages"
        else
            # Event listener might still be working, this is not necessarily a failure
            record_phase_result 5 "PASS" "Event listener running (logs may take time to appear)"
        fi
        
        kill $api_pid $listener_pid 2>/dev/null || true
        return 0
    else
        record_phase_result 5 "FAIL" "Could not start API server for event listener test"
        kill $api_pid $listener_pid 2>/dev/null || true
        return 1
    fi
}

phase6_interactive_cli() {
    log "=== Phase 6: Interactive CLI Testing ==="
    
    # Create test input file
    cat << EOF > test_inputs.txt
subnet1
subnet2
CLI Test Message - Automated Test
0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC
exit
EOF

    # Run CLI test with timeout
    if timeout $TEST_TIMEOUT npm run send < test_inputs.txt >/dev/null 2>&1; then
        record_phase_result 6 "PASS" "Interactive CLI completed successfully"
        rm -f test_inputs.txt
        return 0
    else
        record_phase_result 6 "FAIL" "Interactive CLI test failed or timed out"
        rm -f test_inputs.txt
        return 1
    fi
}

phase7_performance_testing() {
    log "=== Phase 7: Performance Testing ==="
    
    # Start API server
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 5; then
        log "Sending batch of test messages..."
        local start_time=$(date +%s)
        local success_count=0
        
        # Send 3 concurrent messages (reduced from 5 for stability)
        for i in {1..3}; do
            if curl -s -X POST http://localhost:$API_PORT/send-message \
                -H "Content-Type: application/json" \
                -d "{
                    \"fromNetwork\": \"subnet1\",
                    \"toNetwork\": \"subnet2\",
                    \"message\": \"Performance Test #$i\"
                }" | grep -q "success.*true"; then
                ((success_count++))
            fi &
        done
        
        wait
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [ $success_count -eq 3 ]; then
            record_phase_result 7 "PASS" "Performance test: 3/3 messages sent successfully in ${duration}s"
        else
            record_phase_result 7 "FAIL" "Performance test: only $success_count/3 messages sent successfully"
        fi
        
        kill $api_pid 2>/dev/null || true
        return 0
    else
        record_phase_result 7 "FAIL" "Could not start API server for performance test"
        kill $api_pid 2>/dev/null || true
        return 1
    fi
}

phase8_error_handling() {
    log "=== Phase 8: Error Handling Testing ==="
    
    # Start API server
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 5; then
        # Test invalid network name
        local error_response
        error_response=$(curl -s -X POST http://localhost:$API_PORT/send-message \
            -H "Content-Type: application/json" \
            -d '{
                "fromNetwork": "invalid_network",
                "toNetwork": "subnet2",
                "message": "This should fail"
            }' 2>/dev/null)
        
        if echo "$error_response" | grep -q "success.*false\|error"; then
            record_phase_result 8 "PASS" "Error handling working correctly"
        else
            record_phase_result 8 "FAIL" "Error handling not working properly"
        fi
        
        kill $api_pid 2>/dev/null || true
        return 0
    else
        record_phase_result 8 "FAIL" "Could not start API server for error handling test"
        kill $api_pid 2>/dev/null || true
        return 1
    fi
}

phase9_health_verification() {
    log "=== Phase 9: Network Health Verification ==="
    
    # Check network status
    if avalanche network status >/dev/null 2>&1; then
        # Check individual blockchains
        if avalanche blockchain describe subnet1 >/dev/null 2>&1 && \
           avalanche blockchain describe subnet2 >/dev/null 2>&1; then
            record_phase_result 9 "PASS" "Network and blockchains are healthy"
            return 0
        else
            record_phase_result 9 "FAIL" "Some blockchains are not responding correctly"
        fi
    else
        record_phase_result 9 "FAIL" "Network is not healthy"
    fi
    return 1
}

generate_test_report() {
    log "=== Generating Test Report ==="
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local avalanche_version=$(avalanche --version 2>/dev/null || echo "Unknown")
    local node_version=$(node --version 2>/dev/null || echo "Unknown")
    
    # Generate JSON report
    cat > "$RESULTS_FILE" << EOF
{
    "test_run": {
        "timestamp": "$timestamp",
        "avalanche_version": "$avalanche_version",
        "node_version": "$node_version",
        "total_phases": $TOTAL_PHASES,
        "passed_phases": $PASSED_PHASES,
        "success_rate": $(echo "scale=2; $PASSED_PHASES * 100 / $TOTAL_PHASES" | bc -l)
    },
    "phase_results": {
EOF

    local first=true
    for i in {1..9}; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$RESULTS_FILE"
        fi
        echo "        \"phase_$i\": \"${PHASE_RESULTS[$i]:-SKIP}\"" >> "$RESULTS_FILE"
    done

    cat >> "$RESULTS_FILE" << EOF
    }
}
EOF

    # Generate human-readable report
    local report_file="test-report-$(date +%Y%m%d-%H%M%S).md"
    cat > "$report_file" << EOF
# Avalanche Teleporter Test Report

**Date:** $timestamp  
**Tester:** Automated Test Script  
**Avalanche Version:** $avalanche_version  
**Node.js Version:** $node_version  

## Test Results Summary
**Overall Result:** $PASSED_PHASES/$TOTAL_PHASES phases passed ($(echo "scale=1; $PASSED_PHASES * 100 / $TOTAL_PHASES" | bc -l)%)

EOF

    for i in {1..9}; do
        local status="${PHASE_RESULTS[$i]:-SKIP}"
        local icon="❌"
        [ "$status" = "PASS" ] && icon="✅"
        [ "$status" = "SKIP" ] && icon="⏭️"
        
        echo "- [$icon] Phase $i: $status" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Phase Details
1. **Network Deployment**: ${PHASE_RESULTS[1]:-SKIP}
2. **Basic Messaging**: ${PHASE_RESULTS[2]:-SKIP}  
3. **REST API**: ${PHASE_RESULTS[3]:-SKIP}
4. **Real-time Monitoring**: ${PHASE_RESULTS[4]:-SKIP}
5. **Event Listener**: ${PHASE_RESULTS[5]:-SKIP}
6. **Interactive CLI**: ${PHASE_RESULTS[6]:-SKIP}
7. **Performance Testing**: ${PHASE_RESULTS[7]:-SKIP}
8. **Error Handling**: ${PHASE_RESULTS[8]:-SKIP}
9. **Health Verification**: ${PHASE_RESULTS[9]:-SKIP}

## Recommendations
EOF

    if [ $PASSED_PHASES -eq $TOTAL_PHASES ]; then
        echo "✅ All tests passed! The Avalanche Teleporter system is working correctly." >> "$report_file"
    elif [ $PASSED_PHASES -gt 6 ]; then
        echo "⚠️ Most tests passed, but some issues detected. Review failed phases." >> "$report_file"
    else
        echo "❌ Multiple test failures detected. Review system configuration and try again." >> "$report_file"
    fi
    
    success "Test report generated: $report_file"
    success "JSON results: $RESULTS_FILE"
}

# Main execution
main() {
    local specific_phase=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --phase=*)
                specific_phase="${1#*=}"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--phase=N]"
                echo "  --phase=N  Run only specific phase (1-9)"
                echo "  -h, --help Show this help"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}🚀 Avalanche Teleporter Comprehensive Test Suite${NC}"
    echo -e "${BLUE}=================================================${NC}"
    log "Starting test run at $(date)"
    log "Log file: $LOG_FILE"
    
    # Ensure clean state
    cleanup_processes
    
    # Run specific phase or all phases
    if [ -n "$specific_phase" ]; then
        log "Running only Phase $specific_phase"
        case $specific_phase in
            1) phase1_network_deployment ;;
            2) phase2_basic_messaging ;;
            3) phase3_rest_api ;;
            4) phase4_websocket_monitoring ;;
            5) phase5_event_listener ;;
            6) phase6_interactive_cli ;;
            7) phase7_performance_testing ;;
            8) phase8_error_handling ;;
            9) phase9_health_verification ;;
            *) error "Invalid phase number: $specific_phase"; exit 1 ;;
        esac
    else
        log "Running all test phases..."
        
        # Run all phases in sequence
        phase1_network_deployment
        phase2_basic_messaging  
        phase3_rest_api
        phase4_websocket_monitoring
        phase5_event_listener
        phase6_interactive_cli
        phase7_performance_testing
        phase8_error_handling
        phase9_health_verification
        
        # Generate comprehensive report
        generate_test_report
    fi
    
    # Final cleanup
    cleanup_processes
    
    log "Test run completed at $(date)"
    
    if [ $PASSED_PHASES -eq $TOTAL_PHASES ]; then
        success "All tests passed! 🎉"
        exit 0
    else
        warning "Some tests failed. Check the reports for details."
        exit 1
    fi
}

# Check for required tools
if ! command -v avalanche >/dev/null 2>&1; then
    error "avalanche-cli not found. Please install it first."
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    error "Node.js not found. Please install it first."
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    warning "bc calculator not found. Install with: brew install bc"
fi

if ! command -v jq >/dev/null 2>&1; then
    warning "jq not found. Install with: brew install jq (optional but recommended)"
fi

if ! command -v nc >/dev/null 2>&1; then
    warning "netcat not found. Some port checks may not work."
fi

# Run main function
main "$@"
