#!/usr/bin/env node
/**
 * Deploy CBDC contract to Besu network
 * Usage: node deploy_contract.js <rpc_url> <sol_file>
 * Outputs: contract address (last line of stdout)
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const rpcUrl   = process.argv[2] || 'http://localhost:8545';
const solFile  = process.argv[3] || path.join(__dirname, '../contracts/CBDC.sol');

// Try to use web3 or ethers
async function deploy() {
    const solSource = fs.readFileSync(solFile, 'utf8');
    
    // Compile with solcjs
    let solc;
    try {
        solc = require('solc');
    } catch {
        console.error('[deploy] solc not found, installing...');
        execSync('npm install -g solc', { stdio: 'inherit' });
        solc = require('solc');
    }
    
    const input = {
        language: 'Solidity',
        sources: { 'CBDC.sol': { content: solSource } },
        settings: {
            outputSelection: { '*': { '*': ['abi', 'evm.bytecode'] } },
            optimizer: { enabled: true, runs: 200 }
        }
    };
    
    const output = JSON.parse(solc.compile(JSON.stringify(input)));
    
    if (output.errors) {
        const errs = output.errors.filter(e => e.severity === 'error');
        if (errs.length > 0) {
            errs.forEach(e => console.error('[solc]', e.formattedMessage));
            process.exit(1);
        }
    }
    
    const contract  = output.contracts['CBDC.sol']['CBDC'];
    const abi       = contract.abi;
    const bytecode  = '0x' + contract.evm.bytecode.object;
    
    // Use Web3 or ethers for deployment
    let Web3;
    try {
        Web3 = require('web3');
    } catch {
        execSync('npm install web3@1.10.0', { stdio: 'inherit' });
        Web3 = require('web3');
    }
    
    const web3 = new Web3(rpcUrl);
    
    // Get deployer account (coinbase / first unlocked)
    const accounts = await web3.eth.getAccounts();
    if (!accounts.length) throw new Error('No accounts available');
    const deployer = accounts[0];
    
    console.error(`[deploy] Using account: ${deployer}`);
    console.error(`[deploy] RPC: ${rpcUrl}`);
    
    const ContractFactory = new web3.eth.Contract(abi);
    
    const gasEstimate = await ContractFactory.deploy({ data: bytecode })
        .estimateGas({ from: deployer });
    
    const deployed = await ContractFactory.deploy({ data: bytecode })
        .send({
            from:     deployer,
            gas:      Math.ceil(gasEstimate * 1.2),
            gasPrice: '0'
        });
    
    const address = deployed.options.address;
    console.error(`[deploy] Contract deployed successfully`);
    
    // Fund benchmark accounts from dataset
    const resultsDir = path.join(__dirname, '../results');
    const addrFile   = path.join(resultsDir, 'workload_addresses.json');
    
    if (fs.existsSync(addrFile)) {
        const addrs = JSON.parse(fs.readFileSync(addrFile, 'utf8'));
        const unique = [...new Set(addrs.slice(0, 100))];
        console.error(`[deploy] Batch minting to ${unique.length} benchmark accounts...`);
        
        const mintAmount = web3.utils.toWei('1000000', 'ether');
        const cbdc = new web3.eth.Contract(abi, address);
        
        // Batch mint in chunks of 50
        for (let i = 0; i < unique.length; i += 50) {
            const chunk = unique.slice(i, i + 50);
            await cbdc.methods.batchMint(chunk, mintAmount).send({
                from: deployer, gas: 5000000, gasPrice: '0'
            });
            console.error(`[deploy] Minted batch ${Math.floor(i/50)+1}`);
        }
    }
    
    // Output contract address as last line (parsed by shell script)
    console.log(address);
    
    // Save ABI for Caliper
    const artifactDir = path.join(__dirname, '../caliper/workload');
    fs.mkdirSync(artifactDir, { recursive: true });
    fs.writeFileSync(
        path.join(artifactDir, 'CBDC.json'),
        JSON.stringify({ abi, address }, null, 2)
    );
    console.error(`[deploy] ABI saved to caliper/workload/CBDC.json`);
}

deploy().catch(err => {
    console.error('[deploy] FATAL:', err.message);
    process.exit(1);
});
