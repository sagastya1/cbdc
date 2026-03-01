#!/usr/bin/env python3
"""
Generate Ethereum-compatible private/public key pairs for Besu nodes.
Usage:
    gen_eth_key.py <key_dir>           - generate and save key
    gen_eth_key.py <key_dir> pubkey    - print pubkey
    gen_eth_key.py <key_dir> address   - print address
"""
import sys, os, secrets, hashlib, json

def keccak256(data: bytes) -> bytes:
    """Keccak-256 using pysha3 or fallback."""
    try:
        import sha3
        k = hashlib.new('sha3_256')
        # Use pysha3 for proper keccak (not sha3)
        import sha3 as _sha3
        k = _sha3.keccak_256()
        k.update(data)
        return k.digest()
    except ImportError:
        pass
    try:
        from Crypto.Hash import keccak as _k
        k = _k.new(digest_bits=256)
        k.update(data)
        return k.digest()
    except ImportError:
        pass
    # web3 fallback
    try:
        from eth_hash.auto import keccak
        return keccak(data)
    except ImportError:
        pass
    # pure python keccak
    return _keccak256_pure(data)

def _keccak256_pure(data: bytes) -> bytes:
    """Pure-python Keccak-256 (for environments without pysha3)."""
    # RC constants
    RC = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    def rot(x, n): return ((x << n) | (x >> (64 - n))) & 0xFFFFFFFFFFFFFFFF

    def keccak_f(A):
        for rc in RC:
            C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
            D = [C[(x-1)%5] ^ rot(C[(x+1)%5], 1) for x in range(5)]
            A = [[A[x][y] ^ D[x] for y in range(5)] for x in range(5)]
            B = [[0]*5 for _ in range(5)]
            offsets = [[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]]
            for x in range(5):
                for y in range(5):
                    B[y][(2*x+3*y)%5] = rot(A[x][y], offsets[x][y])
            A = [[B[x][y] ^ ((~B[(x+1)%5][y]) & B[(x+2)%5][y]) for y in range(5)] for x in range(5)]
            A[0][0] ^= rc
        return A

    rate = 136  # 1088 bits rate for keccak-256
    data = bytearray(data)
    data += b'\x01'
    while len(data) % rate != 0:
        data += b'\x00'
    data[-1] |= 0x80

    state = [[0]*5 for _ in range(5)]
    for block_start in range(0, len(data), rate):
        block = data[block_start:block_start+rate]
        for i in range(rate // 8):
            x, y = i % 5, i // 5
            state[x][y] ^= int.from_bytes(block[i*8:(i+1)*8], 'little')
        state = keccak_f(state)

    out = b''
    for y in range(5):
        for x in range(5):
            out += state[x][y].to_bytes(8, 'little')
            if len(out) >= 32:
                return out[:32]
    return out[:32]


def privkey_to_pubkey_uncompressed(privkey_bytes: bytes) -> bytes:
    """Derive uncompressed public key from private key using secp256k1."""
    try:
        from coincurve import PrivateKey
        pk = PrivateKey(privkey_bytes)
        return pk.public_key.format(compressed=False)[1:]  # strip 0x04 prefix
    except ImportError:
        pass
    try:
        from cryptography.hazmat.primitives.asymmetric.ec import (
            SECP256K1, derive_private_key, EllipticCurvePublicKey
        )
        from cryptography.hazmat.backends import default_backend
        privnum = int.from_bytes(privkey_bytes, 'big')
        key = derive_private_key(privnum, SECP256K1(), default_backend())
        pub = key.public_key().public_bytes(
            encoding=__import__('cryptography.hazmat.primitives.serialization', fromlist=['Encoding']).Encoding.X962,
            format=__import__('cryptography.hazmat.primitives.serialization', fromlist=['PublicFormat']).PublicFormat.UncompressedPoint
        )
        return pub[1:]  # strip 0x04
    except Exception:
        pass
    # eth_keys fallback
    from eth_keys import keys
    pk = keys.PrivateKey(privkey_bytes)
    return pk.public_key.to_bytes()


def pubkey_to_address(pubkey_bytes: bytes) -> str:
    h = keccak256(pubkey_bytes)
    return '0x' + h[-20:].hex()


def load_or_create(key_dir: str) -> dict:
    key_file = os.path.join(key_dir, 'key')
    meta_file = os.path.join(key_dir, 'key_meta.json')
    os.makedirs(key_dir, exist_ok=True)

    if os.path.exists(meta_file):
        with open(meta_file) as f:
            return json.load(f)

    # Generate new key
    privkey = secrets.token_bytes(32)
    # Ensure valid secp256k1 range
    order = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    while int.from_bytes(privkey, 'big') >= order or int.from_bytes(privkey, 'big') == 0:
        privkey = secrets.token_bytes(32)

    pubkey = privkey_to_pubkey_uncompressed(privkey)
    address = pubkey_to_address(pubkey)

    # Write private key in hex (Besu format - no 0x prefix)
    with open(key_file, 'w') as f:
        f.write(privkey.hex())

    meta = {
        'privkey': privkey.hex(),
        'pubkey': pubkey.hex(),
        'address': address
    }
    with open(meta_file, 'w') as f:
        json.dump(meta, f, indent=2)

    return meta


if __name__ == '__main__':
    key_dir = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else 'generate'
    meta = load_or_create(key_dir)
    if mode == 'pubkey':
        print(meta['pubkey'])
    elif mode == 'address':
        print(meta['address'])
    else:
        print(f"Generated key for {key_dir}: address={meta['address']}")
