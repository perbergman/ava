#!/bin/bash
set -e

echo "🚀 Avalanche Teleporter Setup Script"
echo "===================================="
echo ""

# Check if avalanche-cli is installed
if ! command -v avalanche &> /dev/null; then
    echo "❌ avalanche-cli is not installed. Please install it first."
    echo "   Visit: https://docs.avax.network/tooling/cli-guides/install-avalanche-cli"
    exit 1
fi

echo "✅ Found avalanche-cli at: $(which avalanche)"

# Clean up any existing network
echo ""
echo "🧹 Cleaning up any existing network..."
avalanche network clean --hard 2>/dev/null || true
rm -rf ~/.avalanche-cli/local/subnet1-local-node-local-network 2>/dev/null || true
rm -rf ~/.avalanche-cli/local/subnet2-local-node-local-network 2>/dev/null || true

# Start the network
echo ""
echo "🌐 Starting Avalanche network..."
avalanche network start

# Wait for network to be ready
echo ""
echo "⏳ Waiting for network to be ready..."
sleep 5

# Create and deploy subnet1
echo ""
echo "📦 Creating Subnet1 with PoA..."
avalanche blockchain create subnet1 \
    --evm \
    --proof-of-authority \
    --test-defaults \
    --validator-manager-owner 0x618FEdD9A45a8C456812ecAAE70C671c6249DfaC \
    --evm-chain-id 10001 \
    --evm-token SUB1 \
    -f

echo ""
echo "🚀 Deploying Subnet1..."
avalanche blockchain deploy subnet1 --local

# Create and deploy subnet2
echo ""
echo "📦 Creating Subnet2 with PoA..."
avalanche blockchain create subnet2 \
    --evm \
    --proof-of-authority \
    --test-defaults \
    --validator-manager-owner 0x618FEdD9A45a8C456812ecAAE70C671c6249DfaC \
    --evm-chain-id 10002 \
    --evm-token SUB2 \
    -f

echo ""
echo "🚀 Deploying Subnet2..."
avalanche blockchain deploy subnet2 --local

# Extract network information
echo ""
echo "📝 Extracting network information..."

# Get subnet1 info using text output
SUBNET1_OUTPUT=$(avalanche blockchain describe subnet1 2>/dev/null)
SUBNET1_RPC=$(echo "$SUBNET1_OUTPUT" | grep -E "RPC Endpoint|Network RPC URL" | head -1 | awk -F'|' '{print $3}' | xargs)
SUBNET1_BLOCKCHAIN_ID=$(echo "$SUBNET1_RPC" | sed -n 's|.*/ext/bc/\([^/]*\)/rpc.*|\1|p')

# Get subnet2 info using text output
SUBNET2_OUTPUT=$(avalanche blockchain describe subnet2 2>/dev/null)
SUBNET2_RPC=$(echo "$SUBNET2_OUTPUT" | grep -E "RPC Endpoint|Network RPC URL" | head -1 | awk -F'|' '{print $3}' | xargs)
SUBNET2_BLOCKCHAIN_ID=$(echo "$SUBNET2_RPC" | sed -n 's|.*/ext/bc/\([^/]*\)/rpc.*|\1|p')

# Get blockchain hex IDs by making RPC calls
SUBNET1_BLOCKCHAIN_ID_HEX=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' -H "Content-Type: application/json" "$SUBNET1_RPC" 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "0x2711")
SUBNET2_BLOCKCHAIN_ID_HEX=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' -H "Content-Type: application/json" "$SUBNET2_RPC" 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "0x2712")

# Validate that we got the RPC URLs
if [ -z "$SUBNET1_RPC" ] || [ "$SUBNET1_RPC" == "|" ]; then
    echo "⚠️  Warning: Could not extract subnet1 RPC URL properly"
    SUBNET1_RPC="http://127.0.0.1:9650/ext/bc/subnet1/rpc"
fi
if [ -z "$SUBNET2_RPC" ] || [ "$SUBNET2_RPC" == "|" ]; then
    echo "⚠️  Warning: Could not extract subnet2 RPC URL properly"
    SUBNET2_RPC="http://127.0.0.1:9650/ext/bc/subnet2/rpc"
fi

# Create network config file
cat > network-config.json << EOF
{
  "networks": {
    "subnet1": {
      "rpc": "${SUBNET1_RPC}",
      "chainId": 10001,
      "token": "SUB1",
      "blockchainId": "${SUBNET1_BLOCKCHAIN_ID}",
      "blockchainIdHex": "${SUBNET1_BLOCKCHAIN_ID_HEX}"
    },
    "subnet2": {
      "rpc": "${SUBNET2_RPC}",
      "chainId": 10002,
      "token": "SUB2",
      "blockchainId": "${SUBNET2_BLOCKCHAIN_ID}",
      "blockchainIdHex": "${SUBNET2_BLOCKCHAIN_ID_HEX}"
    },
    "cchain": {
      "rpc": "http://127.0.0.1:9650/ext/bc/C/rpc",
      "chainId": 43112
    }
  },
  "contracts": {
    "teleporter": "0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf",
    "registry": {
      "subnet1": "0xc7c252313C7894Ba5452ea856A057a957e19DBeB",
      "subnet2": "0xc7c252313C7894Ba5452ea856A057a957e19DBeB",
      "cchain": "0x17aB05351fC94a1a67Bf3f56DdbB941aE6c63E25"
    }
  },
  "accounts": {
    "main": {
      "address": "0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC",
      "privateKey": "56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027",
      "name": "ewoq"
    },
    "teleporter": {
      "address": "0x9453bf548cc94700fE701793181b85092151e527",
      "privateKey": "68da395fd8d6b1dec2f423a3b852975003f6d99e68a2d506df47a09feeb49629",
      "name": "cli-teleporter-deployer"
    },
    "relayer": {
      "address": "0x5579f30992B3c870648779b69112cA0D8f3dD822",
      "privateKey": "12a2686f185d1676527f79387fe57f6b7beee4c32cc51a020ec83a61741fa1f6",
      "name": "relayer"
    },
    "validatorManager": {
      "address": "0x618FEdD9A45a8C456812ecAAE70C671c6249DfaC",
      "name": "validator-manager-owner"
    }
  }
}
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "📊 Network Summary:"
echo "==================="
echo "Subnet1 RPC: ${SUBNET1_RPC}"
echo "Subnet2 RPC: ${SUBNET2_RPC}"
echo "C-Chain RPC: http://127.0.0.1:9650/ext/bc/C/rpc"
echo ""
echo "Teleporter Address: 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf"
echo ""
echo "Main Account (ewoq): 0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC"
echo "Balance: 1,000,000 tokens on each subnet"
echo ""
echo "📄 Network configuration saved to: network-config.json"
echo ""
echo "🚀 You can now run: npm test"
echo ""