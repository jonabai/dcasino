// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {Casino} from "../src/Casino.sol";
import {Treasury} from "../src/Treasury.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {VRFConsumer} from "../src/chainlink/VRFConsumer.sol";
import {Roulette} from "../src/games/Roulette.sol";
import {Blackjack} from "../src/games/Blackjack.sol";

/// @title VerifyDeployment - Verify deployed contracts
/// @notice Checks that all contracts are properly configured after deployment
contract VerifyDeployment is Script {
    // Addresses loaded from env
    address casino;
    address treasury;
    address gameRegistry;
    address vrfConsumer;
    address roulette;
    address blackjack;

    uint256 errors;

    function run() external view {
        console.log("");
        console.log("==============================================");
        console.log("       DCasino Deployment Verification");
        console.log("==============================================");
        console.log("");

        // Load addresses
        address _casino = vm.envAddress("CASINO_ADDRESS");
        address _treasury = vm.envAddress("TREASURY_ADDRESS");
        address _gameRegistry = vm.envAddress("GAME_REGISTRY_ADDRESS");
        address _vrfConsumer = vm.envAddress("VRF_CONSUMER_ADDRESS");
        address _roulette = vm.envAddress("ROULETTE_ADDRESS");
        address _blackjack = vm.envAddress("BLACKJACK_ADDRESS");

        uint256 _errors = 0;

        // Check Casino
        _errors = _verifyCasino(_casino, _treasury, _gameRegistry, _errors);

        // Check Treasury
        _errors = _verifyTreasury(_treasury, _roulette, _blackjack, _errors);

        // Check GameRegistry
        _errors = _verifyRegistry(_gameRegistry, _roulette, _blackjack, _errors);

        // Check VRFConsumer
        _errors = _verifyVRF(_vrfConsumer, _roulette, _blackjack, _errors);

        // Check Games
        _errors = _verifyGames(_roulette, _blackjack, _vrfConsumer, _errors);

        // Summary
        console.log("");
        console.log("==============================================");
        if (_errors == 0) {
            console.log("  All checks passed!");
        } else {
            console.log("  ERRORS FOUND:", _errors);
        }
        console.log("==============================================");
    }

    function _verifyCasino(
        address _casino,
        address _treasury,
        address _gameRegistry,
        uint256 _errors
    ) internal view returns (uint256) {
        console.log("Checking Casino...");
        Casino c = Casino(payable(_casino));

        if (c.treasury() != _treasury) {
            console.log("  ERROR: Treasury mismatch");
            _errors++;
        } else {
            console.log("  Treasury: OK");
        }

        if (c.gameRegistry() != _gameRegistry) {
            console.log("  ERROR: GameRegistry mismatch");
            _errors++;
        } else {
            console.log("  GameRegistry: OK");
        }

        return _errors;
    }

    function _verifyTreasury(
        address _treasury,
        address _roulette,
        address _blackjack,
        uint256 _errors
    ) internal view returns (uint256) {
        console.log("");
        console.log("Checking Treasury...");
        Treasury t = Treasury(payable(_treasury));
        bytes32 gameRole = t.GAME_ROLE();

        if (!t.hasRole(gameRole, _roulette)) {
            console.log("  ERROR: Roulette missing GAME_ROLE");
            _errors++;
        } else {
            console.log("  Roulette GAME_ROLE: OK");
        }

        if (!t.hasRole(gameRole, _blackjack)) {
            console.log("  ERROR: Blackjack missing GAME_ROLE");
            _errors++;
        } else {
            console.log("  Blackjack GAME_ROLE: OK");
        }

        console.log("  Balance:", t.getBalance());

        return _errors;
    }

    function _verifyRegistry(
        address _gameRegistry,
        address _roulette,
        address _blackjack,
        uint256 _errors
    ) internal view returns (uint256) {
        console.log("");
        console.log("Checking GameRegistry...");
        GameRegistry r = GameRegistry(_gameRegistry);

        if (!r.isActiveGame(_roulette)) {
            console.log("  ERROR: Roulette not active");
            _errors++;
        } else {
            console.log("  Roulette active: OK");
        }

        if (!r.isActiveGame(_blackjack)) {
            console.log("  ERROR: Blackjack not active");
            _errors++;
        } else {
            console.log("  Blackjack active: OK");
        }

        return _errors;
    }

    function _verifyVRF(
        address _vrfConsumer,
        address _roulette,
        address _blackjack,
        uint256 _errors
    ) internal view returns (uint256) {
        console.log("");
        console.log("Checking VRFConsumer...");
        VRFConsumer v = VRFConsumer(_vrfConsumer);
        bytes32 requesterRole = v.REQUESTER_ROLE();

        if (!v.hasRole(requesterRole, _roulette)) {
            console.log("  ERROR: Roulette missing REQUESTER_ROLE");
            _errors++;
        } else {
            console.log("  Roulette REQUESTER_ROLE: OK");
        }

        if (!v.hasRole(requesterRole, _blackjack)) {
            console.log("  ERROR: Blackjack missing REQUESTER_ROLE");
            _errors++;
        } else {
            console.log("  Blackjack REQUESTER_ROLE: OK");
        }

        return _errors;
    }

    function _verifyGames(
        address _roulette,
        address _blackjack,
        address _vrfConsumer,
        uint256 _errors
    ) internal view returns (uint256) {
        console.log("");
        console.log("Checking Games...");

        Roulette r = Roulette(_roulette);
        bytes32 resolverRole = r.RESOLVER_ROLE();

        if (!r.hasRole(resolverRole, _vrfConsumer)) {
            console.log("  ERROR: Roulette missing VRF RESOLVER_ROLE");
            _errors++;
        } else {
            console.log("  Roulette RESOLVER_ROLE: OK");
        }

        Blackjack b = Blackjack(_blackjack);
        if (!b.hasRole(resolverRole, _vrfConsumer)) {
            console.log("  ERROR: Blackjack missing VRF RESOLVER_ROLE");
            _errors++;
        } else {
            console.log("  Blackjack RESOLVER_ROLE: OK");
        }

        console.log("  Roulette house edge:", r.getHouseEdge(), "bp");
        console.log("  Blackjack house edge:", b.getHouseEdge(), "bp");

        return _errors;
    }
}
