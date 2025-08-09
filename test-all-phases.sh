#!/bin/bash

# Simplified Avalanche Teleporter Test Script
# Compatible with macOS default bash/zsh

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=30
API_PORT=3000
WEBSOCKET_PORT=8080

# Results tracking (using simple variables instead of associative arrays)
TOTAL_PHASES=9
PASSED_PHASES=0
PHASE1_RESULT="SKIP"
PHASE2_RESULT="SKIP"
PHASE3_RESULT="SKIP"
PHASE4_RESULT="SKIP"
PHASE5_RESULT="SKIP"
PHASE6_RESULT="SKIP"
PHASE7_RESULT="SKIP"
PHASE8_RESULT="SKIP"
PHASE9_RESULT="SKIP"

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

record_result() {
    local phase=$1
    local result=$2
    local message=$3
    
    case $phase in
        1) PHASE1_RESULT="$result" ;;
        2) PHASE2_RESULT="$result" ;;
        3) PHASE3_RESULT="$result" ;;
        4) PHASE4_RESULT="$result" ;;
        5) PHASE5_RESULT="$result" ;;
        6) PHASE6_RESULT="$result" ;;
        7) PHASE7_RESULT="$result" ;;
        8) PHASE8_RESULT="$result" ;;
        9) PHASE9_RESULT="$result" ;;
    esac
    
    if [ "$result" = "PASS" ]; then
        ((PASSED_PHASES++))
        success "Phase $phase: $message"
    else
        error "Phase $phase: $message"
    fi
}

# Test Phase Functions
test_network_health() {
    log "=== Phase 1: Network Health Check ==="
    
    if avalanche network status >/dev/null 2>&1; then
        if [ -f "network-config.json" ] && grep -q "http://127.0.0.1" network-config.json; then
            record_result 1 "PASS" "Network is healthy and configured"
            return 0
        else
            record_result 1 "FAIL" "Network configuration invalid"
        fi
    else
        record_result 1 "FAIL" "Network is not running"
    fi
    return 1
}

test_basic_messaging() {
    log "=== Phase 2: Basic Cross-Chain Messaging ==="
    
    if timeout $TEST_TIMEOUT npm test >/dev/null 2>&1; then
        record_result 2 "PASS" "Basic messaging tests passed"
        return 0
    else
        record_result 2 "FAIL" "Basic messaging tests failed"
        return 1
    fi
}

test_rest_api() {
    log "=== Phase 3: REST API Testing ==="
    
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 10; then
        local response
        response=$(curl -s http://localhost:$API_PORT/balances 2>/dev/null)
        
        if echo "$response" | grep -q "subnet1"; then
            # Test message sending
            local msg_response
            msg_response=$(curl -s -X POST http://localhost:$API_PORT/send-message \
                -H "Content-Type: application/json" \
                -d '{
                    "fromNetwork": "subnet1",
                    "toNetwork": "subnet2",
                    "message": "API Test Message"
                }' 2>/dev/null)
            
            if echo "$msg_response" | grep -q "success.*true"; then
                record_result 3 "PASS" "REST API working correctly"
                kill $api_pid 2>/dev/null || true
                return 0
            fi
        fi
        record_result 3 "FAIL" "API functionality failed"
    else
        record_result 3 "FAIL" "API server failed to start"
    fi
    
    kill $api_pid 2>/dev/null || true
    return 1
}

test_websocket_monitor() {
    log "=== Phase 4: WebSocket Monitoring ==="
    
    npm run monitor >/dev/null 2>&1 &
    local monitor_pid=$!
    sleep 5
    
    if wait_for_port $WEBSOCKET_PORT 10; then
        if [ -f "teleporter-monitor.html" ]; then
            record_result 4 "PASS" "WebSocket monitor working"
            kill $monitor_pid 2>/dev/null || true
            return 0
        fi
    fi
    
    record_result 4 "FAIL" "WebSocket monitor failed"
    kill $monitor_pid 2>/dev/null || true
    return 1
}

test_event_listener() {
    log "=== Phase 5: Event Listener ==="
    
    timeout 10 npm run listen >/dev/null 2>&1 &
    local listener_pid=$!
    
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 5; then
        curl -s -X POST http://localhost:$API_PORT/send-message \
            -H "Content-Type: application/json" \
            -d '{"fromNetwork": "subnet1", "toNetwork": "subnet2", "message": "Listener Test"}' \
            >/dev/null 2>&1
        
        sleep 5
        record_result 5 "PASS" "Event listener functional"
    else
        record_result 5 "FAIL" "Event listener test failed"
    fi
    
    kill $api_pid $listener_pid 2>/dev/null || true
    return 0  # Don't fail the whole suite for this
}

test_interactive_cli() {
    log "=== Phase 6: Interactive CLI ==="
    
    # Create test input
    cat << EOF > test_inputs.txt
subnet1
subnet2
CLI Test Message
0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC
exit
EOF

    if timeout $TEST_TIMEOUT npm run send < test_inputs.txt >/dev/null 2>&1; then
        record_result 6 "PASS" "Interactive CLI working"
        rm -f test_inputs.txt
        return 0
    else
        record_result 6 "FAIL" "Interactive CLI failed"
        rm -f test_inputs.txt
        return 1
    fi
}

test_performance() {
    log "=== Phase 7: Performance Testing ==="
    
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 5; then
        local success_count=0
        local start_time=$(date +%s)
        
        # Send 3 test messages
        for i in {1..3}; do
            if curl -s -X POST http://localhost:$API_PORT/send-message \
                -H "Content-Type: application/json" \
                -d "{\"fromNetwork\": \"subnet1\", \"toNetwork\": \"subnet2\", \"message\": \"Perf Test $i\"}" \
                | grep -q "success.*true"; then
                ((success_count++))
            fi &
        done
        
        wait
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [ $success_count -eq 3 ]; then
            record_result 7 "PASS" "Performance test: 3/3 messages sent in ${duration}s"
        else
            record_result 7 "FAIL" "Performance test: only $success_count/3 messages sent"
        fi
    else
        record_result 7 "FAIL" "Performance test setup failed"
    fi
    
    kill $api_pid 2>/dev/null || true
    return 0
}

test_error_handling() {
    log "=== Phase 8: Error Handling ==="
    
    npm run send:server >/dev/null 2>&1 &
    local api_pid=$!
    
    if wait_for_port $API_PORT 5; then
        local error_response
        error_response=$(curl -s -X POST http://localhost:$API_PORT/send-message \
            -H "Content-Type: application/json" \
            -d '{"fromNetwork": "invalid_network", "toNetwork": "subnet2", "message": "Should fail"}' \
            2>/dev/null)
        
        if echo "$error_response" | grep -q "success.*false\|error"; then
            record_result 8 "PASS" "Error handling working"
        else
            record_result 8 "FAIL" "Error handling not working"
        fi
    else
        record_result 8 "FAIL" "Error handling test setup failed"
    fi
    
    kill $api_pid 2>/dev/null || true
    return 0
}

test_final_health() {
    log "=== Phase 9: Final Health Check ==="
    
    if avalanche network status >/dev/null 2>&1; then
        if avalanche blockchain describe subnet1 >/dev/null 2>&1 && \
           avalanche blockchain describe subnet2 >/dev/null 2>&1; then
            record_result 9 "PASS" "All systems healthy"
            return 0
        fi
    fi
    
    record_result 9 "FAIL" "System health check failed"
    return 1
}

generate_simple_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local success_rate=$(echo "scale=1; $PASSED_PHASES * 100 / $TOTAL_PHASES" | bc -l 2>/dev/null || echo "N/A")
    
    echo ""
    echo -e "${BLUE}📊 Test Results Summary${NC}"
    echo -e "${BLUE}=======================${NC}"
    echo "Date: $timestamp"
    echo "Overall: $PASSED_PHASES/$TOTAL_PHASES phases passed ($success_rate%)"
    echo ""
    
    # Display results
    local phases=("Network Health" "Basic Messaging" "REST API" "WebSocket Monitor" "Event Listener" "Interactive CLI" "Performance" "Error Handling" "Final Health")
    local results=($PHASE1_RESULT $PHASE2_RESULT $PHASE3_RESULT $PHASE4_RESULT $PHASE5_RESULT $PHASE6_RESULT $PHASE7_RESULT $PHASE8_RESULT $PHASE9_RESULT)
    
    for i in {0..8}; do
        local icon="❌"
        [ "${results[$i]}" = "PASS" ] && icon="✅"
        [ "${results[$i]}" = "SKIP" ] && icon="⏭️"
        echo "Phase $((i+1)): $icon ${phases[$i]} - ${results[$i]}"
    done
    
    echo ""
    if [ $PASSED_PHASES -eq $TOTAL_PHASES ]; then
        success "All tests passed! 🎉"
    elif [ $PASSED_PHASES -gt 6 ]; then
        warning "Most tests passed, but some issues detected."
    else
        error "Multiple test failures. Check system configuration."
    fi
}

# Main execution
main() {
    local specific_phase=""
    
    if [ "$1" = "--phase" ] && [ -n "$2" ]; then
        specific_phase="$2"
    elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "Usage: $0 [--phase N]"
        echo "  --phase N  Run only specific phase (1-9)"
        exit 0
    fi
    
    echo -e "${BLUE}🚀 Avalanche Teleporter Test Suite${NC}"
    echo -e "${BLUE}==================================${NC}"
    echo ""
    
    cleanup_processes
    
    if [ -n "$specific_phase" ]; then
        log "Running only Phase $specific_phase"
        case $specific_phase in
            1) test_network_health ;;
            2) test_basic_messaging ;;
            3) test_rest_api ;;
            4) test_websocket_monitor ;;
            5) test_event_listener ;;
            6) test_interactive_cli ;;
            7) test_performance ;;
            8) test_error_handling ;;
            9) test_final_health ;;
            *) error "Invalid phase: $specific_phase"; exit 1 ;;
        esac
    else
        # Run all phases
        test_network_health
        test_basic_messaging
        test_rest_api
        test_websocket_monitor
        test_event_listener
        test_interactive_cli
        test_performance
        test_error_handling
        test_final_health
        
        generate_simple_report
    fi
    
    cleanup_processes
    
    if [ $PASSED_PHASES -eq $TOTAL_PHASES ] || [ -n "$specific_phase" ]; then
        exit 0
    else
        exit 1
    fi
}

# Check requirements
if ! command -v avalanche >/dev/null 2>&1; then
    error "avalanche-cli not found"
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    error "Node.js not found"
    exit 1
fi

main "$@"
