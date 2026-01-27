# SYSTEM ARCHITECTURE - DISTRIBUTED LEDGER v2.4

## 1. Overview
This document outlines the proposed changes to the core consensus engine. We are moving from a Proof-of-Work (PoW) model to a delegated Proof-of-Stake (dPoS) to improve throughput and reduce energy consumption.

## 2. Components
### 2.1 The Validator Set
Validators are elected by token holders. The top 21 candidates by weight are selected to produce blocks in a round-robin fashion.

| Component | Description | Responsibility |
| :--- | :--- | :--- |
| P2P Layer | libp2p based | Node discovery and gossip |
| Storage | RocksDB | Local state and block history |
| VM | WASM | Smart contract execution |

## 3. Consensus Flow
1. **Proposal**: A validator is selected based on the schedule.
2. **Pre-commit**: Other validators verify the block and sign.
3. **Commitment**: Once 2/3+1 signatures are collected, the block is finalized.

### 4. Known Issues
- Network latency can lead to missed slots if the block time is under 500ms.
- Current slashing logic is too aggressive for minor uptime issues.

---
*Internal use only. Do not distribute without permission.*
