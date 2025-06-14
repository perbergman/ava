# Avalanche Teleporter Project Context

## Project Overview
This project sets up Avalanche L1s (formerly subnets) with Teleporter (ICM - Inter-Chain Messaging) for cross-chain communication testing on macOS using native avalanche-cli.

## Key Components
- **Avalanche L1s**: Two sovereign L1 blockchains (subnet1 and subnet2) with Proof-of-Authority consensus
- **Teleporter/ICM**: Cross-chain messaging protocol for communication between L1s
- **ICM Relayer**: Service that delivers messages between chains
- **Subnet-EVM**: Simplified EVM-compatible blockchain VM

## Project Structure
```
/Users/perjbergman/Downloads/ava/
├── setup-avalanche-teleporter.sh    # Main setup script
├── test-teleporter-messaging.js      # Test cross-chain messaging
├── shutdown-avalanche.sh             # Clean shutdown script
├── network-config.json              # Generated network configuration
├── package.json                     # Node.js dependencies
├── README.md                        # User documentation
└── CLAUDE.md                        # This file - project context
```

## Complete Setup Process
1. **Prerequisites**: 
   - Install avalanche-cli from https://docs.avax.network/tooling/cli-guides/install-avalanche-cli
   - Install Node.js for running tests
   - Run `npm install` to install dependencies

2. **Run setup**: `./setup-avalanche-teleporter.sh`
   - Cleans any existing network with `--hard` flag
   - Starts Avalanche network with 2 primary nodes
   - Creates and deploys subnet1 (chain ID: 10001, token: SUB1)
   - Creates and deploys subnet2 (chain ID: 10002, token: SUB2)
   - Converts subnets to sovereign L1s
   - Deploys Teleporter contracts on all chains
   - Starts ICM Relayer for message delivery
   - Generates network-config.json with RPC endpoints and contract addresses

## Network Configuration
The setup script extracts network information and saves it to `network-config.json`:
- **Subnet1 RPC**: Dynamic port (e.g., http://127.0.0.1:53862/ext/bc/{blockchainId}/rpc)
- **Subnet2 RPC**: Dynamic port (e.g., http://127.0.0.1:54359/ext/bc/{blockchainId}/rpc)
- **C-Chain RPC**: http://127.0.0.1:9650/ext/bc/C/rpc
- **Teleporter Address**: 0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf (same on all chains)
- **Registry Address**: 0xc7c252313C7894Ba5452ea856A057a957e19DBeB
- **Main Account (ewoq)**: 0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC (1M tokens on each chain)

## Testing
Run `npm test` or `node test-teleporter-messaging.js` to:
- Check account balances on all chains
- Send messages between subnet1 ↔ subnet2
- Send messages from C-Chain → subnets
- Verify message delivery through the relayer
- Typical delivery times: 100-200ms for L1↔L1, 4-5s for C-Chain→L1

## Complete Shutdown
Run `./shutdown-avalanche.sh` to:
- Stop all network nodes
- Stop local subnet nodes individually
- Kill all avalanche-related processes (avalanchego, avalanche-cli, awm-relayer, icm-relayer, subnet-evm)
- Clean up network files with `--hard` flag
- Remove local subnet directories
- Clean up run directories

## Known Issues & Solutions
1. **RPC URL Extraction**: The setup script sometimes fails to properly extract RPC URLs from avalanche-cli output. If network-config.json has invalid RPC URLs (like "RPC Endpoint" or "|"), manually update with correct URLs from setup output.

2. **Setup Script Improvements Needed**:
   - Better parsing of avalanche-cli output to extract RPC URLs
   - Consider using JSON output format if available
   - Add validation of extracted values before writing config

3. **Incomplete Shutdown**: Previous versions didn't stop all processes. Current version handles:
   - Network nodes
   - Local subnet nodes
   - All related processes
   - Complete directory cleanup

## Key Technical Details
- Uses BLS signature aggregation for message validation
- Warp messaging system for cross-chain communication
- PoA validator management through smart contracts
- Each L1 runs on its own local node with separate ports
- Message delivery handled by ICM Relayer service

## Important Commands
```bash
# Check network status
avalanche network status

# List deployed blockchains
avalanche blockchain list

# Describe a blockchain (get RPC URL, blockchain ID, etc.)
avalanche blockchain describe subnet1
avalanche blockchain describe subnet2

# View relayer logs
tail -f ~/.avalanche-cli/runs/network_*/awm-relayer.log

# Check running processes
ps aux | grep avalanche
```

## Architecture
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Subnet1   │     │   Subnet2   │     │   C-Chain   │
│  (L1 PoA)   │     │  (L1 PoA)   │     │   (Primary) │
│ Chain:10001 │     │ Chain:10002 │     │ Chain:43112 │
│             │     │             │     │             │
│ Teleporter  │────▶│ Teleporter  │────▶│ Teleporter  │
└─────────────┘     └─────────────┘     └─────────────┘
       ▲                    ▲                    ▲
       └────────────────────┴────────────────────┘
                     ICM Relayer Service
```

## Full Cycle Workflow
1. Run `./shutdown-avalanche.sh` to ensure clean state
2. Run `./setup-avalanche-teleporter.sh` to create network
3. Wait for "Setup complete!" message
4. Run `npm test` to verify cross-chain messaging
5. Run `./shutdown-avalanche.sh` when done

## Accounts and Keys
- **Main Account (ewoq)**: Pre-funded with 1M tokens on each chain
- **Teleporter Deployer**: Used for contract deployment
- **Relayer Account**: Used by ICM relayer service
- **Validator Manager Owner**: Controls PoA validator set