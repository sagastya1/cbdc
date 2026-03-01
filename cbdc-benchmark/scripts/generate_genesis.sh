#!/usr/bin/env bash
# Generate Besu genesis file and node keys for PoA (Clique) or QBFT
set -euo pipefail

CONSENSUS="${1:-poa}"  # poa | qbft
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET_DIR="${REPO_ROOT}/networks/${CONSENSUS}"

log() { echo "[genesis] $*"; }

# ─── Generate node keys using Besu ───────────────────────────────────────────
generate_keys() {
    local node="$1"
    local key_dir="${NET_DIR}/keys/${node}"
    mkdir -p "$key_dir"
    
    if [[ ! -f "${key_dir}/key" ]]; then
        log "Generating key for ${node}..."
        docker run --rm \
            -v "${key_dir}:/opt/besu/data" \
            hyperledger/besu:24.1.2 \
            --data-path=/opt/besu/data \
            public-key export \
            --to=/opt/besu/data/key.pub \
            2>/dev/null || true
        
        # Fallback: generate via openssl + eth key derivation
        python3 "${REPO_ROOT}/scripts/gen_eth_key.py" "$key_dir"
    fi
}

# ─── Read public key from key file ───────────────────────────────────────────
get_pubkey() {
    local key_dir="${NET_DIR}/keys/$1"
    python3 "${REPO_ROOT}/scripts/gen_eth_key.py" "${key_dir}" pubkey
}

get_address() {
    local key_dir="${NET_DIR}/keys/$1"
    python3 "${REPO_ROOT}/scripts/gen_eth_key.py" "${key_dir}" address
}

# ─── Generate all node keys ──────────────────────────────────────────────────
for node in bootnode validator1 validator2 validator3; do
    generate_keys "$node"
done

BOOTNODE_PUBKEY=$(get_pubkey bootnode)
VALIDATOR1_ADDR=$(get_address validator1)
VALIDATOR2_ADDR=$(get_address validator2)  
VALIDATOR3_ADDR=$(get_address validator3)
BOOTNODE_ADDR=$(get_address bootnode)

log "Bootnode pubkey: ${BOOTNODE_PUBKEY:0:20}..."
log "Validator addresses: ${VALIDATOR1_ADDR}, ${VALIDATOR2_ADDR}, ${VALIDATOR3_ADDR}"

# Export bootnode pubkey for docker-compose
export BOOTNODE_PUBKEY
echo "BOOTNODE_PUBKEY=${BOOTNODE_PUBKEY}" > "${NET_DIR}/.env"

# ─── Generate genesis ────────────────────────────────────────────────────────
if [[ "$CONSENSUS" == "poa" ]]; then
    # Clique PoA
    # Extradata: 32 bytes vanity + validator addresses (no 0x, packed) + 65 bytes seal
    VANITY="0000000000000000000000000000000000000000000000000000000000000000"
    
    # Remove 0x prefix, concatenate validator addresses
    V1="${VALIDATOR1_ADDR#0x}"
    V2="${VALIDATOR2_ADDR#0x}"
    V3="${VALIDATOR3_ADDR#0x}"
    
    EXTRA_DATA="0x${VANITY}${V1}${V2}${V3}$(python3 -c "print('00' * 65)")"
    
    cat > "${NET_DIR}/genesis.json" <<GENESIS
{
  "config": {
    "chainId": 1337,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "clique": {
      "blockperiodseconds": 2,
      "epochlength": 30000
    }
  },
  "nonce": "0x0",
  "timestamp": "0x0",
  "gasLimit": "0x1fffffffffffff",
  "difficulty": "0x1",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "extraData": "${EXTRA_DATA}",
  "alloc": {
    "${BOOTNODE_ADDR}":   {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"},
    "${VALIDATOR1_ADDR}": {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"},
    "${VALIDATOR2_ADDR}": {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"},
    "${VALIDATOR3_ADDR}": {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"}
  }
}
GENESIS

else
    # QBFT
    # Build QBFT extra data using Besu operator command
    VALIDATORS_JSON="[\"${VALIDATOR1_ADDR}\",\"${VALIDATOR2_ADDR}\",\"${VALIDATOR3_ADDR}\"]"
    
    QBFT_EXTRA=$(docker run --rm hyperledger/besu:24.1.2 \
        operator generate-blockchain-config \
        --config-file=/dev/stdin <<< '{
            "genesis": {"config": {"chainId": 1338, "qbft": {"blockperiodseconds": 2}}},
            "blockchain": {"nodes": {"count": 4}}
        }' 2>/dev/null | grep '"extraData"' | head -1 | awk -F'"' '{print $4}' || echo "0x")
    
    # Fallback extradata if Besu operator fails
    if [[ "$QBFT_EXTRA" == "0x" || -z "$QBFT_EXTRA" ]]; then
        python3 "${REPO_ROOT}/scripts/gen_qbft_extra.py" \
            "$VALIDATOR1_ADDR" "$VALIDATOR2_ADDR" "$VALIDATOR3_ADDR" \
            > "${NET_DIR}/qbft_extra.txt"
        QBFT_EXTRA=$(cat "${NET_DIR}/qbft_extra.txt")
    fi
    
    cat > "${NET_DIR}/genesis.json" <<GENESIS
{
  "config": {
    "chainId": 1338,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "qbft": {
      "blockperiodseconds": 2,
      "epochlength": 30000,
      "requesttimeoutseconds": 4
    }
  },
  "nonce": "0x0",
  "timestamp": "0x0",
  "gasLimit": "0x1fffffffffffff",
  "difficulty": "0x1",
  "mixHash": "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "extraData": "${QBFT_EXTRA}",
  "alloc": {
    "${BOOTNODE_ADDR}":   {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"},
    "${VALIDATOR1_ADDR}": {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"},
    "${VALIDATOR2_ADDR}": {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"},
    "${VALIDATOR3_ADDR}": {"balance": "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"}
  }
}
GENESIS
fi

# Create data dirs
for node in bootnode validator1 validator2 validator3; do
    mkdir -p "${NET_DIR}/data/${node}"
done

log "Genesis generated: ${NET_DIR}/genesis.json"
log "Consensus: ${CONSENSUS^^}"
