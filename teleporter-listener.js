const ethers = require('ethers');
const fs = require('fs').promises;

// Teleporter ABI for event listening
const TELEPORTER_ABI = [
    "event ReceiveCrossChainMessage(bytes32 indexed messageID, bytes32 indexed sourceBlockchainID, address indexed deliverer, address relayerRewardAddress, tuple(bytes32 sourceBlockchainID, address originSenderAddress, bytes message) teleporterMessage)",
    "event SendCrossChainMessage(bytes32 indexed messageID, bytes32 indexed destinationBlockchainID, tuple(bytes32 destinationBlockchainID, address destinationAddress, tuple(address feeTokenAddress, uint256 amount) feeInfo, uint256 requiredGasLimit, address[] allowedRelayerAddresses, bytes message) message, tuple(address feeTokenAddress, uint256 amount) feeInfo)"
];

class TeleporterListener {
    constructor(networkName, config) {
        this.networkName = networkName;
        this.config = config;
        this.provider = new ethers.JsonRpcProvider(config.networks[networkName].rpc);
        this.teleporter = new ethers.Contract(
            config.contracts.teleporter,
            TELEPORTER_ABI,
            this.provider
        );
        this.blockchainId = config.networks[networkName].blockchainId;
    }

    async start() {
        console.log(`\n🎧 Starting Teleporter listener on ${this.networkName}`);
        console.log(`   Blockchain ID: ${this.blockchainId}`);
        console.log(`   RPC: ${this.config.networks[this.networkName].rpc}`);
        console.log(`   Teleporter: ${this.config.contracts.teleporter}`);
        
        // Listen for incoming messages
        this.teleporter.on("ReceiveCrossChainMessage", async (messageID, sourceBlockchainID, deliverer, relayerRewardAddress, teleporterMessage) => {
            console.log(`\n📨 [${this.networkName}] Received message!`);
            console.log(`   Message ID: ${messageID}`);
            console.log(`   From Chain: ${sourceBlockchainID}`);
            console.log(`   Deliverer: ${deliverer}`);
            
            try {
                // Decode the message
                const decodedMessage = ethers.toUtf8String(teleporterMessage.message);
                console.log(`   Message: "${decodedMessage}"`);
                console.log(`   From Address: ${teleporterMessage.originSenderAddress}`);
                
                // Here you would typically process the message
                await this.processMessage({
                    messageId: messageID,
                    sourceChain: sourceBlockchainID,
                    sender: teleporterMessage.originSenderAddress,
                    content: decodedMessage
                });
            } catch (error) {
                console.error(`   Error decoding message: ${error.message}`);
            }
        });

        // Listen for outgoing messages (optional - for monitoring)
        this.teleporter.on("SendCrossChainMessage", (messageID, destinationBlockchainID, message, feeInfo) => {
            console.log(`\n📤 [${this.networkName}] Sent message!`);
            console.log(`   Message ID: ${messageID}`);
            console.log(`   To Chain: ${destinationBlockchainID}`);
            try {
                const decodedMessage = ethers.toUtf8String(message.message);
                console.log(`   Message: "${decodedMessage}"`);
            } catch (error) {
                // Message might not be UTF-8
            }
        });

        console.log(`✅ Listener started on ${this.networkName}\n`);
    }

    async processMessage(message) {
        // Implement your message processing logic here
        console.log(`   🔧 Processing message...`);
        
        // Example: Save to database, trigger actions, send responses, etc.
        // await saveToDatabase(message);
        // await triggerWebhook(message);
        // await sendResponse(message);
        
        // For demo, just save to a log file
        const logEntry = {
            timestamp: new Date().toISOString(),
            network: this.networkName,
            message
        };
        
        try {
            const logs = await this.loadLogs();
            logs.push(logEntry);
            await fs.writeFile('message-logs.json', JSON.stringify(logs, null, 2));
            console.log(`   ✅ Message logged`);
        } catch (error) {
            console.error(`   ❌ Error logging message: ${error.message}`);
        }
    }

    async loadLogs() {
        try {
            const data = await fs.readFile('message-logs.json', 'utf8');
            return JSON.parse(data);
        } catch (error) {
            return [];
        }
    }

    stop() {
        console.log(`\n🛑 Stopping listener on ${this.networkName}`);
        this.teleporter.removeAllListeners();
    }
}

// Main function to run listeners
async function main() {
    console.log('🚀 Teleporter Message Listener Service');
    console.log('=====================================');

    // Load configuration
    const config = JSON.parse(await fs.readFile('network-config.json', 'utf8'));

    // Create listeners for each network
    const listeners = [];
    
    // Listen on subnet1
    if (config.networks.subnet1) {
        const subnet1Listener = new TeleporterListener('subnet1', config);
        await subnet1Listener.start();
        listeners.push(subnet1Listener);
    }

    // Listen on subnet2
    if (config.networks.subnet2) {
        const subnet2Listener = new TeleporterListener('subnet2', config);
        await subnet2Listener.start();
        listeners.push(subnet2Listener);
    }

    // Listen on C-Chain (optional)
    if (config.networks.cchain) {
        const cchainListener = new TeleporterListener('cchain', config);
        await cchainListener.start();
        listeners.push(cchainListener);
    }

    console.log(`🎧 Listening for messages... Press Ctrl+C to stop\n`);

    // Handle graceful shutdown
    process.on('SIGINT', () => {
        console.log('\n\n👋 Shutting down...');
        listeners.forEach(listener => listener.stop());
        process.exit(0);
    });
}

// Run the listener service
main().catch(console.error);