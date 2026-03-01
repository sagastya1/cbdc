#!/usr/bin/env python3
"""Generate QBFT extraData field for genesis block."""
import sys

def rlp_encode_list(items):
    """Simple RLP list encoder."""
    encoded_items = b''.join(rlp_encode(i) for i in items)
    return rlp_encode_length(len(encoded_items), 0xc0) + encoded_items

def rlp_encode(data):
    if isinstance(data, bytes):
        if len(data) == 1 and data[0] < 0x80:
            return data
        return rlp_encode_length(len(data), 0x80) + data
    elif isinstance(data, list):
        return rlp_encode_list(data)
    return b''

def rlp_encode_length(length, offset):
    if length < 56:
        return bytes([length + offset])
    hex_len = length.to_bytes((length.bit_length() + 7) // 8, 'big')
    return bytes([len(hex_len) + offset + 55]) + hex_len

def addr_bytes(addr_str):
    return bytes.fromhex(addr_str.lstrip('0x').zfill(40))

def generate_qbft_extradata(validators):
    """
    QBFT extraData format (RLP encoded):
    [vanity(32 bytes), [validator_addresses], [], [], empty_seal]
    """
    vanity = b'\x00' * 32
    validator_bytes = [addr_bytes(v) for v in validators]
    
    # RLP: [vanity, [validators], [], [], []]
    inner = rlp_encode_list([
        vanity,
        rlp_encode_list(validator_bytes),
        rlp_encode_list([]),  # votes
        rlp_encode(b'\x00'),  # round
        rlp_encode_list([]),  # committed seals
    ])
    
    return '0x' + inner.hex()

if __name__ == '__main__':
    validators = sys.argv[1:]
    if not validators:
        print("Usage: gen_qbft_extra.py <addr1> <addr2> <addr3>", file=sys.stderr)
        sys.exit(1)
    print(generate_qbft_extradata(validators))
