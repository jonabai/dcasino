// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Casino} from "../src/Casino.sol";
import {Treasury} from "../src/Treasury.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {VRFConsumer} from "../src/chainlink/VRFConsumer.sol";
import {GameResolver} from "../src/chainlink/GameResolver.sol";

/// @title DeployCore - Deploy core casino infrastructure
/// @notice Deploys Casino, Treasury, GameRegistry, VRFConsumer, and GameResolver
/// @dev All contracts are deployed behind UUPS proxies
contract DeployCore is Script {
    // Deployment configuration
    struct DeployConfig {
        address admin;
        address vrfCoordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bool nativePayment;
    }

    // Deployed contract addresses
    struct DeployedContracts {
        address casino;
        address treasury;
        address gameRegistry;
        address vrfConsumer;
        address gameResolver;
    }

    /// @notice Main deployment function
    function run() external returns (DeployedContracts memory deployed) {
        // Load configuration from environment
        DeployConfig memory config = _loadConfig();

        console.log("Deploying DCasino Core Contracts");
        console.log("================================");
        console.log("Admin:", config.admin);
        console.log("VRF Coordinator:", config.vrfCoordinator);

        vm.startBroadcast();

        // 1. Deploy Treasury
        deployed.treasury = _deployTreasury(config.admin);
        console.log("Treasury deployed at:", deployed.treasury);

        // 2. Deploy GameRegistry
        deployed.gameRegistry = _deployGameRegistry(config.admin, deployed.treasury);
        console.log("GameRegistry deployed at:", deployed.gameRegistry);

        // 3. Deploy Casino
        deployed.casino = _deployCasino(config.admin, deployed.treasury, deployed.gameRegistry);
        console.log("Casino deployed at:", deployed.casino);

        // 4. Deploy VRFConsumer
        deployed.vrfConsumer = _deployVRFConsumer(config, deployed.gameRegistry);
        console.log("VRFConsumer deployed at:", deployed.vrfConsumer);

        // 5. Deploy GameResolver
        deployed.gameResolver = _deployGameResolver(config.admin, deployed.gameRegistry);
        console.log("GameResolver deployed at:", deployed.gameResolver);

        // 6. Configure cross-references
        _configureContracts(deployed, config.admin);

        vm.stopBroadcast();

        console.log("");
        console.log("Deployment complete!");
        console.log("================================");

        return deployed;
    }

    /// @notice Load configuration from environment variables
    function _loadConfig() internal view returns (DeployConfig memory config) {
        config.admin = vm.envAddress("ADMIN_ADDRESS");
        config.vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
        config.keyHash = vm.envBytes32("VRF_KEY_HASH");
        config.subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        config.requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        config.callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500000)));
        config.numWords = uint32(vm.envOr("VRF_NUM_WORDS", uint256(1)));
        config.nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", false);
    }

    /// @notice Deploy Treasury behind a proxy
    function _deployTreasury(address admin) internal returns (address) {
        Treasury implementation = new Treasury();
        bytes memory initData = abi.encodeWithSelector(Treasury.initialize.selector, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    /// @notice Deploy GameRegistry behind a proxy
    function _deployGameRegistry(address admin, address treasury) internal returns (address) {
        GameRegistry implementation = new GameRegistry();
        bytes memory initData = abi.encodeWithSelector(GameRegistry.initialize.selector, admin, treasury);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    /// @notice Deploy Casino behind a proxy
    function _deployCasino(address admin, address treasury, address gameRegistry) internal returns (address) {
        Casino implementation = new Casino();
        bytes memory initData = abi.encodeWithSelector(Casino.initialize.selector, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Set treasury and game registry
        Casino(payable(address(proxy))).setTreasury(treasury);
        Casino(payable(address(proxy))).setGameRegistry(gameRegistry);

        return address(proxy);
    }

    /// @notice Deploy VRFConsumer behind a proxy
    function _deployVRFConsumer(DeployConfig memory config, address gameRegistry) internal returns (address) {
        VRFConsumer implementation = new VRFConsumer();
        bytes memory initData = abi.encodeWithSelector(
            VRFConsumer.initialize.selector,
            config.admin,
            config.vrfCoordinator,
            gameRegistry,
            config.keyHash,
            config.subscriptionId,
            config.requestConfirmations,
            config.callbackGasLimit,
            config.numWords,
            config.nativePayment
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    /// @notice Deploy GameResolver behind a proxy
    function _deployGameResolver(address admin, address gameRegistry) internal returns (address) {
        GameResolver implementation = new GameResolver();
        bytes memory initData = abi.encodeWithSelector(GameResolver.initialize.selector, admin, gameRegistry);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    /// @notice Configure cross-contract references and roles
    function _configureContracts(DeployedContracts memory deployed, address admin) internal {
        // Grant RESOLVER_ROLE to VRFConsumer on Treasury (so it can trigger payouts via games)
        // Note: Individual games will need GAME_ROLE granted when deployed

        console.log("");
        console.log("Configuration:");
        console.log("- Casino references set");
        console.log("- Admin:", admin);
        console.log("");
        console.log("Next steps:");
        console.log("1. Fund Treasury with ETH for bankroll");
        console.log("2. Deploy games using DeployGames script");
        console.log("3. Register games with GameRegistry");
        console.log("4. Add VRF subscription consumer");
    }
}
