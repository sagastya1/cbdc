#!/usr/bin/env python3
"""
Preprocess the realtime transaction dataset for Caliper workload.
Extracts unique from/to addresses for mint/transfer operations.
"""
import sys, json, csv, os

def preprocess(input_file: str, output_file: str):
    addresses = []
    tx_patterns = []
    
    print(f"[preprocess] Reading {input_file}...")
    
    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i >= 5000:  # Use first 5000 rows for workload
                break
            
            from_addr = row.get('from_address', '').strip()
            to_addr   = row.get('to_address', '').strip()
            value     = row.get('value', '0').strip()
            
            if from_addr and from_addr.startswith('0x') and len(from_addr) == 42:
                addresses.append(from_addr)
            if to_addr and to_addr.startswith('0x') and len(to_addr) == 42:
                addresses.append(to_addr)
            
            # Extract transfer pattern
            if from_addr and to_addr and value and value != '0':
                try:
                    val_wei = int(float(value))
                    # Normalize to reasonable CBDC amount
                    cbdc_amount = min(val_wei % 10000 + 1, 9999)
                    tx_patterns.append({
                        'from': from_addr,
                        'to':   to_addr,
                        'amount': cbdc_amount
                    })
                except (ValueError, OverflowError):
                    pass
    
    unique_addrs = list(dict.fromkeys(addresses))  # deduplicate, preserve order
    print(f"[preprocess] Found {len(unique_addrs)} unique addresses")
    print(f"[preprocess] Extracted {len(tx_patterns)} transaction patterns")
    
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(unique_addrs, f)
    
    # Also save tx patterns for realistic workload
    pattern_file = output_file.replace('workload_addresses.json', 'tx_patterns.json')
    with open(pattern_file, 'w') as f:
        json.dump(tx_patterns[:2000], f)
    
    print(f"[preprocess] Saved {output_file}")
    print(f"[preprocess] Saved {pattern_file}")
    return unique_addrs

if __name__ == '__main__':
    input_file  = sys.argv[1] if len(sys.argv) > 1 else '/data/realtime_txn_dataset.csv'
    output_file = sys.argv[2] if len(sys.argv) > 2 else '/results/workload_addresses.json'
    preprocess(input_file, output_file)
