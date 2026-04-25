# Smart Contracts

Solidity ^0.8.24 · Foundry · OpenZeppelin v5

## Deployments

**Sepolia**

| Contract | Address | Etherscan |
|---|---|---|
| IdentityRegistry | `0x278f7ff4DA46fF0527Bea05fe8B85d993FFF1502` | [view](https://sepolia.etherscan.io/address/0x278f7ff4da46ff0527bea05fe8b85d993fff1502#code) |
| PropertyNFT | `0x7Ae673B7534D1e1F4c3cc7d6bF1eBdee49ee85Cd` | [view](https://sepolia.etherscan.io/address/0x7ae673b7534d1e1f4c3cc7d6bf1ebdee49ee85cd#code) |
| RWAFactory | `0x126688efc91B4927418094d9d206c7B895a918F1` | [view](https://sepolia.etherscan.io/address/0x126688efc91b4927418094d9d206c7b895a918f1#code) |

## Contracts

| Contract | Standard | Description |
|---|---|---|
| `IdentityRegistry` | ERC-3643 pattern | KYC whitelist, tier system, jurisdiction blocks, global pause |
| `PropertyNFT` | ERC-721 | On-chain SVG deed, valuation, legal identifier |
| `FractionalToken` | ERC-20 + Votes + Permit | Compliance-gated transfers, snapshot dividends |
| `RWAFactory` | — | Single-tx: mint NFT → deploy token → link → distribute supply |
| `PropertyNFTV2` | UUPS + ERC-721 | Upgradeable NFT with annotation support |
| `FractionalTokenV2` | UUPS + ERC-20 | Upgradeable token with vesting locks |

## Architecture

```
                    ┌─────────────────┐
                    │   RWAFactory    │
                    │  (orchestrator) │
                    └───────┬─────────┘
               mint NFT     │     deploy + link token
              ┌─────────────┴──────────────┐
              ▼                             ▼
   ┌─────────────────┐          ┌──────────────────────┐
   │   PropertyNFT   │◄─ link ──│   FractionalToken    │
   │   ERC-721       │          │   ERC-20 + Votes     │
   │   On-chain SVG  │          │   _update() → check  │
   └─────────────────┘          └──────────┬───────────┘
                                            │ validateTransfer()
                                            ▼
                                 ┌──────────────────────┐
                                 │  IdentityRegistry    │
                                 │  KYC expiry          │
                                 │  Investor tiers      │
                                 │  Jurisdiction blocks │
                                 │  Global pause        │
                                 └──────────────────────┘
```

`createAsset()` is atomic — if any step fails the entire transaction reverts.

## Setup

**Prerequisites:** [Foundry](https://getfoundry.sh), an Alchemy Sepolia endpoint, an Etherscan API key.

```bash
git clone https://github.com/shrxyeh/rwa-tokenization
cd rwa-tokenization/backend
forge install
cp .env.example .env
# fill SEPOLIA_RPC_URL, PRIVATE_KEY, ETHERSCAN_API_KEY
```

## Testing

```bash
forge test                                           # 128 tests
forge test -vvv                                      # with traces
forge test --match-contract FractionalToken          # single suite
forge coverage                                       # coverage report
```

```
IdentityRegistry.t.sol   22   roles, KYC lifecycle, pause, jurisdiction, validateTransfer
PropertyNFT.t.sol        23   mint, metadata, on-chain SVG, link, valuation
FractionalToken.t.sol    23   transfers, tier cap, dividends, ERC-2612 permit
RWAFactory.t.sol         12   atomic deploy, ownership, linking, records
Compliance.t.sol          9   end-to-end: full flow, revoke, expiry, dividend cycle
Upgrades.t.sol           39   UUPS proxy, state preservation, V2 features, access control
─────────────────────────────
                        128   0 failures
```

## Deploy

```bash
source .env

# Sepolia
forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Grant AGENT_ROLE to your wallet
forge script script/GrantRole.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast
```

**Post-deploy:** delegate your votes before depositing dividends.

```bash
cast send <FRACTION_TOKEN> "delegate(address)" <YOUR_WALLET> \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

## Local Demo

Runs the full lifecycle (deploy → KYC → tokenize → distribute → compliance checks) against a local fork.

```bash
anvil --fork-url $SEPOLIA_RPC_URL &
forge script script/Demo.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Design Notes

**Dividend snapshots** — `depositDividend()` records `block.number - 1` as the snapshot; `claimDividend()` calls `getPastVotes()` at that exact block. Tokens bought after a deposit cannot claim that round.

**Immutable registry** — `identityRegistry` in `FractionalToken` is `immutable`. It cannot be replaced with a permissive stub after deployment.

**bytes32 jurisdictions** — `bytes32("US")` instead of `string` saves a storage slot per investor and eliminates dynamic-length overhead on every compliance check.

**UUPS over Transparent Proxy** — upgrade logic lives in the implementation. Lower deployment gas, no `ProxyAdmin`, single `_authorizeUpgrade` path to audit.

**Custom errors** — no string storage for revert reasons. Cheaper to deploy, cheaper to revert, structured for off-chain decoding.

**On-chain SVG** — token metadata is self-contained. No IPFS. The SVG is base64-encoded and returned as `data:application/json;base64,...` — verifiable and permanent.

## Production Considerations

| This repo | Production equivalent |
|---|---|
| On-chain KYC whitelist | Webhook from Jumio, Onfido, or similar |
| Static USD valuation | Chainlink oracle or appraiser feed |
| `bytes32` jurisdiction codes | OFAC/FATF real-time sanctions list |
| Manual ETH dividend deposit | Automated from rental/revenue stream |
| `legalIdentifier` string | On-chain SPV, legal wrapper |
