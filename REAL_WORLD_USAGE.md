# Real-World Teleporter Message Handling

## Overview
In production environments, client and server applications are typically separate services. This guide shows how to properly listen for and send Teleporter messages in real-world scenarios.

## Message Listening Patterns

### 1. Event Listener Service (`teleporter-listener.js`)
A dedicated service that listens for Teleporter events on multiple chains:

```bash
npm run listen
```

**Features:**
- Monitors all configured chains simultaneously
- Decodes and logs incoming messages
- Saves message history to `message-logs.json`
- Handles both text and binary messages

**Use Cases:**
- Backend services that react to cross-chain messages
- Message archival and auditing
- Triggering webhooks or database updates

### 2. Interactive Message Sender (`teleporter-sender.js`)
Send messages between chains via CLI or API:

```bash
# Interactive CLI mode
npm run send

# API server mode (requires express)
npm run send:server
```

**CLI Features:**
- Interactive prompts for source/destination chains
- Real-time balance checking
- Custom destination address support

**API Server Features:**
- REST endpoints for sending messages
- Balance checking endpoint
- Easy integration with web applications

**API Endpoints:**
```
POST /send-message
{
  "fromNetwork": "subnet1",
  "toNetwork": "subnet2",
  "message": "Hello from API",
  "destinationAddress": "0x..." // optional
}

GET /balances
```

### 3. WebSocket Real-Time Monitor (`teleporter-websocket-relay.js`)
Real-time message monitoring with WebSocket broadcasting:

```bash
npm run monitor
```

**Features:**
- WebSocket server on port 8080
- Real-time event broadcasting to connected clients
- Message history and statistics
- Auto-generated HTML monitoring dashboard

**Open `teleporter-monitor.html` in browser for:**
- Live message feed
- Network statistics
- Messages per minute tracking
- Visual indicators for sent/received messages

## Architecture Patterns

### Pattern 1: Microservices Architecture
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   API Gateway   │────▶│ Message Sender  │────▶│   Teleporter    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                          │
┌─────────────────┐     ┌─────────────────┐              ▼
│  Message Queue  │◀────│ Event Listener  │◀────────[Blockchain Events]
└─────────────────┘     └─────────────────┘
```

### Pattern 2: Event-Driven Architecture
```
┌─────────────────┐
│   Teleporter    │
└────────┬────────┘
         │ Events
         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Event Listener  │────▶│ Message Broker  │────▶│   Processors    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │   Database      │
                        └─────────────────┘
```

### Pattern 3: Real-Time Notifications
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Blockchain    │────▶│ WebSocket Relay │────▶│   Web Clients   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │  Mobile Clients  │
                        └─────────────────┘
```

## Integration Examples

### Example 1: Backend Service Integration
```javascript
// Import the listener
const TeleporterListener = require('./teleporter-listener');

// In your service
async function startMessageProcessor() {
    const listener = new TeleporterListener('subnet1', config);
    
    // Override processMessage for custom logic
    listener.processMessage = async (message) => {
        // Your custom processing
        if (message.content.startsWith('ORDER:')) {
            await processOrder(message);
        } else if (message.content.startsWith('TRANSFER:')) {
            await processTransfer(message);
        }
    };
    
    await listener.start();
}
```

### Example 2: Frontend Integration
```javascript
// Connect to WebSocket relay
const ws = new WebSocket('ws://localhost:8080');

ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    
    if (data.type === 'message_received') {
        // Update UI with new message
        showNotification(`New message from ${data.sourceChain}`);
        updateMessageList(data);
    }
};

// Send message via API
async function sendMessage(from, to, message) {
    const response = await fetch('http://localhost:3000/send-message', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
            fromNetwork: from, 
            toNetwork: to, 
            message 
        })
    });
    return response.json();
}
```

### Example 3: Message Queue Integration
```javascript
// Using with RabbitMQ or Redis
const listener = new TeleporterListener('subnet1', config);

listener.processMessage = async (message) => {
    // Push to message queue
    await messageQueue.publish('teleporter.messages', {
        ...message,
        receivedAt: new Date()
    });
};
```

## Best Practices

### 1. Message Format
Use structured messages for easier processing:
```javascript
const message = JSON.stringify({
    type: 'TRANSFER',
    from: userAddress,
    to: recipientAddress,
    amount: '1000',
    token: 'USDC',
    nonce: Date.now()
});
```

### 2. Error Handling
Always implement retry logic:
```javascript
async function sendWithRetry(sender, from, to, message, maxRetries = 3) {
    for (let i = 0; i < maxRetries; i++) {
        try {
            return await sender.sendMessage(from, to, message);
        } catch (error) {
            if (i === maxRetries - 1) throw error;
            await new Promise(r => setTimeout(r, 2000 * (i + 1)));
        }
    }
}
```

### 3. Message Verification
Verify message integrity:
```javascript
listener.processMessage = async (message) => {
    // Verify sender is authorized
    if (!authorizedSenders.includes(message.sender)) {
        console.warn('Unauthorized sender:', message.sender);
        return;
    }
    
    // Verify message format
    try {
        const parsed = JSON.parse(message.content);
        if (!parsed.type || !parsed.nonce) {
            throw new Error('Invalid message format');
        }
    } catch (error) {
        console.error('Invalid message:', error);
        return;
    }
    
    // Process valid message
    await processValidMessage(message);
};
```

### 4. Monitoring and Alerting
Set up monitoring for:
- Message delivery times
- Failed messages
- Network connectivity
- Gas costs

## Security Considerations

1. **Authentication**: Always verify message senders
2. **Rate Limiting**: Implement rate limits to prevent spam
3. **Message Validation**: Validate all message content
4. **Access Control**: Restrict who can send messages to your contracts
5. **Encryption**: Consider encrypting sensitive message content

## Deployment

### Docker Example
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["npm", "run", "listen"]
```

### PM2 Process Management
```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: 'teleporter-listener',
    script: './teleporter-listener.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G'
  }, {
    name: 'teleporter-api',
    script: './teleporter-sender.js',
    args: '--server',
    instances: 2,
    exec_mode: 'cluster'
  }]
};
```

## Testing

### Unit Testing Example
```javascript
// test/teleporter.test.js
const { TeleporterSender } = require('../teleporter-sender');

describe('TeleporterSender', () => {
    it('should send message successfully', async () => {
        const sender = new TeleporterSender(mockConfig);
        const result = await sender.sendMessage(
            'subnet1', 
            'subnet2', 
            'test message'
        );
        expect(result.txHash).toBeDefined();
    });
});
```

### Integration Testing
1. Start local network: `npm run setup`
2. Run listener in test mode
3. Send test messages
4. Verify message receipt
5. Clean up: `npm run shutdown`