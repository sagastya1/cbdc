#!/usr/bin/env python3
"""Generate Caliper network configuration for a given consensus type."""
import sys, json, os

def gen_config(consensus: str, rpc_port: int, contract_addr: str, output_file: str):
    ws_port = rpc_port + 1  # 8546 for poa, 8646 for qbft
    
    # Load ABI
    abi_file = os.path.join(os.path.dirname(output_file), '../../caliper/workload/CBDC.json')
    abi = []
    if os.path.exists(abi_file):
        with open(abi_file) as f:
            data = json.load(f)
            abi = data.get('abi', [])
    
    config = {
        "name": f"Hyperledger Besu {consensus.upper()} - CBDC Benchmark",
        "version": "1.0.0",
        "ethereum": {
            "url": f"ws://localhost:{ws_port}",
            "contractDeployerAddressPrivateKey": "8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63",
            "fromAddressPrivateKey": "8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63",
            "transactionConfirmationBlocks": 2,
            "contracts": {
                "CBDC": {
                    "address": contract_addr,
                    "abi": abi,
                    "gas": {
                        "mint":      100000,
                        "transfer":  80000,
                        "balanceOf": 30000
                    },
                    "gasPrice": 0
                }
            }
        }
    }
    
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"[caliper-config] Saved {output_file}")

if __name__ == '__main__':
    consensus     = sys.argv[1]
    rpc_port      = int(sys.argv[2])
    contract_addr = sys.argv[3]
    output_file   = sys.argv[4]
    gen_config(consensus, rpc_port, contract_addr, output_file)
