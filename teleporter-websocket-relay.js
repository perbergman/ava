const ethers = require('ethers');
const WebSocket = require('ws');
const fs = require('fs').promises;

// Teleporter ABI for events
const TELEPORTER_ABI = [
    "event ReceiveCrossChainMessage(bytes32 indexed messageID, bytes32 indexed sourceBlockchainID, address indexed deliverer, address relayerRewardAddress, tuple(bytes32 sourceBlockchainID, address originSenderAddress, bytes message) teleporterMessage)",
    "event SendCrossChainMessage(bytes32 indexed messageID, bytes32 indexed destinationBlockchainID, tuple(bytes32 destinationBlockchainID, address destinationAddress, tuple(address feeTokenAddress, uint256 amount) feeInfo, uint256 requiredGasLimit, address[] allowedRelayerAddresses, bytes message) message, tuple(address feeTokenAddress, uint256 amount) feeInfo)"
];

class TeleporterWebSocketRelay {
    constructor(config, port = 8080) {
        this.config = config;
        this.port = port;
        this.providers = {};
        this.teleporters = {};
        this.clients = new Set();
        this.messageHistory = [];
        this.maxHistorySize = 100;
        
        // Initialize providers and contracts
        for (const [networkName, network] of Object.entries(config.networks)) {
            this.providers[networkName] = new ethers.JsonRpcProvider(network.rpc);
            this.teleporters[networkName] = new ethers.Contract(
                config.contracts.teleporter,
                TELEPORTER_ABI,
                this.providers[networkName]
            );
        }
    }

    async start() {
        // Start WebSocket server
        this.wss = new WebSocket.Server({ port: this.port });
        
        console.log(`🌐 WebSocket server started on ws://localhost:${this.port}`);
        console.log('📡 Monitoring Teleporter events on all networks...\n');

        // Handle WebSocket connections
        this.wss.on('connection', (ws) => {
            console.log('👤 New client connected');
            this.clients.add(ws);
            
            // Send connection confirmation
            ws.send(JSON.stringify({
                type: 'connected',
                timestamp: new Date().toISOString(),
                networks: Object.keys(this.config.networks)
            }));
            
            // Send message history to new client
            if (this.messageHistory.length > 0) {
                ws.send(JSON.stringify({
                    type: 'history',
                    messages: this.messageHistory
                }));
            }
            
            // Handle client messages
            ws.on('message', async (message) => {
                try {
                    const data = JSON.parse(message);
                    await this.handleClientMessage(ws, data);
                } catch (error) {
                    ws.send(JSON.stringify({
                        type: 'error',
                        error: error.message
                    }));
                }
            });
            
            // Handle disconnection
            ws.on('close', () => {
                console.log('👤 Client disconnected');
                this.clients.delete(ws);
            });
        });

        // Start monitoring all networks
        await this.startMonitoring();
    }

    async startMonitoring() {
        for (const [networkName, network] of Object.entries(this.config.networks)) {
            // Monitor incoming messages
            this.teleporters[networkName].on("ReceiveCrossChainMessage", 
                async (messageID, sourceBlockchainID, deliverer, relayerRewardAddress, teleporterMessage) => {
                    const event = {
                        type: 'message_received',
                        network: networkName,
                        messageId: messageID,
                        sourceChain: sourceBlockchainID,
                        deliverer,
                        timestamp: new Date().toISOString(),
                        data: {
                            sender: teleporterMessage.originSenderAddress,
                            message: null
                        }
                    };

                    try {
                        // Try to decode as UTF-8
                        event.data.message = ethers.toUtf8String(teleporterMessage.message);
                    } catch (error) {
                        // If not UTF-8, send as hex
                        event.data.message = teleporterMessage.message;
                        event.data.messageType = 'hex';
                    }

                    await this.broadcastEvent(event);
                }
            );

            // Monitor outgoing messages
            this.teleporters[networkName].on("SendCrossChainMessage",
                async (messageID, destinationBlockchainID, message, feeInfo) => {
                    const event = {
                        type: 'message_sent',
                        network: networkName,
                        messageId: messageID,
                        destinationChain: destinationBlockchainID,
                        timestamp: new Date().toISOString(),
                        data: {
                            destinationAddress: message.destinationAddress,
                            requiredGasLimit: message.requiredGasLimit.toString(),
                            message: null
                        }
                    };

                    try {
                        // Try to decode as UTF-8
                        event.data.message = ethers.toUtf8String(message.message);
                    } catch (error) {
                        // If not UTF-8, send as hex
                        event.data.message = message.message;
                        event.data.messageType = 'hex';
                    }

                    await this.broadcastEvent(event);
                }
            );

            console.log(`✅ Monitoring ${networkName}`);
        }
    }

    async broadcastEvent(event) {
        // Add to history
        this.messageHistory.push(event);
        if (this.messageHistory.length > this.maxHistorySize) {
            this.messageHistory.shift();
        }

        // Broadcast to all connected clients
        const message = JSON.stringify(event);
        for (const client of this.clients) {
            if (client.readyState === WebSocket.OPEN) {
                client.send(message);
            }
        }

        // Log to console
        if (event.type === 'message_received') {
            console.log(`📨 [${event.network}] Received: "${event.data.message}" from ${event.data.sender}`);
        } else if (event.type === 'message_sent') {
            console.log(`📤 [${event.network}] Sent: "${event.data.message}" to ${event.destinationChain}`);
        }
    }

    async handleClientMessage(ws, data) {
        switch (data.type) {
            case 'subscribe':
                // Client wants to subscribe to specific networks
                ws.send(JSON.stringify({
                    type: 'subscribed',
                    networks: data.networks || Object.keys(this.config.networks)
                }));
                break;
                
            case 'get_stats':
                // Send statistics
                const stats = {
                    type: 'stats',
                    totalMessages: this.messageHistory.length,
                    connectedClients: this.clients.size,
                    networks: {}
                };
                
                // Count messages per network
                for (const msg of this.messageHistory) {
                    if (!stats.networks[msg.network]) {
                        stats.networks[msg.network] = { sent: 0, received: 0 };
                    }
                    if (msg.type === 'message_sent') {
                        stats.networks[msg.network].sent++;
                    } else {
                        stats.networks[msg.network].received++;
                    }
                }
                
                ws.send(JSON.stringify(stats));
                break;
                
            default:
                ws.send(JSON.stringify({
                    type: 'error',
                    error: 'Unknown message type'
                }));
        }
    }

    stop() {
        console.log('\n🛑 Shutting down WebSocket relay...');
        
        // Remove all listeners
        for (const teleporter of Object.values(this.teleporters)) {
            teleporter.removeAllListeners();
        }
        
        // Close all WebSocket connections
        for (const client of this.clients) {
            client.close();
        }
        
        // Close the server
        this.wss.close();
    }
}

// Example HTML client
async function createExampleClient() {
    const html = `<!DOCTYPE html>
<html>
<head>
    <title>Teleporter Message Monitor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f0f0f0; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        h1 { color: #333; }
        .status { padding: 10px; margin: 10px 0; border-radius: 4px; }
        .connected { background: #d4edda; color: #155724; }
        .disconnected { background: #f8d7da; color: #721c24; }
        .messages { margin-top: 20px; }
        .message { padding: 10px; margin: 5px 0; border-radius: 4px; border-left: 4px solid #007bff; background: #f8f9fa; }
        .message-sent { border-left-color: #28a745; }
        .message-received { border-left-color: #17a2b8; }
        .network { font-weight: bold; color: #495057; }
        .timestamp { color: #6c757d; font-size: 0.9em; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat-box { flex: 1; padding: 15px; background: #e9ecef; border-radius: 4px; text-align: center; }
        .stat-value { font-size: 2em; font-weight: bold; color: #007bff; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Teleporter Message Monitor</h1>
        <div id="status" class="status disconnected">Disconnected</div>
        
        <div class="stats">
            <div class="stat-box">
                <div class="stat-value" id="totalMessages">0</div>
                <div>Total Messages</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="messagesPerMinute">0</div>
                <div>Messages/Minute</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="activeNetworks">0</div>
                <div>Active Networks</div>
            </div>
        </div>
        
        <div class="messages">
            <h2>Recent Messages</h2>
            <div id="messageList"></div>
        </div>
    </div>

    <script>
        const ws = new WebSocket('ws://localhost:8080');
        const messageList = document.getElementById('messageList');
        const statusDiv = document.getElementById('status');
        let messageCount = 0;
        let messageTimestamps = [];

        ws.onopen = () => {
            statusDiv.textContent = 'Connected';
            statusDiv.className = 'status connected';
            ws.send(JSON.stringify({ type: 'get_stats' }));
        };

        ws.onclose = () => {
            statusDiv.textContent = 'Disconnected';
            statusDiv.className = 'status disconnected';
        };

        ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            
            if (data.type === 'message_sent' || data.type === 'message_received') {
                messageCount++;
                messageTimestamps.push(Date.now());
                
                const messageDiv = document.createElement('div');
                messageDiv.className = 'message ' + data.type.replace('_', '-');
                
                const icon = data.type === 'message_sent' ? '📤' : '📨';
                const action = data.type === 'message_sent' ? 'sent to' : 'received from';
                const otherChain = data.type === 'message_sent' ? data.destinationChain : data.sourceChain;
                
                messageDiv.innerHTML = \`
                    <div>\${icon} <span class="network">\${data.network}</span> \${action} \${otherChain}</div>
                    <div>Message: "\${data.data.message}"</div>
                    <div class="timestamp">\${new Date(data.timestamp).toLocaleString()}</div>
                \`;
                
                messageList.insertBefore(messageDiv, messageList.firstChild);
                
                // Keep only last 50 messages
                while (messageList.children.length > 50) {
                    messageList.removeChild(messageList.lastChild);
                }
                
                updateStats();
            } else if (data.type === 'stats') {
                document.getElementById('totalMessages').textContent = data.totalMessages;
                document.getElementById('activeNetworks').textContent = Object.keys(data.networks).length;
            } else if (data.type === 'history') {
                // Display historical messages
                data.messages.forEach(msg => {
                    ws.onmessage({ data: JSON.stringify(msg) });
                });
            }
        };

        function updateStats() {
            document.getElementById('totalMessages').textContent = messageCount;
            
            // Calculate messages per minute
            const now = Date.now();
            const oneMinuteAgo = now - 60000;
            const recentMessages = messageTimestamps.filter(ts => ts > oneMinuteAgo).length;
            document.getElementById('messagesPerMinute').textContent = recentMessages;
        }

        // Update stats every 5 seconds
        setInterval(() => {
            if (ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ type: 'get_stats' }));
                updateStats();
            }
        }, 5000);
    </script>
</body>
</html>`;

    await fs.writeFile('teleporter-monitor.html', html);
    console.log('📄 Created teleporter-monitor.html - Open in browser to view real-time messages');
}

// Main function
async function main() {
    const config = JSON.parse(await fs.readFile('network-config.json', 'utf8'));
    const relay = new TeleporterWebSocketRelay(config);
    
    await relay.start();
    await createExampleClient();
    
    console.log('\n📡 WebSocket relay is running...');
    console.log('🌐 Open teleporter-monitor.html in your browser');
    console.log('Press Ctrl+C to stop\n');

    // Handle graceful shutdown
    process.on('SIGINT', () => {
        relay.stop();
        process.exit(0);
    });
}

// Check if ws module is installed
try {
    require('ws');
    main().catch(console.error);
} catch (error) {
    console.error('Please install the ws module: npm install ws');
    process.exit(1);
}