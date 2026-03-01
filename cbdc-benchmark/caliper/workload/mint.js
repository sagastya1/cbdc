'use strict';
/**
 * Caliper workload: mint CBDC tokens
 * Uses addresses from the preprocessed real-world dataset
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const fs = require('fs');
const path = require('path');

class MintWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.addresses = [];
        this.contractAddr = '';
        this.cbdcAbi = null;
        this.idx = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);

        this.contractAddr = roundArguments.contractAddress;
        this.amount = roundArguments.amount || '1000000000000000000';

        // Load addresses from dataset
        const addrFile = path.join(__dirname, '../../results/workload_addresses.json');
        if (fs.existsSync(addrFile)) {
            this.addresses = JSON.parse(fs.readFileSync(addrFile, 'utf8'));
        } else {
            // Fallback: generate random addresses
            for (let i = 0; i < 100; i++) {
                const bytes = Buffer.allocUnsafe(20);
                for (let j = 0; j < 20; j++) bytes[j] = Math.floor(Math.random() * 256);
                this.addresses.push('0x' + bytes.toString('hex'));
            }
        }

        // Load ABI
        const abiFile = path.join(__dirname, 'CBDC.json');
        if (fs.existsSync(abiFile)) {
            this.cbdcAbi = JSON.parse(fs.readFileSync(abiFile, 'utf8')).abi;
        }
    }

    async submitTransaction() {
        const recipient = this.addresses[this.idx % this.addresses.length];
        this.idx++;

        const request = {
            contract: 'CBDC',
            verb: 'mint',
            args: [recipient, this.amount],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }

    async cleanupWorkloadModule() {}
}

module.exports.createWorkloadModule = () => new MintWorkload();
