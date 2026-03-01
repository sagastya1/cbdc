'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const fs = require('fs'), path = require('path');

class BalanceOfWorkload extends WorkloadModuleBase {
    constructor() { super(); this.addresses = []; this.idx = 0; }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        const addrFile = path.join(__dirname, '../../results/workload_addresses.json');
        this.addresses = fs.existsSync(addrFile)
            ? JSON.parse(fs.readFileSync(addrFile, 'utf8'))
            : ['0x0000000000000000000000000000000000000001'];
        this.idx = workerIndex * 50;
    }

    async submitTransaction() {
        const addr = this.addresses[this.idx++ % this.addresses.length];
        return this.sutAdapter.sendRequests({
            contract: 'CBDC', verb: 'balanceOf', args: [addr], readOnly: true
        });
    }
    async cleanupWorkloadModule() {}
}

module.exports.createWorkloadModule = () => new BalanceOfWorkload();
