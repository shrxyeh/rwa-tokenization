# RWA Tokenization

Real-world asset tokenization on Ethereum — ERC-721 property deeds, ERC-20 fractional ownership, on-chain KYC compliance, and dividend distribution.

## Structure

```
rwa-tokenization/
├── backend/    # Foundry smart contracts (Solidity ^0.8.24)
└── frontend/   # Next.js 14 dApp (wagmi v2, RainbowKit)
```

## Quick start

**Contracts**
```bash
cd backend
forge install          # install dependencies
forge build            # compile
forge test             # run 128 tests
cp .env.example .env   # fill in RPC + wallet keys
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
```

**Frontend**
```bash
cd frontend
npm install
cp .env.example .env.local   # paste deployed contract addresses
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Docs

See [backend/README.md](backend/README.md) for full contract architecture, security notes, and deployment guide.
