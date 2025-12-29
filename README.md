# DCasino - Decentralized Casino dApp

A modular, upgradeable smart contract system for decentralized casino games on EVM-compatible blockchains. Built with Foundry and designed for Arbitrum/Base L2 deployment.

## Architecture

```
                    ┌─────────────────┐
                    │     Casino      │
                    │  (Admin Hub)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼────────┐ ┌───▼───┐ ┌────────▼────────┐
     │   GameRegistry  │ │       │ │    Treasury     │
     │ (Plugin System) │ │ Games │ │   (Bankroll)    │
     └────────┬────────┘ │       │ └────────┬────────┘
              │          └───┬───┘          │
              │              │              │
              └──────────────┼──────────────┘
                             │
                    ┌────────▼────────┐
                    │    BaseGame     │
                    │   (Abstract)    │
                    └─────────────────┘
```

### Core Contracts

| Contract | Description |
|----------|-------------|
| **Casino.sol** | Central admin hub - manages ecosystem pause, treasury/registry references, emergency functions |
| **Treasury.sol** | Bankroll management - deposits, withdrawals, bet reservations, payouts, fee collection |
| **GameRegistry.sol** | Plugin architecture - game registration, enable/disable, statistics tracking |
| **BaseGame.sol** | Abstract game template - common bet logic, treasury integration, randomness requests |

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
RESOLVER_ROLE ── Can resolve bets (for Chainlink Automation)
OPERATOR_ROLE ── Game operators (pause individual games, set bet limits)
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
│   │   └── IGame.sol
│   ├── abstracts/
│   │   └── BaseGame.sol            # Abstract base for games
│   ├── games/                      # Game implementations (Phase 3-4)
│   │   ├── Roulette.sol
│   │   └── Blackjack.sol
│   ├── chainlink/                  # Chainlink integration (Phase 2)
│   │   ├── VRFConsumer.sol
│   │   └── GameResolver.sol
│   └── libraries/
│       ├── Errors.sol              # Custom errors
│       ├── BetLib.sol              # Bet structures
│       └── PayoutLib.sol           # Payout calculations
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

### BaseGame

Games inherit from BaseGame for common functionality:

```solidity
contract MyGame is BaseGame {
    function initialize(address admin, ...) external initializer {
        __BaseGame_init(admin, "MyGame", casino, treasury, registry);
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

## Security

### Access Control

All contracts use OpenZeppelin's AccessControl for role-based permissions:

- `DEFAULT_ADMIN_ROLE`: Full administrative access
- `TREASURY_ROLE`: Can withdraw from treasury
- `GAME_ROLE`: Registered games can interact with treasury
- `UPGRADER_ROLE`: Can upgrade proxy implementations

### Safety Features

- **UUPS Upgradeable**: All core contracts are upgradeable with proper access control
- **ReentrancyGuard**: Protects against reentrancy in ETH transfers
- **Pausable**: Emergency pause functionality
- **Custom Errors**: Gas-efficient error handling
- **Storage Gaps**: Reserved storage slots for upgrade safety

### Bet Flow

1. Player calls `placeBet()` with ETH
2. Game validates bet amount (min/max)
3. Game calculates potential payout
4. Treasury checks if it can cover payout
5. Bet amount transferred to treasury
6. Potential payout reserved in treasury
7. Randomness requested (VRF)
8. On resolution:
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

# Chainlink VRF (Phase 2)
VRF_COORDINATOR=
VRF_KEY_HASH=
VRF_SUBSCRIPTION_ID=
```

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
| SystemIntegrationTest | 18     | 0      | 0       |
╰-----------------------+--------+--------+---------╯
Total: 118 tests passing
```

## Roadmap

### Phase 1 (Complete)
- [x] Project setup with Foundry
- [x] Libraries (Errors, BetLib, PayoutLib)
- [x] Interfaces (ICasino, ITreasury, IGameRegistry, IGame)
- [x] Treasury contract with tests
- [x] Casino contract with tests
- [x] GameRegistry contract with tests
- [x] BaseGame abstract contract
- [x] Integration tests

### Phase 2 (Planned)
- [ ] Chainlink VRF V2.5 integration
- [ ] Chainlink Automation for bet resolution
- [ ] VRFConsumer contract
- [ ] GameResolver contract

### Phase 3 (Planned)
- [ ] Roulette game implementation
- [ ] European roulette rules (single zero)
- [ ] All bet types (straight, split, street, etc.)

### Phase 4 (Planned)
- [ ] Blackjack game implementation
- [ ] Standard blackjack rules
- [ ] Split, double down, insurance

### Phase 5 (Planned)
- [ ] Deployment scripts for testnets
- [ ] Mainnet deployment (Arbitrum/Base)
- [ ] Frontend integration

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
- [Chainlink](https://github.com/smartcontractkit/chainlink) (Phase 2)
- [Forge Std](https://github.com/foundry-rs/forge-std)
