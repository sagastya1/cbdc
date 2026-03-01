# CBDC Blockchain Benchmark Suite

**Hyperledger Besu PoA (Clique) vs QBFT — powered by Hyperledger Caliper**  
One-command, fully automated, Docker-based, single-EC2 deployment.

---

## ASCII Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         AWS EC2  c5.4xlarge (16 vCPU / 32 GB RAM)              │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │  run.sh  (orchestrator)                                                   │  │
│  │                                                                           │  │
│  │  Phase 1: PoA                Phase 2: QBFT             Phase 3: Report   │  │
│  │  ─────────────────           ───────────────           ──────────────    │  │
│  │  genesis_gen ──►             genesis_gen ──►           parse_results     │  │
│  │  docker-compose up           docker-compose up         generate_graphs   │  │
│  │  deploy_contract.js          deploy_contract.js        html_report       │  │
│  │  caliper launch              caliper launch                              │  │
│  │  monitor_resources           monitor_resources                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│          │                                │                                      │
│          ▼                                ▼                                      │
│  ┌───────────────────┐          ┌─────────────────────┐                        │
│  │  Docker Network:  │          │  Docker Network:     │                        │
│  │  172.20.0.0/24    │          │  172.21.0.0/24       │                        │
│  │  (poa-net)        │          │  (qbft-net)          │                        │
│  │                   │          │                       │                        │
│  │  ┌─────────────┐  │          │  ┌────────────────┐  │                        │
│  │  │  besu-poa-  │  │          │  │  besu-qbft-    │  │                        │
│  │  │  bootnode   │◄─┤          │  │  bootnode      │◄─┤                        │
│  │  │  :8545 RPC  │  │          │  │  :8645 RPC     │  │                        │
│  │  │  :8546 WS   │  │          │  │  :8646 WS      │  │                        │
│  │  └──────┬──────┘  │          │  └───────┬────────┘  │                        │
│  │         │ enode   │          │          │ enode      │                        │
│  │  ┌──────▼──────┐  │          │  ┌───────▼────────┐  │                        │
│  │  │ validator1  │  │          │  │  validator1    │  │                        │
│  │  │ validator2  │  │          │  │  validator2    │  │                        │
│  │  │ validator3  │  │          │  │  validator3    │  │                        │
│  │  │             │  │          │  │                │  │                        │
│  │  │  Clique PoA │  │          │  │  QBFT (BFT)   │  │                        │
│  │  │  2s blocks  │  │          │  │  2s blocks     │  │                        │
│  │  └─────────────┘  │          │  └────────────────┘  │                        │
│  └───────────────────┘          └─────────────────────┘                        │
│          │                                │                                      │
│          ▼                                ▼                                      │
│  ┌───────────────────┐          ┌─────────────────────┐                        │
│  │  Hyperledger      │          │  Hyperledger         │                        │
│  │  Caliper 0.6.0    │          │  Caliper 0.6.0       │                        │
│  │                   │          │                       │                        │
│  │  Workloads:       │          │  Workloads:           │                        │
│  │  • mint           │          │  • mint               │                        │
│  │  • transfer       │          │  • transfer           │                        │
│  │  • balanceOf      │          │  • balanceOf          │                        │
│  │  • mixed          │          │  • mixed              │                        │
│  │    (dataset-      │          │    (dataset-          │                        │
│  │     driven)       │          │     driven)           │                        │
│  └───────────────────┘          └─────────────────────┘                        │
│          │                                │                                      │
│          └──────────────┬─────────────────┘                                      │
│                         ▼                                                        │
│                ┌────────────────┐                                                │
│                │  /results/     │                                                │
│                │  ────────────  │                                                │
│                │  comparison_   │                                                │
│                │  graphs.png    │                                                │
│                │  summary_      │                                                │
│                │  report.html   │                                                │
│                │  benchmark_    │                                                │
│                │  summary.json  │                                                │
│                │  *_caliper_    │                                                │
│                │  report.html   │                                                │
│                │  *_resources   │                                                │
│                │  .csv          │                                                │
│                └────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────────────────┘

Data Flow:
  realtime_txn_dataset.csv (71,250 Ethereum txns)
        │
        ▼  preprocess_data.py
  workload_addresses.json + tx_patterns.json
        │
        ▼  Caliper workload modules
  CBDC Contract calls (mint/transfer/balanceOf)
        │
        ▼  Benchmark execution
  TPS + Latency + Success Rate + CPU + Memory
        │
        ▼  generate_report.py
  Graphs + HTML Report + JSON Summary
```

---

## EC2 Sizing

| Dimension          | Recommendation     | Why                                                    |
|--------------------|-------------------|--------------------------------------------------------|
| **Instance type**  | `c5.4xlarge`       | 16 vCPU + 32 GB. Runs 8 Besu nodes + Caliper + monitoring simultaneously |
| **vCPU**           | 16 (minimum 8)     | 4 nodes × 2 per consensus = 8 Besu processes; Caliper needs 2+ |
| **RAM**            | 32 GB (minimum 16) | Each Besu node: ~2-3 GB JVM heap. Total 4 nodes × 2 networks = up to 24 GB |
| **Storage**        | 60 GB gp3          | Besu chain data + Docker images (~15 GB) + results + logs |
| **IOPS**           | 3,000 (gp3 base)   | Besu RocksDB is I/O heavy during block production |
| **Network**        | Up to 10 Gbps      | Docker bridge networking; external only for image pull |
| **OS**             | Amazon Linux 2023  | First-class Docker + AWS CLI support |
| **Estimated cost** | ~$0.68/hour        | Benchmark runs ~45-90 min = **$0.51–$1.02 total** |

**Minimum viable (dev/test):** `c5.2xlarge` (8 vCPU / 16 GB) — may swap under load.  
**High-throughput study:** `c5.9xlarge` (36 vCPU / 72 GB) for realistic 1000+ TPS benchmarks.

---

## Quick Start

### From AWS CloudShell (one-time EC2 deploy)

```bash
# 1. Open AWS CloudShell in your region
# 2. Paste and execute:

git clone https://github.com/YOUR_ORG/cbdc-benchmark.git
cd cbdc-benchmark

# Edit deploy_ec2.sh: set REPO_URL and optionally DATA_BUCKET
nano scripts/deploy_ec2.sh

bash scripts/deploy_ec2.sh
# → Outputs SSH command and instance IP
```

### On the EC2 Instance

```bash
# SSH in (key generated by deploy_ec2.sh)
ssh -i cbdc-benchmark-key.pem ec2-user@<PUBLIC_IP>

# Wait for bootstrap to finish (~3-5 min)
tail -f /var/log/cbdc-bootstrap.log

# Place your dataset (if not auto-downloaded from S3)
cp /path/to/realtime_txn_dataset.csv /data/

# ONE COMMAND to run everything
cd ~/cbdc-benchmark
bash run.sh
```

### Retrieve Results

```bash
# From your local machine or CloudShell:
scp -r -i cbdc-benchmark-key.pem \
    ec2-user@<IP>:/results/ \
    ./cbdc-benchmark-results/

# Open the report:
open cbdc-benchmark-results/summary_report.html
```

---

## Repository Structure

```
cbdc-benchmark/
├── run.sh                          # 🚀 ONE COMMAND to run all
├── package.json                    # Node.js deps (Caliper, Web3, solc)
├── .gitignore
│
├── contracts/
│   └── CBDC.sol                    # Minimal CBDC contract (mint/transfer/balanceOf)
│
├── networks/
│   ├── poa/
│   │   └── docker-compose.yml      # Besu Clique PoA (4 nodes, port 8545)
│   └── qbft/
│       └── docker-compose.yml      # Besu QBFT (4 nodes, port 8645)
│
├── caliper/
│   ├── config/
│   │   └── benchmark.yaml          # Caliper rounds: mint, transfer, balanceOf, mixed
│   └── workload/
│       ├── mint.js                 # Mint workload (dataset-driven addresses)
│       ├── transfer.js             # Transfer workload (replays tx patterns)
│       ├── balanceOf.js            # Read workload
│       └── mixed.js                # 70/20/10 mixed realistic workload
│
├── scripts/
│   ├── install_deps.sh             # Install Docker, Node, Python deps
│   ├── deploy_ec2.sh               # CloudShell → EC2 deployer
│   ├── generate_genesis.sh         # Create genesis + node keys
│   ├── gen_eth_key.py              # Ethereum key generation (pure Python)
│   ├── gen_qbft_extra.py           # QBFT extraData RLP encoder
│   ├── deploy_contract.js          # Compile + deploy CBDC.sol + batch mint
│   ├── preprocess_data.py          # Extract addresses/patterns from CSV dataset
│   ├── generate_dataset.py         # Synthetic fallback dataset generator
│   ├── gen_caliper_config.py       # Generate Caliper network JSON configs
│   ├── monitor_resources.sh        # Docker stats → CSV (CPU/memory/net)
│   ├── parse_caliper_results.py    # Parse Caliper HTML/log → JSON metrics
│   ├── generate_report.py          # matplotlib graphs + HTML report
│   └── clean.sh                    # Teardown containers + generated files
│
├── data/                           # → symlink /data/realtime_txn_dataset.csv
└── results/                        # → symlink /results/ (benchmark outputs)
```

---

## Output Files (`/results/`)

| File                          | Description                                      |
|-------------------------------|--------------------------------------------------|
| `comparison_graphs.png`       | 8-panel chart: TPS, latency, success rate, CPU, memory, latency distribution, radar chart, summary table |
| `summary_report.html`         | Full interactive HTML report with tables + embedded graph |
| `benchmark_summary.json`      | Machine-readable JSON with all metrics           |
| `poa_caliper_report.html`     | Raw Caliper HTML report for PoA                  |
| `qbft_caliper_report.html`    | Raw Caliper HTML report for QBFT                 |
| `poa_caliper_results.json`    | Parsed PoA metrics JSON                          |
| `qbft_caliper_results.json`   | Parsed QBFT metrics JSON                         |
| `poa_resources.csv`           | CPU/memory time-series for PoA run               |
| `qbft_resources.csv`          | CPU/memory time-series for QBFT run              |
| `workload_addresses.json`     | Unique addresses extracted from dataset          |
| `tx_patterns.json`            | Transfer patterns from dataset (from/to/amount)  |
| `benchmark.log`               | Full execution log                               |

---

## Benchmark Rounds

| Round           | TX Count | Rate Control   | Mix                |
|-----------------|----------|----------------|---------------------|
| `mint`          | 1,000    | Fixed 50 TPS   | 100% mint           |
| `transfer`      | 3,000    | Linear 20→150  | 100% transfer       |
| `balanceOf`     | 1,000    | Fixed 200 TPS  | 100% reads          |
| `mixed-realistic`| 2,000   | Fixed backlog  | 70% transfer, 20% mint, 10% query |

---

## Network Configuration

| Parameter         | PoA (Clique)     | QBFT              |
|-------------------|------------------|-------------------|
| Chain ID          | 1337             | 1338              |
| Block period      | 2 seconds        | 2 seconds         |
| Consensus         | Clique PoA       | QBFT (BFT)        |
| Validators        | 3                | 3                 |
| HTTP RPC port     | 8545             | 8645              |
| WS RPC port       | 8546             | 8646              |
| P2P port          | 30303            | 30403             |
| Gas price         | 0 (free)         | 0 (free)          |
| Gas limit         | 0x1fffffffffffff | 0x1fffffffffffff  |
| Subnet            | 172.20.0.0/24    | 172.21.0.0/24     |
| Fault tolerance   | None (leader)    | f = ⌊(n-1)/3⌋    |

---

## Dataset Integration

The benchmark uses `realtime_txn_dataset.csv` (71,250 real Ethereum transactions with fields: `hash`, `from_address`, `to_address`, `value`, `gas`, `gas_price`, `block_timestamp`, etc.).

**How it's used:**
1. `preprocess_data.py` extracts unique `from_address` / `to_address` values → `workload_addresses.json`
2. Value field is normalized to CBDC token amounts → `tx_patterns.json`
3. Caliper workload modules replay these real-world patterns against the CBDC contract
4. This creates a **realistic payment network simulation** based on actual Ethereum transaction characteristics

---

## CBDC Contract

```solidity
// Minimal CBDC.sol — 3 core operations + ERC-20 extensions
function mint(address to, uint256 amount) external onlyCentralBank
function transfer(address to, uint256 amount) external returns (bool)
function balanceOf(address account) external view returns (uint256)
function batchMint(address[] calldata recipients, uint256 amount) external  // pre-fund benchmark
function burn(uint256 amount) external                                       // settlement
```

---

## Consensus Comparison (Expected Results)

| Metric           | PoA (Clique)           | QBFT                   |
|------------------|------------------------|------------------------|
| Peak TPS         | Higher (~80–150)       | Moderate (~60–120)     |
| Avg Latency      | Lower (300–500ms)      | Higher (500–800ms)     |
| Finality         | Probabilistic (forks possible) | Absolute (no forks) |
| Fault Tolerance  | N/A (trusted validators) | Byzantine (f=(n-1)/3) |
| Best use case    | Retail CBDC payments   | Interbank settlement   |

*Actual results vary by EC2 load, dataset, and block period.*

---

## Troubleshooting

```bash
# Check container health
docker ps
docker logs besu-poa-bootnode --tail 50
docker logs besu-qbft-bootnode --tail 50

# Test RPC connectivity
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Re-run individual phase
bash scripts/generate_genesis.sh poa
docker-compose -f networks/poa/docker-compose.yml up -d

# Reset everything
bash scripts/clean.sh
```

---

## License

MIT — See LICENSE file.
