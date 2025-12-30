# DCasino - Decentralized Casino dApp

A modular, upgradeable smart contract system for decentralized casino games on EVM-compatible blockchains. Built with Foundry and designed for Arbitrum/Base L2 deployment.

## Architecture

```
                    ┌─────────────────┐
                    │     Casino      │
                    │  (Admin Hub)    │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
┌────────▼────────┐  ┌───────▼───────┐  ┌────────▼────────┐
│  GameRegistry   │  │   VRFConsumer │  │    Treasury     │
│ (Plugin System) │  │  (Randomness) │  │   (Bankroll)    │
└────────┬────────┘  └───────┬───────┘  └────────┬────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                    ┌────────▼────────┐
                    │  BaseGameVRF    │
                    │   (Abstract)    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  GameResolver   │
                    │  (Automation)   │
                    └─────────────────┘
```

### Core Contracts

| Contract | Description |
|----------|-------------|
| **Casino.sol** | Central admin hub - manages ecosystem pause, treasury/registry references, emergency functions |
| **Treasury.sol** | Bankroll management - deposits, withdrawals, bet reservations, payouts, fee collection |
| **GameRegistry.sol** | Plugin architecture - game registration, enable/disable, statistics tracking |
| **BaseGame.sol** | Abstract game template - common bet logic, treasury integration |
| **BaseGameVRF.sol** | VRF-enabled game template - extends BaseGame with Chainlink VRF integration |

### Chainlink Integration (Phase 2)

| Contract | Description |
|----------|-------------|
| **VRFConsumer.sol** | Centralized VRF manager - handles randomness requests/callbacks for all games |
| **GameResolver.sol** | Chainlink Automation - automatically triggers bet resolution for pending bets |

### Role Hierarchy

```
DEFAULT_ADMIN_ROLE (Owner/Multisig)
       │
  ┌────┴────┬──────────────┬──────────────┐
  │         │              │              │
PAUSER   TREASURY_ROLE   GAME_MANAGER  UPGRADER
  │                                       │
  └── Controls pause/unpause              └── Can upgrade contracts

GAME_ROLE ── Registered games can call treasury functions
RESOLVER_ROLE ── Can resolve bets (VRFConsumer)
REQUESTER_ROLE ── Can request VRF randomness
FORWARDER_ROLE ── Chainlink Automation forwarder
OPERATOR_ROLE ── Game operators (pause individual games, set bet limits)
```

### VRF Flow

```
Player places bet → Game requests randomness → VRFConsumer
                                                    │
                                                    ▼
                                          VRF Coordinator
                                                    │
                                                    ▼
                                   rawFulfillRandomWords()
                                                    │
                                                    ▼
                                         Game.resolveBet()
                                                    │
                              ┌─────────────────────┼─────────────────────┐
                              │                                           │
                           Win: Payout                              Loss: Release
```

### Treasury Flow

```
Bankroll Providers → deposit() → Treasury
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
              Available      Reserved (bets)    Fees
                    │               │               │
                    ▼               ▼               ▼
               withdraw()    processPayout()   withdrawFees()
```

**Key Parameters:**
- Available = Total Balance - Reserved
- Max Payout = Available × 5% (configurable)
- Protocol Fee = 0.5% of bets (configurable)
- Min Bet = 0.001 ETH, Max Bet = 10 ETH (configurable)

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Setup

```bash
# Clone the repository
git clone <repository-url>
cd dcasino

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

## Project Structure

```
dcasino/
├── src/
│   ├── Casino.sol                  # Main admin hub
│   ├── Treasury.sol                # Bankroll management
│   ├── GameRegistry.sol            # Game registration
│   ├── interfaces/
│   │   ├── ICasino.sol
│   │   ├── ITreasury.sol
│   │   ├── IGameRegistry.sol
│   │   ├── IGame.sol
│   │   └── IVRFConsumer.sol
│   ├── abstracts/
│   │   ├── BaseGame.sol            # Abstract base for games
│   │   └── BaseGameVRF.sol         # VRF-enabled game base
│   ├── games/                      # Game implementations (Phase 3-4)
│   │   ├── Roulette.sol
│   │   └── Blackjack.sol
│   ├── chainlink/
│   │   ├── VRFConsumer.sol         # Centralized VRF manager
│   │   ├── GameResolver.sol        # Chainlink Automation
│   │   ├── VRFConsumerBaseV2Plus.sol
│   │   └── interfaces/
│   │       ├── IVRFCoordinatorV2Plus.sol
│   │       └── IAutomationCompatible.sol
│   └── libraries/
│       ├── Errors.sol              # Custom errors
│       ├── BetLib.sol              # Bet structures
│       ├── PayoutLib.sol           # Payout calculations
│       ├── RouletteLib.sol         # Roulette bet types & validation
│       └── BlackjackLib.sol        # Card handling & hand calculations
├── test/
│   ├── unit/                       # Unit tests
│   ├── integration/                # Integration tests
│   └── mocks/                      # Mock contracts
└── script/                         # Deployment scripts
```

## Usage

### Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/unit/Treasury.t.sol

# Run with gas reporting
forge test --gas-report

# Run fuzz tests with more runs
forge test --fuzz-runs 10000

# Generate coverage report
forge coverage
```

### Building

```bash
# Compile contracts
forge build

# Clean build artifacts
forge clean

# Check contract sizes
forge build --sizes
```

### Formatting

```bash
# Format code
forge fmt

# Check formatting
forge fmt --check
```

## Contract Details

### Treasury

The Treasury contract manages the casino's bankroll:

```solidity
// Deposit funds
treasury.deposit{value: 100 ether}();

// Check available balance (total - reserved)
uint256 available = treasury.getAvailableBalance();

// Check maximum payout allowed
uint256 maxPayout = treasury.getMaxPayout();

// Reserve funds for a pending bet (called by games)
treasury.reserveFunds(potentialPayout);

// Process payout to winner (called by games)
treasury.processPayout(player, amount);

// Release reserved funds (called by games on loss)
treasury.releaseFunds(potentialPayout);
```

### GameRegistry

The GameRegistry manages game plugins:

```solidity
// Register a new game
bytes32 gameId = registry.registerGame(gameAddress, "Roulette");

// Check if game is active
bool active = registry.isActiveGame(gameAddress);

// Disable a game
registry.disableGame(gameAddress);

// Get game statistics
IGameRegistry.GameInfo memory info = registry.getGameByAddress(gameAddress);
```

### VRFConsumer

The VRFConsumer handles Chainlink VRF V2.5 randomness:

```solidity
// Request randomness for a bet
uint256 requestId = vrfConsumer.requestRandomness(gameAddress, betId);

// Check if request is pending
bool pending = vrfConsumer.isPending(requestId);

// Get request details
VRFRequest memory request = vrfConsumer.getRequest(requestId);

// Get VRF statistics
(uint256 requests, uint256 fulfilled, uint256 pending) = vrfConsumer.getStats();
```

### GameResolver

The GameResolver implements Chainlink Automation:

```solidity
// Enable automation for a game
resolver.enableAutomation(gameAddress);

// Check if upkeep is needed (called by Chainlink nodes)
(bool upkeepNeeded, bytes memory performData) = resolver.checkUpkeep("");

// Perform upkeep (resolve bets)
resolver.performUpkeep(performData);

// Manual upkeep for testing/emergency
resolver.manualUpkeep(gameAddress, betIds);
```

### BaseGameVRF

Games with VRF inherit from BaseGameVRF:

```solidity
contract MyGame is BaseGameVRF {
    function initialize(
        address admin,
        address casino,
        address treasury,
        address registry,
        address vrfConsumer
    ) external initializer {
        __BaseGameVRF_init(admin, "MyGame", casino, treasury, registry, vrfConsumer);
    }

    function _calculatePotentialPayout(uint256 amount, bytes calldata betData)
        internal view override returns (uint256)
    {
        // Calculate max possible payout for this bet
    }

    function _resolveBet(BetLib.Bet storage bet, uint256[] calldata randomWords)
        internal override returns (bool won, uint256 payout)
    {
        // Determine outcome using random values
    }
}
```

### Roulette

European roulette with single zero (0-36) and all standard bet types:

```solidity
// Place a straight bet (single number, pays 35:1)
roulette.placeStraightBet{value: 1 ether}(17);

// Place a split bet (two adjacent numbers, pays 17:1)
roulette.placeSplitBet{value: 1 ether}(17, 18);

// Place even-money bets (pays 1:1)
roulette.placeRedBet{value: 1 ether}();
roulette.placeBlackBet{value: 1 ether}();
roulette.placeOddBet{value: 1 ether}();
roulette.placeEvenBet{value: 1 ether}();
roulette.placeLowBet{value: 1 ether}();   // 1-18
roulette.placeHighBet{value: 1 ether}();  // 19-36

// Place 2:1 bets
roulette.placeColumnBet{value: 1 ether}(1);  // Column 1, 2, or 3
roulette.placeDozenBet{value: 1 ether}(2);   // Dozen 1, 2, or 3

// Place multiple bets in a single transaction
RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](2);
bets[0] = RouletteLib.RouletteBet({
    betType: RouletteLib.BetType.Straight,
    numbers: [17],
    amount: 0.5 ether
});
bets[1] = RouletteLib.RouletteBet({
    betType: RouletteLib.BetType.Red,
    numbers: RouletteLib.getRedNumbers(),
    amount: 0.5 ether
});
roulette.placeBet{value: 1 ether}(abi.encode(bets));

// View functions
uint8 winningNumber = roulette.getWinningNumber(betId);
RouletteLib.RouletteBet[] memory placedBets = roulette.getRouletteBets(betId);
```

**Bet Types and Payouts:**

| Bet Type | Numbers Covered | Payout |
|----------|----------------|--------|
| Straight | 1 | 35:1 |
| Split | 2 | 17:1 |
| Street | 3 | 11:1 |
| Corner | 4 | 8:1 |
| Line | 6 | 5:1 |
| Column | 12 | 2:1 |
| Dozen | 12 | 2:1 |
| Red/Black | 18 | 1:1 |
| Odd/Even | 18 | 1:1 |
| High/Low | 18 | 1:1 |

**House Edge:** 2.7% (European roulette with single zero)

### Blackjack

Standard Vegas blackjack with single 52-card deck:

```solidity
// Place a blackjack bet
uint256 betId = blackjack.placeBet{value: 1 ether}("");

// After initial deal (VRF callback), player can take actions:
blackjack.hit(betId);              // Take another card
blackjack.stand(betId);            // Stand on current hand
blackjack.doubleDown{value: 1 ether}(betId);  // Double bet, take one card, stand

// Splitting (when initial cards have same rank)
blackjack.split{value: 1 ether}(betId);  // Split into two hands

// Insurance (when dealer shows Ace)
blackjack.takeInsurance(betId);    // Side bet against dealer blackjack

// View functions
(uint8[] memory cardIds, uint8 value, bool isSoft, bool isBlackjack) = blackjack.getPlayerHand(betId, 0);
(uint8[] memory dealerCardIds, uint8 dealerValue, bool dealerSoft, bool dealerBJ) = blackjack.getDealerHand(betId);
BlackjackLib.GameState state = blackjack.getGameState(betId);
```

**Game Flow:**
1. Player places bet → VRF randomness requested (10 random words)
2. Initial deal: Player gets 2 cards face up, Dealer gets 1 up + 1 down
3. Check for blackjacks - if either has blackjack, resolve immediately
4. Player turn: Hit, Stand, Double Down, or Split
5. After player stands (or busts), dealer reveals hole card
6. Dealer draws according to rules (hits on 16 or less, hits soft 17)
7. Outcomes determined and payouts processed

**Payouts:**
| Outcome | Payout |
|---------|--------|
| Player Blackjack | 3:2 |
| Player Win | 1:1 |
| Dealer Bust | 1:1 |
| Push | Bet returned |
| Insurance (dealer BJ) | 2:1 |
| Double Down Win | 2:2 (double bet) |

**Rules:**
- Dealer hits on soft 17
- Blackjack pays 3:2
- Split up to 3 times (4 hands max)
- Double down on any two cards
- No re-splitting aces (planned)
- Insurance pays 2:1 when dealer has blackjack

**House Edge:** 0.5% (with basic strategy)

## Security

### Access Control

All contracts use OpenZeppelin's AccessControl for role-based permissions:

- `DEFAULT_ADMIN_ROLE`: Full administrative access
- `TREASURY_ROLE`: Can withdraw from treasury
- `GAME_ROLE`: Registered games can interact with treasury
- `RESOLVER_ROLE`: Can resolve bets
- `REQUESTER_ROLE`: Can request VRF randomness
- `UPGRADER_ROLE`: Can upgrade proxy implementations

### Safety Features

- **UUPS Upgradeable**: All core contracts are upgradeable with proper access control
- **ReentrancyGuard**: Protects against reentrancy in ETH transfers
- **Pausable**: Emergency pause functionality
- **Custom Errors**: Gas-efficient error handling
- **Storage Gaps**: Reserved storage slots for upgrade safety
- **VRF Security**: Only coordinator can fulfill randomness

### Bet Flow

1. Player calls `placeBet()` with ETH
2. Game validates bet amount (min/max)
3. Game calculates potential payout
4. Treasury checks if it can cover payout
5. Bet amount transferred to treasury
6. Potential payout reserved in treasury
7. VRFConsumer requests randomness from Chainlink VRF
8. VRF Coordinator returns random words via callback
9. VRFConsumer calls `resolveBet()` on the game
10. On resolution:
    - **Win**: Treasury pays out to player, releases remaining reserve
    - **Loss**: Treasury releases entire reserve (keeps bet)
    - **Cancel**: Treasury refunds bet, releases reserve

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# RPC URLs
ARBITRUM_RPC_URL=
BASE_RPC_URL=

# Private key for deployment
PRIVATE_KEY=

# Etherscan API keys for verification
ARBISCAN_API_KEY=
BASESCAN_API_KEY=

# Chainlink VRF V2.5
VRF_COORDINATOR=0x...              # Arbitrum: 0x41034678D6C633D8a95c75e1138A360a28bA15d1
VRF_KEY_HASH=0x...                 # Gas lane key hash
VRF_SUBSCRIPTION_ID=123            # Your VRF subscription ID
VRF_CALLBACK_GAS_LIMIT=500000      # Gas limit for callback

# Chainlink Automation
AUTOMATION_FORWARDER=0x...         # Automation forwarder address
```

### Chainlink VRF V2.5 Configuration

VRFConsumer is configured with:
- `keyHash`: Gas lane selector (determines gas price for fulfillment)
- `subscriptionId`: VRF subscription for payment
- `requestConfirmations`: Block confirmations (default: 3)
- `callbackGasLimit`: Max gas for callback (default: 500,000)
- `numWords`: Random values per request (default: 1)
- `nativePayment`: Use LINK (false) or native token (true)

### Foundry Configuration

Key settings in `foundry.toml`:

```toml
[profile.default]
solc = "0.8.24"
optimizer = true
optimizer_runs = 200
evm_version = "cancun"

[profile.default.fuzz]
runs = 1000

[profile.default.invariant]
runs = 256
depth = 100
```

## Testing Strategy

| Type | Coverage | Description |
|------|----------|-------------|
| Unit | 100% functions | Individual function testing |
| Fuzz | Amount handling | Property-based testing with random inputs |
| Integration | Contract interactions | Full system tests |
| Invariant | Balance consistency | State invariant verification |

### Test Results

```
╭-----------------------+--------+--------+---------╮
| Test Suite            | Passed | Failed | Skipped |
+===================================================+
| TreasuryTest          | 40     | 0      | 0       |
| CasinoTest            | 30     | 0      | 0       |
| GameRegistryTest      | 30     | 0      | 0       |
| VRFConsumerTest       | 18     | 0      | 0       |
| GameResolverTest      | 23     | 0      | 0       |
| SystemIntegrationTest | 18     | 0      | 0       |
| RouletteTest          | 43     | 0      | 0       |
| BlackjackTest         | 30     | 0      | 0       |
╰-----------------------+--------+--------+---------╯
Total: 232 tests passing
```

## Deployment

### Prerequisites

1. Copy `.env.example` to `.env` and configure:
   - `PRIVATE_KEY` - Deployer wallet private key
   - `ADMIN_ADDRESS` - Admin address for contracts
   - `VRF_SUBSCRIPTION_ID` - Chainlink VRF subscription ID
   - Network-specific VRF coordinator and key hash

2. Create a Chainlink VRF subscription at [vrf.chain.link](https://vrf.chain.link)

### Deploy to Testnet

```bash
# Deploy all contracts to Arbitrum Sepolia
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url arbitrum_sepolia \
  --broadcast \
  --verify

# Or deploy to Base Sepolia
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

### Deploy to Mainnet

```bash
# Deploy to Arbitrum One
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url arbitrum \
  --broadcast \
  --verify

# Deploy to Base
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url base \
  --broadcast \
  --verify
```

### Post-Deployment Steps

1. **Add VRF Consumer**: Go to [vrf.chain.link](https://vrf.chain.link) and add the deployed VRFConsumer address as a consumer to your subscription.

2. **Fund Treasury**: Send ETH to the Treasury contract for bankroll:
   ```bash
   cast send $TREASURY_ADDRESS --value 10ether --rpc-url arbitrum_sepolia
   ```

3. **Verify Deployment**: Run the verification script:
   ```bash
   forge script script/Verify.s.sol:VerifyDeployment --rpc-url arbitrum_sepolia
   ```

### Deployment Scripts

| Script | Description |
|--------|-------------|
| `DeployAll.s.sol` | Full system deployment (recommended) |
| `DeployCore.s.sol` | Deploy only core contracts |
| `DeployGames.s.sol` | Deploy games and register with existing core |
| `Verify.s.sol` | Verify deployment configuration |

### Frontend Integration

Export ABIs for frontend:

```bash
# Build contracts first
forge build

# Export ABIs
./script/export-abis.sh
```

ABIs are exported to `frontend/abis/`. The `frontend/contracts.ts` file provides:
- Network configuration
- Contract address management
- Game constants (bet types, payouts)
- Helper functions

## Chainlink Network Addresses

### Arbitrum One (Mainnet)
- VRF Coordinator: `0x41034678D6C633D8a95c75e1138A360a28bA15d1`
- Key Hash (500 gwei): `0x72d2b016bb5b62912afea355ebf33b91319f828738b111b723b78696b9847b63`

### Arbitrum Sepolia (Testnet)
- VRF Coordinator: `0x5CE8D5A2BC84beb22a398CCA51996F7930313D61`
- Key Hash: `0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be`

### Base Mainnet
- VRF Coordinator: `0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634`
- Key Hash: `0x0c4fc1d14b9680b5f7fb4efc2b36fded1ca63eb2a23e09a36b8be5fc9c13e0e3`

### Base Sepolia (Testnet)
- VRF Coordinator: `0x5C210eF41CD1a72de73bF76eC39637bB0dc89a52`
- Key Hash: `0x9e9e46732b32662b9adc6f3abdf6c5e926a666d174a4d6b8e39c4e4bea3abe9a`

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests: `forge test`
4. Submit a pull request

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) v5.x
- [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) v5.x
- [Forge Std](https://github.com/foundry-rs/forge-std)
