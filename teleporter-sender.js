const ethers = require('ethers');
const fs = require('fs').promises;
const readline = require('readline');

// Teleporter ABI
const TELEPORTER_ABI = [
    "function sendCrossChainMessage(tuple(bytes32 destinationBlockchainID, address destinationAddress, tuple(address feeTokenAddress, uint256 amount) feeInfo, uint256 requiredGasLimit, address[] allowedRelayerAddresses, bytes message) message) returns (bytes32 messageID)"
];

class TeleporterSender {
    constructor(config) {
        this.config = config;
        this.providers = {};
        this.wallets = {};
        this.teleporters = {};
        
        // Initialize providers and wallets for each network
        for (const [networkName, network] of Object.entries(config.networks)) {
            this.providers[networkName] = new ethers.JsonRpcProvider(network.rpc);
            this.wallets[networkName] = new ethers.Wallet(
                config.accounts.main.privateKey,
                this.providers[networkName]
            );
            this.teleporters[networkName] = new ethers.Contract(
                config.contracts.teleporter,
                TELEPORTER_ABI,
                this.wallets[networkName]
            );
        }
    }

    async sendMessage(fromNetwork, toNetwork, message, destinationAddress = null) {
        console.log(`\n📤 Sending message from ${fromNetwork} to ${toNetwork}...`);
        
        const toNetworkConfig = this.config.networks[toNetwork];
        if (!toNetworkConfig) {
            throw new Error(`Network ${toNetwork} not found in config`);
        }

        // Use sender's address as destination if not specified
        if (!destinationAddress) {
            destinationAddress = this.wallets[fromNetwork].address;
        }

        // Prepare the message
        const encodedMessage = ethers.toUtf8Bytes(message);
        
        // Get the destination blockchain ID
        const destinationBlockchainID = toNetworkConfig.blockchainIdHex || toNetworkConfig.blockchainId;
        
        console.log(`   Destination Chain: ${destinationBlockchainID}`);
        console.log(`   Destination Address: ${destinationAddress}`);
        console.log(`   Message: "${message}"`);

        try {
            // Send the cross-chain message
            const tx = await this.teleporters[fromNetwork].sendCrossChainMessage({
                destinationBlockchainID,
                destinationAddress,
                feeInfo: {
                    feeTokenAddress: ethers.ZeroAddress,
                    amount: 0
                },
                requiredGasLimit: 100000,
                allowedRelayerAddresses: [],
                message: encodedMessage
            });

            console.log(`   Tx Hash: ${tx.hash}`);
            console.log(`   ⏳ Waiting for confirmation...`);
            
            const receipt = await tx.wait();
            console.log(`   ✅ Confirmed in block ${receipt.blockNumber}`);
            console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
            
            // Extract message ID from events
            const messageId = receipt.logs[0]?.topics[1];
            if (messageId) {
                console.log(`   Message ID: ${messageId}`);
            }
            
            return {
                txHash: tx.hash,
                blockNumber: receipt.blockNumber,
                messageId,
                gasUsed: receipt.gasUsed.toString()
            };
        } catch (error) {
            console.error(`   ❌ Error: ${error.message}`);
            throw error;
        }
    }

    async getBalance(network) {
        const balance = await this.providers[network].getBalance(this.wallets[network].address);
        const symbol = this.config.networks[network].token || 'ETH';
        return `${ethers.formatEther(balance)} ${symbol}`;
    }
}

// Interactive CLI for sending messages
async function interactiveCLI() {
    const config = JSON.parse(await fs.readFile('network-config.json', 'utf8'));
    const sender = new TeleporterSender(config);
    
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    const question = (query) => new Promise((resolve) => rl.question(query, resolve));

    console.log('🚀 Teleporter Message Sender');
    console.log('============================\n');

    // Show available networks
    console.log('Available networks:');
    for (const network of Object.keys(config.networks)) {
        const balance = await sender.getBalance(network);
        console.log(`  - ${network}: ${balance}`);
    }

    while (true) {
        console.log('\n' + '─'.repeat(50));
        
        const fromNetwork = await question('\n📍 From network (or "exit" to quit): ');
        if (fromNetwork.toLowerCase() === 'exit') break;
        
        const toNetwork = await question('📍 To network: ');
        const message = await question('💬 Message: ');
        const customDest = await question('📍 Custom destination address (press Enter for default): ');
        
        try {
            const result = await sender.sendMessage(
                fromNetwork,
                toNetwork,
                message,
                customDest || null
            );
            
            console.log('\n✅ Message sent successfully!');
            console.log(`   Track delivery with Message ID: ${result.messageId}`);
        } catch (error) {
            console.error('\n❌ Failed to send message:', error.message);
        }
    }

    rl.close();
    console.log('\n👋 Goodbye!\n');
}

// API Server example
async function startAPIServer() {
    const express = require('express');
    const app = express();
    app.use(express.json());
    
    const config = JSON.parse(await fs.readFile('network-config.json', 'utf8'));
    const sender = new TeleporterSender(config);
    
    // Send message endpoint
    app.post('/send-message', async (req, res) => {
        const { fromNetwork, toNetwork, message, destinationAddress } = req.body;
        
        try {
            const result = await sender.sendMessage(
                fromNetwork,
                toNetwork,
                message,
                destinationAddress
            );
            res.json({ success: true, result });
        } catch (error) {
            res.status(500).json({ success: false, error: error.message });
        }
    });
    
    // Get balances endpoint
    app.get('/balances', async (req, res) => {
        const balances = {};
        for (const network of Object.keys(config.networks)) {
            balances[network] = await sender.getBalance(network);
        }
        res.json(balances);
    });
    
    const PORT = process.env.PORT || 3000;
    app.listen(PORT, () => {
        console.log(`\n🌐 Teleporter API Server running on http://localhost:${PORT}`);
        console.log('\nEndpoints:');
        console.log('  POST /send-message - Send a cross-chain message');
        console.log('  GET /balances - Get account balances\n');
    });
}

// Main function
async function main() {
    const args = process.argv.slice(2);
    
    if (args.includes('--server')) {
        // Check if express is installed
        try {
            require('express');
            await startAPIServer();
        } catch (error) {
            console.error('Please install express: npm install express');
            process.exit(1);
        }
    } else {
        // Run interactive CLI
        await interactiveCLI();
    }
}

// Run the application
main().catch(console.error);