// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Casino} from "../src/Casino.sol";
import {Treasury} from "../src/Treasury.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {VRFConsumer} from "../src/chainlink/VRFConsumer.sol";
import {Roulette} from "../src/games/Roulette.sol";
import {Blackjack} from "../src/games/Blackjack.sol";

/// @title DeployGames - Deploy game contracts
/// @notice Deploys Roulette and Blackjack games and registers them
/// @dev Requires core contracts to be deployed first
contract DeployGames is Script {
    // Core contract addresses (set from environment or previous deployment)
    struct CoreContracts {
        address casino;
        address treasury;
        address gameRegistry;
        address vrfConsumer;
    }

    // Deployed game addresses
    struct DeployedGames {
        address roulette;
        address blackjack;
    }

    /// @notice Main deployment function
    function run() external returns (DeployedGames memory games) {
        // Load core contract addresses
        CoreContracts memory core = _loadCoreContracts();
        address admin = vm.envAddress("ADMIN_ADDRESS");

        console.log("Deploying DCasino Games");
        console.log("=======================");
        console.log("Admin:", admin);
        console.log("Casino:", core.casino);
        console.log("Treasury:", core.treasury);
        console.log("GameRegistry:", core.gameRegistry);
        console.log("VRFConsumer:", core.vrfConsumer);

        vm.startBroadcast();

        // 1. Deploy Roulette
        games.roulette = _deployRoulette(admin, core);
        console.log("Roulette deployed at:", games.roulette);

        // 2. Deploy Blackjack
        games.blackjack = _deployBlackjack(admin, core);
        console.log("Blackjack deployed at:", games.blackjack);

        // 3. Register games
        _registerGames(games, core);

        // 4. Grant necessary roles
        _grantRoles(games, core);

        vm.stopBroadcast();

        console.log("");
        console.log("Games deployment complete!");
        console.log("==========================");

        return games;
    }

    /// @notice Load core contract addresses from environment
    function _loadCoreContracts() internal view returns (CoreContracts memory core) {
        core.casino = vm.envAddress("CASINO_ADDRESS");
        core.treasury = vm.envAddress("TREASURY_ADDRESS");
        core.gameRegistry = vm.envAddress("GAME_REGISTRY_ADDRESS");
        core.vrfConsumer = vm.envAddress("VRF_CONSUMER_ADDRESS");
    }

    /// @notice Deploy Roulette behind a proxy
    function _deployRoulette(address admin, CoreContracts memory core) internal returns (address) {
        Roulette implementation = new Roulette();
        bytes memory initData = abi.encodeWithSelector(
            Roulette.initialize.selector,
            admin,
            core.casino,
            core.treasury,
            core.gameRegistry,
            core.vrfConsumer
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    /// @notice Deploy Blackjack behind a proxy
    function _deployBlackjack(address admin, CoreContracts memory core) internal returns (address) {
        Blackjack implementation = new Blackjack();
        bytes memory initData = abi.encodeWithSelector(
            Blackjack.initialize.selector,
            admin,
            core.casino,
            core.treasury,
            core.gameRegistry,
            core.vrfConsumer
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    /// @notice Register games with the GameRegistry
    function _registerGames(DeployedGames memory games, CoreContracts memory core) internal {
        GameRegistry registry = GameRegistry(core.gameRegistry);

        // Register Roulette
        bytes32 rouletteId = registry.registerGame(games.roulette, "Roulette");
        console.log("Roulette registered with ID:");
        console.logBytes32(rouletteId);

        // Register Blackjack
        bytes32 blackjackId = registry.registerGame(games.blackjack, "Blackjack");
        console.log("Blackjack registered with ID:");
        console.logBytes32(blackjackId);
    }

    /// @notice Grant necessary roles to games
    function _grantRoles(DeployedGames memory games, CoreContracts memory core) internal {
        Treasury treasury = Treasury(payable(core.treasury));
        VRFConsumer vrfConsumer = VRFConsumer(core.vrfConsumer);

        // Grant GAME_ROLE to games on Treasury
        bytes32 gameRole = treasury.GAME_ROLE();
        treasury.grantRole(gameRole, games.roulette);
        treasury.grantRole(gameRole, games.blackjack);
        console.log("GAME_ROLE granted to Roulette and Blackjack on Treasury");

        // Grant REQUESTER_ROLE to games on VRFConsumer
        bytes32 requesterRole = vrfConsumer.REQUESTER_ROLE();
        vrfConsumer.grantRole(requesterRole, games.roulette);
        vrfConsumer.grantRole(requesterRole, games.blackjack);
        console.log("REQUESTER_ROLE granted to Roulette and Blackjack on VRFConsumer");

        // Grant RESOLVER_ROLE to VRFConsumer on games
        bytes32 resolverRole = Roulette(games.roulette).RESOLVER_ROLE();
        Roulette(games.roulette).grantRole(resolverRole, core.vrfConsumer);
        Blackjack(games.blackjack).grantRole(resolverRole, core.vrfConsumer);
        console.log("RESOLVER_ROLE granted to VRFConsumer on games");
    }
}

/// @title DeployRoulette - Deploy only Roulette
contract DeployRoulette is Script {
    function run() external returns (address roulette) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address casino = vm.envAddress("CASINO_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address gameRegistry = vm.envAddress("GAME_REGISTRY_ADDRESS");
        address vrfConsumer = vm.envAddress("VRF_CONSUMER_ADDRESS");

        vm.startBroadcast();

        Roulette implementation = new Roulette();
        bytes memory initData = abi.encodeWithSelector(
            Roulette.initialize.selector,
            admin,
            casino,
            treasury,
            gameRegistry,
            vrfConsumer
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        roulette = address(proxy);

        console.log("Roulette deployed at:", roulette);

        vm.stopBroadcast();

        return roulette;
    }
}

/// @title DeployBlackjack - Deploy only Blackjack
contract DeployBlackjack is Script {
    function run() external returns (address blackjack) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address casino = vm.envAddress("CASINO_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address gameRegistry = vm.envAddress("GAME_REGISTRY_ADDRESS");
        address vrfConsumer = vm.envAddress("VRF_CONSUMER_ADDRESS");

        vm.startBroadcast();

        Blackjack implementation = new Blackjack();
        bytes memory initData = abi.encodeWithSelector(
            Blackjack.initialize.selector,
            admin,
            casino,
            treasury,
            gameRegistry,
            vrfConsumer
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        blackjack = address(proxy);

        console.log("Blackjack deployed at:", blackjack);

        vm.stopBroadcast();

        return blackjack;
    }
}
