# Avalanche Teleporter Demo

This project demonstrates cross-chain messaging using Avalanche's Teleporter (ICM - Inter-Chain Messaging) protocol.

## Overview

Teleporter enables secure message passing between different Avalanche L1s (formerly subnets). This demo sets up:
- Two EVM-based L1s (Subnet1 and Subnet2) with Proof-of-Authority consensus
- Teleporter smart contracts deployed on each L1 and C-Chain
- An ICM relayer to facilitate message delivery
- Test scripts to send messages between chains

## Prerequisites

### 1. Install avalanche-cli on macOS

Choose one of these methods:

#### Option A: Using Homebrew (Recommended)
```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install avalanche-cli
brew install ava-labs/tap/avalanche-cli

# Verify installation
avalanche --version
```

#### Option B: Using curl
```bash
# Download and install
curl -sSfL https://raw.githubusercontent.com/ava-labs/avalanche-cli/main/scripts/install.sh | sh -s

# Add to PATH (add this to your ~/.zshrc or ~/.bash_profile)
export PATH=$PATH:~/bin

# Verify installation
avalanche --version
```

#### Option C: Manual Download
```bash
# Download the latest release for macOS ARM64 (Apple Silicon)
curl -L https://github.com/ava-labs/avalanche-cli/releases/latest/download/avalanche-cli_darwin_arm64.tar.gz -o avalanche-cli.tar.gz

# Or for macOS Intel
curl -L https://github.com/ava-labs/avalanche-cli/releases/latest/download/avalanche-cli_darwin_amd64.tar.gz -o avalanche-cli.tar.gz

# Extract and install
tar -xzf avalanche-cli.tar.gz
sudo mv bin/avalanche /usr/local/bin/
rm -rf avalanche-cli.tar.gz bin/

# Verify installation
avalanche --version
```

### 2. Other Requirements

- **Node.js**: v16 or higher
  ```bash
  # Install with Homebrew
  brew install node
  
  # Or download from https://nodejs.org
  ```

- **Git**: For cloning the repository
  ```bash
  # Usually pre-installed on macOS
  git --version
  ```

## Quick Start

```bash
# 1. Install dependencies
npm install

# 2. Setup the network (creates 2 L1s with Teleporter)
npm run setup

# 3. Run tests (send messages between chains)
npm test

# 4. Shutdown when done
npm run shutdown
```

## Network Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Subnet1      │     │    Subnet2      │     │    C-Chain      │
│  Chain ID: 10001│     │  Chain ID: 10002│     │  Chain ID: 43112│
│  Token: SUB1    │     │  Token: SUB2    │     │  Token: AVAX    │
│                 │     │                 │     │                 │
│  Teleporter ◄───┼─────┼──► Teleporter ◄─┼─────┼──► Teleporter  │
│  0x253b2784...  │     │  0x253b2784...  │     │  0x253b2784...  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         ▲                       ▲                       ▲
         └───────────────────────┴───────────────────────┘
                         ICM Relayer Service
```

## Key Components

### 1. **Teleporter Contract** (`0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf`)
   - Deployed on all chains at the same address
   - Handles message sending and receiving
   - Emits events that the relayer monitors

### 2. **ICM Relayer**
   - Monitors Teleporter events on source chains
   - Collects validator signatures
   - Delivers messages to destination chains
   - Typical delivery time: 5-6 seconds

### 3. **Registry Contracts**
   - Subnet1/2: `0xc7c252313C7894Ba5452ea856A057a957e19DBeB`
   - C-Chain: `0x17aB05351fC94a1a67Bf3f56DdbB941aE6c63E25`

## Accounts

| Account | Address | Purpose |
|---------|---------|---------|
| Main (ewoq) | `0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC` | Funded with 1M tokens on each chain |
| Teleporter Deployer | `0x9453bf548cc94700fE701793181b85092151e527` | Used for ICM deployments |
| Relayer | `0x5579f30992B3c870648779b69112cA0D8f3dD822` | Pays for message delivery gas |
| Validator Manager | `0x618FEdD9A45a8C456812ecAAE70C671c6249DfaC` | Controls PoA validators |

Private keys are stored in `network-config.json` (⚠️ TEST ONLY - never use in production!)

## Scripts

### `setup-avalanche-teleporter.sh`
- Cleans any existing network
- Starts a local Avalanche network
- Creates and deploys 2 L1s with PoA consensus
- Deploys Teleporter contracts
- Starts the ICM relayer
- Saves configuration to `network-config.json`

### `test-teleporter-messaging.js`
- Sends test messages between chains
- Verifies delivery
- Shows end-to-end timing

### `shutdown-avalanche.sh`
- Stops all network nodes
- Kills relayer processes
- Cleans up resources

## Message Flow

1. **Send Message**: Call `sendCrossChainMessage` on source chain's Teleporter
2. **Event Emission**: `SendCrossChainMessage` event emitted
3. **Relayer Detection**: ICM relayer detects the event
4. **Signature Collection**: Relayer collects validator signatures (BLS aggregation)
5. **Message Delivery**: Relayer calls `receiveCrossChainMessage` on destination
6. **Event Confirmation**: `ReceiveCrossChainMessage` event confirms delivery

## Development

### Check Network Status
```bash
avalanche network status
avalanche blockchain list
```

### View Logs
```bash
# Relayer logs
tail -f ~/.avalanche-cli/runs/LocalNetwork/local-relayer/icm-relayer.log

# Node logs
tail -f ~/.avalanche-cli/runs/network_*/NodeID-*/logs/main.log
```

### Manual Testing with curl
```bash
# Check chain ID
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:PORT/ext/bc/BLOCKCHAIN_ID/rpc
```

## Real-World Usage

For production scenarios where client and server are separate:
- **Event Listeners**: `npm run listen` - Monitor messages across chains
- **Message Sender CLI/API**: `npm run send` or `npm run send:server`
- **WebSocket Monitor**: `npm run monitor` - Real-time message feed

See [REAL_WORLD_USAGE.md](./REAL_WORLD_USAGE.md) for detailed patterns and examples.

## UI Options

### 1. **Core Wallet** (https://core.app)
   - Official Avalanche wallet
   - Add custom networks using RPC URLs from `network-config.json`
   - Import test accounts using private keys

### 2. **MetaMask**
   - Add networks manually:
     - Network Name: Subnet1/Subnet2
     - RPC URL: From `network-config.json`
     - Chain ID: 10001/10002
     - Currency Symbol: SUB1/SUB2

### 3. **Avalanche Explorer**
   - For testnet/mainnet: https://subnets.avax.network
   - Local networks: Use `cast` or `eth-cli` for basic queries

### 4. **Custom DApp**
   - Build a simple web interface using ethers.js
   - Connect to Teleporter contracts
   - Example: https://github.com/ava-labs/teleporter-demo-app

## Troubleshooting

### Message Not Delivered
1. Check relayer logs for errors
2. Ensure nodes are synced: `avalanche blockchain describe subnet1`
3. Verify sufficient gas on destination chain

### Port Conflicts
- Default ports: 9650 (node1), 9652 (node2)
- Subnet nodes use dynamic ports (check `network-config.json`)

### Clean Start
```bash
npm run shutdown
avalanche network clean --hard
npm run setup
```

## Resources

- [Teleporter Documentation](https://docs.avax.network/cross-chain/teleporter)
- [Avalanche CLI Guide](https://docs.avax.network/tooling/cli-guides)
- [ICM (Inter-Chain Messaging)](https://docs.avax.network/learn/avalanche/icm)
- [Subnet-EVM](https://github.com/ava-labs/subnet-evm)

## Security Notice

⚠️ **This setup is for development/testing only!**
- Uses well-known test private keys
- Staking is disabled
- Single-node validators
- Not suitable for production use

For production deployments, see the official Avalanche documentation.