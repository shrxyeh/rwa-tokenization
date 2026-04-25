export interface PropertyMetadata {
  name: string;
  location: string;
  valuationUSD: bigint;
  legalIdentifier: string;
  mintedAt: bigint;
  originalOwner: `0x${string}`;
}

export interface AssetRecord {
  tokenId: bigint;
  fractionToken: `0x${string}`;
  assetName: string;
  createdAt: bigint;
}

export interface InvestorData {
  kycExpiry: bigint;
  investorTier: number;
  jurisdiction: `0x${string}`;
  active: boolean;
}

export interface DividendRound {
  totalETH: bigint;
  snapshotBlock: bigint;
  claimedCount: bigint;
  totalSupplyAtSnapshot: bigint;
}

export type Address = `0x${string}`;
