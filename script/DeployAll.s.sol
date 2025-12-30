// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Casino} from "../src/Casino.sol";
import {Treasury} from "../src/Treasury.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {VRFConsumer} from "../src/chainlink/VRFConsumer.sol";
import {GameResolver} from "../src/chainlink/GameResolver.sol";
import {Roulette} from "../src/games/Roulette.sol";
import {Blackjack} from "../src/games/Blackjack.sol";

/// @title DeployAll - Full system deployment
/// @notice Deploys all contracts in a single transaction for testnet/mainnet
contract DeployAll is Script {
    // Deployed proxy addresses
    address public casino;
    address public treasury;
    address public gameRegistry;
    address public vrfConsumer;
    address public gameResolver;
    address public roulette;
    address public blackjack;

    function run() external {
        // Load config
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");

        console.log("");
        console.log("==============================================");
        console.log("       DCasino Full System Deployment");
        console.log("==============================================");
        console.log("");
        console.log("Admin:", admin);
        console.log("VRF Coordinator:", vrfCoordinator);
        console.log("");

        vm.startBroadcast();

        // Deploy core contracts
        _deployCore(admin, vrfCoordinator, keyHash, subscriptionId);

        // Deploy games
        _deployGames(admin);

        // Configure system
        _configure();

        vm.stopBroadcast();

        // Output summary
        _printSummary();
    }

    function _deployCore(
        address admin,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subscriptionId
    ) internal {
        console.log("Deploying core contracts...");

        // Treasury
        Treasury treasuryImpl = new Treasury();
        treasury = address(
            new ERC1967Proxy(address(treasuryImpl), abi.encodeWithSelector(Treasury.initialize.selector, admin))
        );
        console.log("  Treasury:", treasury);

        // GameRegistry
        GameRegistry registryImpl = new GameRegistry();
        gameRegistry = address(
            new ERC1967Proxy(
                address(registryImpl), abi.encodeWithSelector(GameRegistry.initialize.selector, admin, treasury)
            )
        );
        console.log("  GameRegistry:", gameRegistry);

        // Casino
        Casino casinoImpl = new Casino();
        casino = address(
            new ERC1967Proxy(address(casinoImpl), abi.encodeWithSelector(Casino.initialize.selector, admin))
        );
        console.log("  Casino:", casino);

        // VRFConsumer
        uint16 confirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        uint32 gasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500000)));
        uint32 numWords = uint32(vm.envOr("VRF_NUM_WORDS", uint256(1)));
        bool nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", false);

        VRFConsumer vrfImpl = new VRFConsumer();
        vrfConsumer = address(
            new ERC1967Proxy(
                address(vrfImpl),
                abi.encodeWithSelector(
                    VRFConsumer.initialize.selector,
                    admin,
                    vrfCoordinator,
                    gameRegistry,
                    keyHash,
                    subscriptionId,
                    confirmations,
                    gasLimit,
                    numWords,
                    nativePayment
                )
            )
        );
        console.log("  VRFConsumer:", vrfConsumer);

        // GameResolver
        GameResolver resolverImpl = new GameResolver();
        gameResolver = address(
            new ERC1967Proxy(
                address(resolverImpl), abi.encodeWithSelector(GameResolver.initialize.selector, admin, gameRegistry)
            )
        );
        console.log("  GameResolver:", gameResolver);
    }

    function _deployGames(address admin) internal {
        console.log("");
        console.log("Deploying games...");

        // Roulette
        Roulette rouletteImpl = new Roulette();
        roulette = address(
            new ERC1967Proxy(
                address(rouletteImpl),
                abi.encodeWithSelector(Roulette.initialize.selector, admin, casino, treasury, gameRegistry, vrfConsumer)
            )
        );
        console.log("  Roulette:", roulette);

        // Blackjack
        Blackjack blackjackImpl = new Blackjack();
        blackjack = address(
            new ERC1967Proxy(
                address(blackjackImpl),
                abi.encodeWithSelector(
                    Blackjack.initialize.selector, admin, casino, treasury, gameRegistry, vrfConsumer
                )
            )
        );
        console.log("  Blackjack:", blackjack);
    }

    function _configure() internal {
        console.log("");
        console.log("Configuring system...");

        // Set Casino references
        Casino(payable(casino)).setTreasury(treasury);
        Casino(payable(casino)).setGameRegistry(gameRegistry);
        console.log("  Casino references set");

        // Register games
        GameRegistry(gameRegistry).registerGame(roulette, "Roulette");
        GameRegistry(gameRegistry).registerGame(blackjack, "Blackjack");
        console.log("  Games registered");

        // Grant GAME_ROLE on Treasury
        bytes32 gameRole = Treasury(payable(treasury)).GAME_ROLE();
        Treasury(payable(treasury)).grantRole(gameRole, roulette);
        Treasury(payable(treasury)).grantRole(gameRole, blackjack);
        console.log("  GAME_ROLE granted");

        // Grant REQUESTER_ROLE on VRFConsumer
        bytes32 requesterRole = VRFConsumer(vrfConsumer).REQUESTER_ROLE();
        VRFConsumer(vrfConsumer).grantRole(requesterRole, roulette);
        VRFConsumer(vrfConsumer).grantRole(requesterRole, blackjack);
        console.log("  REQUESTER_ROLE granted");

        // Grant RESOLVER_ROLE on games
        bytes32 resolverRole = Roulette(roulette).RESOLVER_ROLE();
        Roulette(roulette).grantRole(resolverRole, vrfConsumer);
        Blackjack(blackjack).grantRole(resolverRole, vrfConsumer);
        console.log("  RESOLVER_ROLE granted");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("==============================================");
        console.log("            Deployment Complete!");
        console.log("==============================================");
        console.log("");
        console.log("Update your .env with these addresses:");
        console.log("");
        console.log("CASINO_ADDRESS=");
        console.log(casino);
        console.log("TREASURY_ADDRESS=");
        console.log(treasury);
        console.log("GAME_REGISTRY_ADDRESS=");
        console.log(gameRegistry);
        console.log("VRF_CONSUMER_ADDRESS=");
        console.log(vrfConsumer);
        console.log("GAME_RESOLVER_ADDRESS=");
        console.log(gameResolver);
        console.log("ROULETTE_ADDRESS=");
        console.log(roulette);
        console.log("BLACKJACK_ADDRESS=");
        console.log(blackjack);
        console.log("");
        console.log("Next steps:");
        console.log("1. Add VRFConsumer as consumer to VRF subscription");
        console.log("2. Fund Treasury with ETH for bankroll");
        console.log("3. Verify contracts on block explorer");
        console.log("");
    }
}
