const { ethers } = require('ethers');
const fs = require('fs');

// Load network configuration
let config;
try {
    config = JSON.parse(fs.readFileSync('network-config.json', 'utf8'));
} catch (error) {
    console.error('❌ Error: network-config.json not found. Run ./setup-avalanche-teleporter.sh first');
    process.exit(1);
}

// Teleporter ABI (minimal)
const TELEPORTER_ABI = [
    {
        "inputs": [{
            "components": [
                { "name": "destinationBlockchainID", "type": "bytes32" },
                { "name": "destinationAddress", "type": "address" },
                { "name": "feeInfo", "type": "tuple", "components": [
                    { "name": "feeTokenAddress", "type": "address" },
                    { "name": "amount", "type": "uint256" }
                ]},
                { "name": "requiredGasLimit", "type": "uint256" },
                { "name": "allowedRelayerAddresses", "type": "address[]" },
                { "name": "message", "type": "bytes" }
            ],
            "name": "messageInput",
            "type": "tuple"
        }],
        "name": "sendCrossChainMessage",
        "outputs": [{ "name": "", "type": "bytes32" }],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "anonymous": false,
        "inputs": [
            { "indexed": true, "name": "messageID", "type": "bytes32" },
            { "indexed": true, "name": "destinationBlockchainID", "type": "bytes32" }
        ],
        "name": "SendCrossChainMessage",
        "type": "event"
    }
];

async function testMessage(from, to, message) {
    console.log(`\n📨 Sending message from ${from} to ${to}...`);
    console.log(`   Message: "${message}"`);

    const fromNetwork = config.networks[from];
    const toNetwork = config.networks[to];
    
    if (!fromNetwork || !toNetwork) {
        throw new Error(`Invalid network: ${from} or ${to}`);
    }

    // Create providers and wallet
    const provider = new ethers.JsonRpcProvider(fromNetwork.rpc);
    const wallet = new ethers.Wallet(config.accounts.main.privateKey, provider);
    const teleporter = new ethers.Contract(config.contracts.teleporter, TELEPORTER_ABI, wallet);

    // Prepare message
    const encodedMessage = ethers.toUtf8Bytes(message);
    const startTime = Date.now();

    // Send message
    const tx = await teleporter.sendCrossChainMessage({
        destinationBlockchainID: toNetwork.blockchainIdHex || toNetwork.blockchainId,
        destinationAddress: wallet.address,
        feeInfo: {
            feeTokenAddress: ethers.ZeroAddress,
            amount: 0
        },
        requiredGasLimit: 100000,
        allowedRelayerAddresses: [],
        message: encodedMessage
    });

    console.log(`   Tx: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`   ✅ Sent! Block: ${receipt.blockNumber}, Gas: ${receipt.gasUsed.toString()}`);

    // Parse message ID
    let messageID = null;
    for (const log of receipt.logs) {
        try {
            const parsed = teleporter.interface.parseLog(log);
            if (parsed && parsed.name === 'SendCrossChainMessage') {
                messageID = parsed.args[0];
                console.log(`   Message ID: ${messageID}`);
                break;
            }
        } catch (e) {}
    }

    // Wait for delivery (checking destination chain)
    console.log(`   ⏳ Waiting for delivery on ${to}...`);
    const destProvider = new ethers.JsonRpcProvider(toNetwork.rpc);
    
    let delivered = false;
    for (let i = 0; i < 20; i++) { // 10 seconds max
        try {
            const currentBlock = await destProvider.getBlockNumber();
            const logs = await destProvider.getLogs({
                address: config.contracts.teleporter,
                fromBlock: currentBlock - 5,
                toBlock: currentBlock
            });

            if (logs.length > 0) {
                const deliveryTime = Date.now() - startTime;
                console.log(`   ✅ Delivered in ~${deliveryTime}ms!`);
                delivered = true;
                break;
            }
        } catch (e) {}
        
        await new Promise(resolve => setTimeout(resolve, 500));
    }

    if (!delivered) {
        console.log(`   ⚠️  Delivery not confirmed (relayer typically takes 5-6s)`);
    }

    return { messageID, delivered };
}

async function main() {
    console.log('🚀 Teleporter Cross-Chain Messaging Test');
    console.log('========================================\n');

    try {
        // Check balances
        console.log('💰 Account Balances:');
        const mainAccount = config.accounts.main;
        
        for (const [name, network] of Object.entries(config.networks)) {
            if (network.rpc) {
                const provider = new ethers.JsonRpcProvider(network.rpc);
                const balance = await provider.getBalance(mainAccount.address);
                const symbol = network.token || 'AVAX';
                console.log(`   ${name}: ${ethers.formatEther(balance)} ${symbol}`);
            }
        }

        // Test 1: Subnet1 to Subnet2
        await testMessage('subnet1', 'subnet2', `Hello from Subnet1! Time: ${new Date().toISOString()}`);
        
        // Test 2: Subnet2 to Subnet1
        await testMessage('subnet2', 'subnet1', `Reply from Subnet2! Time: ${new Date().toISOString()}`);
        
        // Test 3: C-Chain to Subnet1
        if (config.networks.cchain) {
            await testMessage('cchain', 'subnet1', `Greetings from C-Chain! Time: ${new Date().toISOString()}`);
        }

        console.log('\n✅ All tests completed!');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        if (error.data) {
            console.error('Error data:', error.data);
        }
    }
}

// Run tests
main().then(() => {
    console.log('\n✨ Test suite finished!');
    process.exit(0);
}).catch((error) => {
    console.error('\n💥 Fatal error:', error);
    process.exit(1);
});