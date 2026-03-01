'use strict';
/**
 * Mixed CBDC workload: 70% transfer, 20% mint, 10% balanceOf
 * Simulates realistic CBDC payment system load
 */

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const fs = require('fs'), path = require('path');

class MixedWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.addresses = [];
        this.patterns  = [];
        this.idx = 0;
        this.txCounts = { transfer: 0, mint: 0, balanceOf: 0 };
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.contractAddr = roundArguments.contractAddress;

        const addrFile    = path.join(__dirname, '../../results/workload_addresses.json');
        const patternFile = path.join(__dirname, '../../results/tx_patterns.json');

        this.addresses = fs.existsSync(addrFile)
            ? JSON.parse(fs.readFileSync(addrFile, 'utf8'))
            : ['0x0000000000000000000000000000000000000001'];

        this.patterns = fs.existsSync(patternFile)
            ? JSON.parse(fs.readFileSync(patternFile, 'utf8'))
            : [];

        this.idx = workerIndex * 200;
    }

    _pickAddr() {
        return this.addresses[this.idx % this.addresses.length];
    }

    async submitTransaction() {
        const roll = Math.random();
        let req;

        if (roll < 0.70) {
            // Transfer (70%)
            const to = this.patterns.length > 0
                ? this.patterns[this.idx % this.patterns.length].to
                : this._pickAddr();
            const amount = this.patterns.length > 0
                ? String(this.patterns[this.idx % this.patterns.length].amount) + '000000000000000'
                : '500000000000000000';
            req = { contract: 'CBDC', verb: 'transfer', args: [to, amount], readOnly: false };
            this.txCounts.transfer++;

        } else if (roll < 0.90) {
            // Mint (20%)
            req = {
                contract: 'CBDC', verb: 'mint',
                args: [this._pickAddr(), '1000000000000000000'],
                readOnly: false
            };
            this.txCounts.mint++;

        } else {
            // BalanceOf (10%)
            req = { contract: 'CBDC', verb: 'balanceOf', args: [this._pickAddr()], readOnly: true };
            this.txCounts.balanceOf++;
        }

        this.idx++;
        return this.sutAdapter.sendRequests(req);
    }

    async cleanupWorkloadModule() {
        console.log(`[mixed] TX breakdown: transfer=${this.txCounts.transfer}, mint=${this.txCounts.mint}, balanceOf=${this.txCounts.balanceOf}`);
    }
}

module.exports.createWorkloadModule = () => new MixedWorkload();
