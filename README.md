# rwa-tokenization

Tokenize real-world property on Ethereum. Each asset gets an ERC-721 deed and a compliance-gated ERC-20 for fractional ownership. Dividends are distributed pro-rata using ERC20Votes snapshots.

## Deployments

**Sepolia testnet**

| Contract | Address |
|---|---|
| IdentityRegistry | [`0x278f7ff4DA46fF0527Bea05fe8B85d993FFF1502`](https://sepolia.etherscan.io/address/0x278f7ff4da46ff0527bea05fe8b85d993fff1502#code) |
| PropertyNFT | [`0x7Ae673B7534D1e1F4c3cc7d6bF1eBdee49ee85Cd`](https://sepolia.etherscan.io/address/0x7ae673b7534d1e1f4c3cc7d6bf1ebdee49ee85cd#code) |
| RWAFactory | [`0x126688efc91B4927418094d9d206c7B895a918F1`](https://sepolia.etherscan.io/address/0x126688efc91b4927418094d9d206c7b895a918f1#code) |

All contracts are verified. Source visible on Etherscan.

## Repo

```
rwa-tokenization/
├── backend/    Foundry — Solidity ^0.8.24, 128 tests
└── frontend/   Next.js 14 — wagmi v2, RainbowKit, Tailwind
```

## Quickstart

```bash
# contracts
cd backend
forge install && forge build && forge test

# frontend (contracts already deployed above)
cd frontend
npm install
cp .env.example .env.local   # paste contract addresses
npm run dev
```

Full setup and architecture: [`backend/README.md`](backend/README.md)
