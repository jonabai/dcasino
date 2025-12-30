#!/bin/bash
# Export ABIs for frontend integration

set -e

# Create output directory
mkdir -p frontend/abis

echo "Exporting ABIs..."

# Core contracts
jq '.abi' out/Casino.sol/Casino.json > frontend/abis/Casino.json
jq '.abi' out/Treasury.sol/Treasury.json > frontend/abis/Treasury.json
jq '.abi' out/GameRegistry.sol/GameRegistry.json > frontend/abis/GameRegistry.json
jq '.abi' out/VRFConsumer.sol/VRFConsumer.json > frontend/abis/VRFConsumer.json
jq '.abi' out/GameResolver.sol/GameResolver.json > frontend/abis/GameResolver.json

# Game contracts
jq '.abi' out/Roulette.sol/Roulette.json > frontend/abis/Roulette.json
jq '.abi' out/Blackjack.sol/Blackjack.json > frontend/abis/Blackjack.json

echo "ABIs exported to frontend/abis/"
echo ""
echo "Files created:"
ls -la frontend/abis/
