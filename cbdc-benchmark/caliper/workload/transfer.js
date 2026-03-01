'use strict';
/**
 * Caliper workload: transfer CBDC tokens
 * Replays transaction patterns from the real Ethereum dataset
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const fs = require('fs');
const path = require('path');

class TransferWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.patterns = [];
        this.addresses = [];
        this.idx = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractAddr = roundArguments.contractAddress;

        // Load real transaction patterns
        const patternFile = path.join(__dirname, '../../results/tx_patterns.json');
        if (fs.existsSync(patternFile)) {
            this.patterns = JSON.parse(fs.readFileSync(patternFile, 'utf8'));
        }

        // Load addresses
        const addrFile = path.join(__dirname, '../../results/workload_addresses.json');
        if (fs.existsSync(addrFile)) {
            this.addresses = JSON.parse(fs.readFileSync(addrFile, 'utf8'));
        }

        // Offset by worker to avoid contention
        this.idx = workerIndex * 100;
    }

    async submitTransaction() {
        let to, amount;

        if (this.patterns.length > 0) {
            const pattern = this.patterns[this.idx % this.patterns.length];
            to     = pattern.to;
            amount = String(pattern.amount) + '000000000000000'; // scale to wei
        } else {
            to     = this.addresses[this.idx % this.addresses.length] || '0x0000000000000000000000000000000000000001';
            amount = String(Math.floor(Math.random() * 1000) + 1) + '000000000000000';
        }

        this.idx++;

        return this.sutAdapter.sendRequests({
            contract: 'CBDC',
            verb: 'transfer',
            args: [to, amount],
            readOnly: false
        });
    }

    async cleanupWorkloadModule() {}
}

module.exports.createWorkloadModule = () => new TransferWorkload();
