#!/bin/bash

echo "🛑 Shutting down Avalanche network..."
echo "===================================="
echo ""

# Stop the network
echo "📴 Stopping network nodes..."
avalanche network stop 2>/dev/null || true

# Stop local subnet nodes
echo "🔌 Stopping local subnet nodes..."
for subnet_dir in ~/.avalanche-cli/local/*/; do
    if [ -d "$subnet_dir" ]; then
        subnet_name=$(basename "$subnet_dir")
        echo "   Stopping $subnet_name..."
        avalanche node stop "$subnet_name" 2>/dev/null || true
    fi
done

# Stop any docker containers
echo "🐳 Stopping Docker containers..."
docker-compose down 2>/dev/null || true
docker stop $(docker ps -q --filter "ancestor=avaplatform/avalanchego") 2>/dev/null || true
docker stop $(docker ps -q --filter "ancestor=avaplatform/avalanche-cli") 2>/dev/null || true

# Kill any remaining avalanche processes
echo "🔪 Killing any remaining processes..."
pkill -f avalanchego 2>/dev/null || true
pkill -f avalanche-cli 2>/dev/null || true
pkill -f awm-relayer 2>/dev/null || true
pkill -f icm-relayer 2>/dev/null || true
pkill -f subnet-evm 2>/dev/null || true
pkill -f signature-aggregator 2>/dev/null || true

# Clean up network files
echo "🧹 Cleaning up..."
avalanche network clean --hard 2>/dev/null || true

# Remove local subnet directories
rm -rf ~/.avalanche-cli/local/subnet1-local-node-local-network 2>/dev/null || true
rm -rf ~/.avalanche-cli/local/subnet2-local-node-local-network 2>/dev/null || true

# Clean up any remaining run directories
rm -rf ~/.avalanche-cli/runs/network_* 2>/dev/null || true

echo ""
echo "✅ Shutdown complete!"
echo ""
echo "To restart, run: ./setup-avalanche-teleporter.sh"
echo ""