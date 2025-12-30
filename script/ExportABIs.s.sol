// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

/// @title ExportABIs - Export contract ABIs for frontend
/// @notice Run this after `forge build` to get ABI file paths
/// @dev ABIs are automatically generated in out/ directory
contract ExportABIs is Script {
    function run() external pure {
        console.log("");
        console.log("==============================================");
        console.log("       DCasino ABI Export Paths");
        console.log("==============================================");
        console.log("");
        console.log("After running `forge build`, ABIs are located at:");
        console.log("");
        console.log("Core Contracts:");
        console.log("  out/Casino.sol/Casino.json");
        console.log("  out/Treasury.sol/Treasury.json");
        console.log("  out/GameRegistry.sol/GameRegistry.json");
        console.log("  out/VRFConsumer.sol/VRFConsumer.json");
        console.log("  out/GameResolver.sol/GameResolver.json");
        console.log("");
        console.log("Game Contracts:");
        console.log("  out/Roulette.sol/Roulette.json");
        console.log("  out/Blackjack.sol/Blackjack.json");
        console.log("");
        console.log("Libraries:");
        console.log("  out/RouletteLib.sol/RouletteLib.json");
        console.log("  out/BlackjackLib.sol/BlackjackLib.json");
        console.log("  out/BetLib.sol/BetLib.json");
        console.log("");
        console.log("To extract just the ABI array, use jq:");
        console.log("  jq '.abi' out/Casino.sol/Casino.json > casino-abi.json");
        console.log("");
        console.log("Or use the provided export script:");
        console.log("  ./script/export-abis.sh");
        console.log("");
    }
}
