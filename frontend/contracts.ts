/**
 * DCasino Contract Configuration
 *
 * This file provides contract addresses and ABIs for frontend integration.
 * Update the addresses after deployment.
 */

// ============================================================================
// Network Configuration
// ============================================================================

export enum ChainId {
  ARBITRUM_ONE = 42161,
  ARBITRUM_SEPOLIA = 421614,
  BASE = 8453,
  BASE_SEPOLIA = 84532,
  LOCALHOST = 31337,
}

export interface NetworkConfig {
  name: string;
  chainId: ChainId;
  rpcUrl: string;
  blockExplorer: string;
  vrfCoordinator: string;
}

export const NETWORKS: Record<ChainId, NetworkConfig> = {
  [ChainId.ARBITRUM_ONE]: {
    name: "Arbitrum One",
    chainId: ChainId.ARBITRUM_ONE,
    rpcUrl: "https://arb1.arbitrum.io/rpc",
    blockExplorer: "https://arbiscan.io",
    vrfCoordinator: "0x41034678D6C633D8a95c75e1138A360a28bA15d1",
  },
  [ChainId.ARBITRUM_SEPOLIA]: {
    name: "Arbitrum Sepolia",
    chainId: ChainId.ARBITRUM_SEPOLIA,
    rpcUrl: "https://sepolia-rollup.arbitrum.io/rpc",
    blockExplorer: "https://sepolia.arbiscan.io",
    vrfCoordinator: "0x5CE8D5A2BC84beb22a398CCA51996F7930313D61",
  },
  [ChainId.BASE]: {
    name: "Base",
    chainId: ChainId.BASE,
    rpcUrl: "https://mainnet.base.org",
    blockExplorer: "https://basescan.org",
    vrfCoordinator: "0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634",
  },
  [ChainId.BASE_SEPOLIA]: {
    name: "Base Sepolia",
    chainId: ChainId.BASE_SEPOLIA,
    rpcUrl: "https://sepolia.base.org",
    blockExplorer: "https://sepolia.basescan.org",
    vrfCoordinator: "0x5C210eF41CD1a72de73bF76eC39637bB0dc89a52",
  },
  [ChainId.LOCALHOST]: {
    name: "Localhost",
    chainId: ChainId.LOCALHOST,
    rpcUrl: "http://127.0.0.1:8545",
    blockExplorer: "",
    vrfCoordinator: "0x0000000000000000000000000000000000000000",
  },
};

// ============================================================================
// Contract Addresses (Update after deployment)
// ============================================================================

export interface ContractAddresses {
  casino: `0x${string}`;
  treasury: `0x${string}`;
  gameRegistry: `0x${string}`;
  vrfConsumer: `0x${string}`;
  gameResolver: `0x${string}`;
  roulette: `0x${string}`;
  blackjack: `0x${string}`;
}

// Placeholder addresses - update after deployment
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const;

export const CONTRACT_ADDRESSES: Partial<Record<ChainId, ContractAddresses>> = {
  // Update these after deployment
  [ChainId.ARBITRUM_SEPOLIA]: {
    casino: ZERO_ADDRESS,
    treasury: ZERO_ADDRESS,
    gameRegistry: ZERO_ADDRESS,
    vrfConsumer: ZERO_ADDRESS,
    gameResolver: ZERO_ADDRESS,
    roulette: ZERO_ADDRESS,
    blackjack: ZERO_ADDRESS,
  },
  [ChainId.ARBITRUM_ONE]: {
    casino: ZERO_ADDRESS,
    treasury: ZERO_ADDRESS,
    gameRegistry: ZERO_ADDRESS,
    vrfConsumer: ZERO_ADDRESS,
    gameResolver: ZERO_ADDRESS,
    roulette: ZERO_ADDRESS,
    blackjack: ZERO_ADDRESS,
  },
};

// ============================================================================
// Game Constants
// ============================================================================

export const ROULETTE = {
  // Bet types
  BetType: {
    Straight: 0, // Single number (35:1)
    Split: 1,    // Two numbers (17:1)
    Street: 2,   // Three numbers (11:1)
    Corner: 3,   // Four numbers (8:1)
    Line: 4,     // Six numbers (5:1)
    Column: 5,   // Twelve numbers (2:1)
    Dozen: 6,    // Twelve numbers (2:1)
    Red: 7,      // Eighteen numbers (1:1)
    Black: 8,    // Eighteen numbers (1:1)
    Odd: 9,      // Eighteen numbers (1:1)
    Even: 10,    // Eighteen numbers (1:1)
    Low: 11,     // 1-18 (1:1)
    High: 12,    // 19-36 (1:1)
  },

  // Red numbers on the wheel
  RED_NUMBERS: [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36],

  // House edge in basis points (2.7%)
  HOUSE_EDGE: 270,

  // Maximum bets per transaction
  MAX_BETS: 10,
} as const;

export const BLACKJACK = {
  // Game states
  GameState: {
    Betting: 0,
    Dealing: 1,
    PlayerTurn: 2,
    DealerTurn: 3,
    Resolved: 4,
  },

  // Player actions
  Action: {
    Hit: 0,
    Stand: 1,
    DoubleDown: 2,
    Split: 3,
    Insurance: 4,
  },

  // Outcomes
  Outcome: {
    Pending: 0,
    PlayerBlackjack: 1,
    DealerBlackjack: 2,
    PlayerWin: 3,
    DealerWin: 4,
    Push: 5,
    PlayerBust: 6,
    DealerBust: 7,
  },

  // Card helpers
  getRank: (cardId: number): number => cardId % 13,
  getSuit: (cardId: number): number => Math.floor(cardId / 13),
  getRankName: (rank: number): string => {
    const names = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
    return names[rank];
  },
  getSuitName: (suit: number): string => {
    const names = ["Hearts", "Diamonds", "Clubs", "Spades"];
    return names[suit];
  },
  getSuitSymbol: (suit: number): string => {
    const symbols = ["\u2665", "\u2666", "\u2663", "\u2660"]; // ♥ ♦ ♣ ♠
    return symbols[suit];
  },
  getCardDisplay: (cardId: number): string => {
    const rank = cardId % 13;
    const suit = Math.floor(cardId / 13);
    const names = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
    const symbols = ["\u2665", "\u2666", "\u2663", "\u2660"];
    return `${names[rank]}${symbols[suit]}`;
  },

  // House edge in basis points (0.5%)
  HOUSE_EDGE: 50,

  // Max splits allowed
  MAX_SPLITS: 3,
} as const;

// ============================================================================
// Treasury Constants
// ============================================================================

export const TREASURY = {
  // Default bet limits (in wei)
  DEFAULT_MIN_BET: BigInt("1000000000000000"), // 0.001 ETH
  DEFAULT_MAX_BET: BigInt("10000000000000000000"), // 10 ETH

  // Fee percentage in basis points (0.5%)
  DEFAULT_FEE: 50,

  // Max payout ratio in basis points (5%)
  DEFAULT_MAX_PAYOUT_RATIO: 500,
} as const;

// ============================================================================
// Helper Functions
// ============================================================================

export function getContractAddress(
  chainId: ChainId,
  contract: keyof ContractAddresses
): `0x${string}` | undefined {
  return CONTRACT_ADDRESSES[chainId]?.[contract];
}

export function getBlockExplorerUrl(chainId: ChainId, address: string): string {
  const network = NETWORKS[chainId];
  if (!network?.blockExplorer) return "";
  return `${network.blockExplorer}/address/${address}`;
}

export function getBlockExplorerTxUrl(chainId: ChainId, txHash: string): string {
  const network = NETWORKS[chainId];
  if (!network?.blockExplorer) return "";
  return `${network.blockExplorer}/tx/${txHash}`;
}

export function formatEth(wei: bigint, decimals = 4): string {
  const eth = Number(wei) / 1e18;
  return eth.toFixed(decimals);
}

export function parseEth(eth: string | number): bigint {
  return BigInt(Math.floor(Number(eth) * 1e18));
}

// ============================================================================
// Event Types (for frontend event listeners)
// ============================================================================

export interface BetPlacedEvent {
  betId: bigint;
  player: `0x${string}`;
  amount: bigint;
  potentialPayout: bigint;
}

export interface BetResolvedEvent {
  betId: bigint;
  player: `0x${string}`;
  payout: bigint;
  won: boolean;
}

export interface RouletteBetEvent extends BetPlacedEvent {
  bets: Array<{
    betType: number;
    numbers: number[];
    amount: bigint;
  }>;
}

export interface BlackjackGameEvent {
  betId: bigint;
  player: `0x${string}`;
  state: number;
  playerCards: number[];
  dealerCards: number[];
}
