#!/usr/bin/env python3
"""Generate a synthetic transaction dataset matching the schema of the real dataset."""
import sys, csv, random, os
from datetime import datetime, timedelta

def generate(output_file: str, num_rows: int = 10000):
    os.makedirs(os.path.dirname(output_file) if os.path.dirname(output_file) else '.', exist_ok=True)
    
    addresses = [f"0x{''.join(random.choices('0123456789abcdef', k=40))}" 
                 for _ in range(200)]
    
    fieldnames = [
        'hash','nonce','transaction_index','from_address','to_address',
        'value','gas','gas_price','input','receipt_cumulative_gas_used',
        'receipt_gas_used','block_timestamp','block_number','block_hash',
        'from_scam','to_scam','from_category','to_category'
    ]
    
    base_time = datetime(2024, 1, 1, 0, 0, 0)
    block_num = 1000000
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        
        for i in range(num_rows):
            ts = base_time + timedelta(seconds=i*2)
            writer.writerow({
                'hash':                        f"0x{''.join(random.choices('0123456789abcdef', k=64))}",
                'nonce':                        random.randint(0, 100000),
                'transaction_index':            random.randint(0, 200),
                'from_address':                 random.choice(addresses),
                'to_address':                   random.choice(addresses),
                'value':                        random.randint(0, 10**18),
                'gas':                          21000,
                'gas_price':                    random.randint(10**9, 10**10),
                'input':                        '0x',
                'receipt_cumulative_gas_used':  random.randint(21000, 500000),
                'receipt_gas_used':             21000,
                'block_timestamp':              ts.strftime('%Y-%m-%d %H:%M:%S UTC'),
                'block_number':                 block_num + i // 10,
                'block_hash':                   f"0x{''.join(random.choices('0123456789abcdef', k=64))}",
                'from_scam':                    0,
                'to_scam':                      0,
                'from_category':                'null',
                'to_category':                  'null',
            })
    
    print(f"[generate] Synthetic dataset: {num_rows} rows → {output_file}")

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '/data/realtime_txn_dataset.csv'
    generate(out)
