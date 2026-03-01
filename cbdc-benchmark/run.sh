#!/usr/bin/env bash
# =============================================================================
# CBDC Blockchain Benchmark: Hyperledger Besu PoA vs QBFT
# One-command execution: ./run.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${REPO_ROOT}/results"
DATA_FILE="${REPO_ROOT}/data/realtime_txn_dataset.csv"
LOG_FILE="${RESULTS_DIR}/benchmark.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN: $*${NC}" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"; exit 1; }

print_banner() {
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║     CBDC Blockchain Benchmark Suite v1.0                        ║
║     Hyperledger Besu: PoA (Clique) vs QBFT                     ║
║     Powered by Hyperledger Caliper                              ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    local missing=()
    for cmd in docker docker-compose node npm python3 jq curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && err "Missing: ${missing[*]}. Run: ./scripts/install_deps.sh"
    
    # Check Docker daemon
    docker info &>/dev/null || err "Docker daemon not running. Start with: sudo systemctl start docker"
    
    # Check memory (need at least 6GB free)
    local free_mem
    free_mem=$(free -g | awk '/^Mem:/{print $7}')
    [[ "$free_mem" -lt 4 ]] && warn "Low free memory (${free_mem}GB). Recommend 6GB+ free."
    
    log "Prerequisites OK"
}

prepare_data() {
    log "Preparing dataset..."
    mkdir -p "${REPO_ROOT}/data" "${RESULTS_DIR}"
    
    if [[ ! -f "$DATA_FILE" ]]; then
        warn "Dataset not found at $DATA_FILE"
        log "Generating synthetic dataset from schema..."
        python3 "${REPO_ROOT}/scripts/generate_dataset.py" "$DATA_FILE"
    else
        log "Dataset found: $(wc -l < "$DATA_FILE") rows"
    fi
    
    # Pre-process: extract addresses for workload
    python3 "${REPO_ROOT}/scripts/preprocess_data.py" "$DATA_FILE" "${RESULTS_DIR}/workload_addresses.json"
    log "Dataset preprocessed → ${RESULTS_DIR}/workload_addresses.json"
}

start_network() {
    local consensus="$1"  # poa or qbft
    log "Starting Besu ${consensus^^} network..."
    
    cd "${REPO_ROOT}/networks/${consensus}"
    
    # Clean any previous state
    docker-compose down -v --remove-orphans 2>/dev/null || true
    rm -rf data/ 2>/dev/null || true
    
    # Generate genesis & keys
    log "Generating genesis for ${consensus^^}..."
    bash "${REPO_ROOT}/scripts/generate_genesis.sh" "$consensus"
    
    docker-compose up -d
    
    # Wait for network readiness
    log "Waiting for ${consensus^^} network to be ready..."
    local retries=60
    local rpc_port
    [[ "$consensus" == "poa" ]] && rpc_port=8545 || rpc_port=8645
    
    while [[ $retries -gt 0 ]]; do
        if curl -sf -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "http://localhost:${rpc_port}" &>/dev/null; then
            log "${consensus^^} network is ready (port ${rpc_port})"
            return 0
        fi
        retries=$((retries - 1))
        sleep 5
    done
    err "${consensus^^} network failed to start after 5 minutes"
}

stop_network() {
    local consensus="$1"
    log "Stopping ${consensus^^} network..."
    cd "${REPO_ROOT}/networks/${consensus}"
    docker-compose down -v --remove-orphans 2>/dev/null || true
}

deploy_contract() {
    local consensus="$1"
    local rpc_port
    [[ "$consensus" == "poa" ]] && rpc_port=8545 || rpc_port=8645
    
    log "Deploying CBDC contract to ${consensus^^} (port ${rpc_port})..."
    
    local contract_addr
    contract_addr=$(node "${REPO_ROOT}/scripts/deploy_contract.js" \
        "http://localhost:${rpc_port}" \
        "${REPO_ROOT}/contracts/CBDC.sol" \
        2>&1 | tail -1)
    
    echo "$contract_addr" > "${RESULTS_DIR}/${consensus}_contract_addr.txt"
    log "${consensus^^} contract deployed at: ${contract_addr}"
    echo "$contract_addr"
}

run_caliper() {
    local consensus="$1"
    local contract_addr="$2"
    local rpc_port
    [[ "$consensus" == "poa" ]] && rpc_port=8545 || rpc_port=8645
    
    log "Running Caliper benchmark for ${consensus^^}..."
    
    # Generate Caliper network config
    python3 "${REPO_ROOT}/scripts/gen_caliper_config.py" \
        "$consensus" "$rpc_port" "$contract_addr" \
        "${REPO_ROOT}/caliper/config/network-${consensus}.json"
    
    # Start resource monitor
    bash "${REPO_ROOT}/scripts/monitor_resources.sh" \
        "${RESULTS_DIR}/${consensus}_resources.csv" &
    local monitor_pid=$!
    
    # Run Caliper
    local caliper_result="${RESULTS_DIR}/${consensus}_caliper_report.html"
    local caliper_json="${RESULTS_DIR}/${consensus}_caliper_results.json"
    
    cd "${REPO_ROOT}"
    npx caliper launch manager \
        --caliper-workspace . \
        --caliper-networkconfig "caliper/config/network-${consensus}.json" \
        --caliper-benchconfig "caliper/config/benchmark.yaml" \
        --caliper-flow-only-test \
        --caliper-report-path "$caliper_result" \
        2>&1 | tee "${RESULTS_DIR}/${consensus}_caliper.log" || warn "Caliper exited with non-zero (check log)"
    
    # Stop resource monitor
    kill "$monitor_pid" 2>/dev/null || true
    
    # Parse results to JSON
    python3 "${REPO_ROOT}/scripts/parse_caliper_results.py" \
        "$caliper_result" "$caliper_json" "$consensus"
    
    log "Caliper ${consensus^^} complete → $caliper_json"
}

generate_reports() {
    log "Generating comparison graphs and reports..."
    python3 "${REPO_ROOT}/scripts/generate_report.py" \
        "${RESULTS_DIR}/poa_caliper_results.json" \
        "${RESULTS_DIR}/qbft_caliper_results.json" \
        "${RESULTS_DIR}/poa_resources.csv" \
        "${RESULTS_DIR}/qbft_resources.csv" \
        "${RESULTS_DIR}"
    
    log "Reports saved to ${RESULTS_DIR}/"
    ls -lh "${RESULTS_DIR}/"
}

cleanup() {
    log "Cleaning up networks..."
    stop_network "poa" || true
    stop_network "qbft" || true
}

# ─── Main execution ──────────────────────────────────────────────────────────
trap 'err "Script interrupted. Cleaning up..."; cleanup' INT TERM

print_banner
mkdir -p "$RESULTS_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

check_prerequisites
prepare_data

# ── Phase 1: PoA Benchmark ───────────────────────────────────────────────────
log "═══ PHASE 1: Clique PoA Benchmark ═══"
start_network "poa"
POA_CONTRACT=$(deploy_contract "poa")
run_caliper "poa" "$POA_CONTRACT"
stop_network "poa"

log "Cooling down 30s between benchmarks..."
sleep 30

# ── Phase 2: QBFT Benchmark ──────────────────────────────────────────────────
log "═══ PHASE 2: QBFT Benchmark ═══"
start_network "qbft"
QBFT_CONTRACT=$(deploy_contract "qbft")
run_caliper "qbft" "$QBFT_CONTRACT"
stop_network "qbft"

# ── Phase 3: Analysis & Reporting ────────────────────────────────────────────
log "═══ PHASE 3: Analysis & Reporting ═══"
generate_reports

log ""
log "════════════════════════════════════════════"
log "  Benchmark Complete! Results in: ${RESULTS_DIR}"
log "════════════════════════════════════════════"
log "  Key files:"
log "  • comparison_graphs.png   - TPS, Latency, CPU, Memory charts"
log "  • summary_report.html     - Full interactive HTML report"
log "  • benchmark_summary.json  - Machine-readable results"
log "  • poa_caliper_report.html - Raw Caliper PoA report"
log "  • qbft_caliper_report.html- Raw Caliper QBFT report"
