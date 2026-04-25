# RWA Tokenization — Smart Contracts

Ethereum contracts for tokenizing real-world property assets. Each property is an ERC-721 deed; fractional ownership is an ERC-20 token gated by an on-chain compliance registry.

## Architecture

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                         RWAFactory                               │
  │  One atomic tx: mint NFT → deploy token → link → distribute      │
  └──────┬────────────────────────────┬────────────────────────────┘
         │ mintProperty()              │ new FractionalToken()
         ▼                             ▼
  ┌─────────────────┐         ┌────────────────────────────┐
  │   PropertyNFT   │◄────────│     FractionalToken        │
  │   (ERC-721)     │  link   │  (ERC-20 + Votes + Permit) │
  │  On-chain SVG   │         │  Compliance hook in _update │
  │  Deed metadata  │         │  Dividend distribution      │
  └─────────────────┘         └──────────┬─────────────────┘
                                          │ validateTransfer()
                                          ▼
                               ┌──────────────────────┐
                               │  IdentityRegistry     │
                               │  (ERC-3643 inspired)  │
                               │  KYC expiry           │
                               │  Investor tiers       │
                               │  Jurisdiction blocks  │
                               │  Global pause         │
                               └──────────────────────┘
```

## Contracts

| Contract           | Standard            | Description                                    |
|--------------------|---------------------|------------------------------------------------|
| IdentityRegistry   | ERC-3643 inspired   | KYC whitelist, transfer compliance gate        |
| PropertyNFT        | ERC-721             | On-chain property deed with SVG token URI      |
| FractionalToken    | ERC-20 + Votes      | Fractional ownership, dividends, ERC-2612 permit |
| RWAFactory         | —                   | Atomic single-tx asset creation                |
| PropertyNFTV2      | UUPS + ERC-721      | Upgradeable NFT with annotation support        |
| FractionalTokenV2  | UUPS + ERC-20       | Upgradeable token with vesting locks           |

## Design Notes

**Snapshot-based dividends** — `ERC20Votes` checkpoints serve as the snapshot mechanism. `depositDividend()` records `block.number - 1` as the snapshot; `claimDividend()` uses `getPastVotes()` at that exact block. Investors who buy tokens after a deposit cannot claim that round.

**`bytes32` jurisdiction codes** — `bytes32("US")` instead of `string` saves a storage slot per investor and eliminates dynamic-length overhead on every compliance check.

**UUPS over Transparent Proxy** — Upgrade logic lives in the implementation, not a separate `ProxyAdmin`. Lower deployment cost, no function-selector clash, and a single auditable `_authorizeUpgrade(onlyOwner)` path.

**Immutable registry address** — The `identityRegistry` address in `FractionalToken` is `immutable`. No owner function can swap it to a permissive stub post-deploy.

**Custom errors everywhere** — No string storage for revert reasons. Cheaper to deploy, cheaper to revert, and structured for off-chain tooling.

**On-chain SVG deed** — Token metadata is fully self-contained. No IPFS, no external dependencies. The SVG is base64-encoded inline and returned as a `data:application/json;base64,…` URI — permanent and verifiable on-chain.

## Setup

### Prerequisites

- [Foundry](https://getfoundry.sh): `curl -L https://foundry.paradigm.xyz | bash`
- [Alchemy](https://www.alchemy.com) account for Sepolia RPC
- [Etherscan](https://etherscan.io/register) account for verification

### Install

```bash
git clone <your-repo>
cd rwa-tokenization/backend
forge install
cp .env.example .env
# fill in SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
```

### Test

```bash
forge test                                              # 128 tests
forge test --match-contract Compliance -vvv             # integration suite
forge test --match-test test_DividendFullCycle -vvvv    # single test, full trace
forge coverage --ir-minimum                             # coverage report
```

### Deploy

```bash
source .env
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

### Local demo (anvil)

```bash
anvil &
source .env
forge script script/Demo.s.sol --rpc-url localhost --broadcast
```

## Test Coverage

```
128 tests across 6 suites — 0 failures

IdentityRegistry.t.sol  22 tests  roles, KYC lifecycle, pause, jurisdiction, validateTransfer
PropertyNFT.t.sol        23 tests  mint, metadata, on-chain SVG URI, link, valuation, ownership
FractionalToken.t.sol    23 tests  mint, compliance transfers, tier cap, dividends, ERC-2612 permit
RWAFactory.t.sol         12 tests  atomic deploy, NFT ownership transfer, fraction linking, records
Compliance.t.sol          9 tests  end-to-end: full flow, revoke, expiry, dividend round, jurisdiction
Upgrades.t.sol           39 tests  UUPS proxy, state preservation, V2 features, access control
```

## Deployed Contracts (Sepolia)

> Run the deploy script and update these addresses.

| Contract         | Address |
|------------------|---------|
| IdentityRegistry | `—`     |
| PropertyNFT      | `—`     |
| RWAFactory       | `—`     |

## Assumptions

| Feature            | Simulated here                      | Production equivalent                          |
|--------------------|-------------------------------------|------------------------------------------------|
| KYC verification   | On-chain whitelist by admin/agent   | Webhook from Jumio, Onfido, or similar         |
| Property valuation | Static USD integer set by owner     | Chainlink oracle or trusted appraiser feed     |
| Jurisdiction codes | `bytes32("US")` etc.                | OFAC/FATF API, real-time sanctions list        |
| Dividend source    | Manual ETH deposit by owner         | Automated from rental income via property mgmt |
| Legal ownership    | `legalIdentifier` string            | On-chain SPV structure, legal wrapper          |
