// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus, VRFV2PlusClient} from "../../src/chainlink/interfaces/IVRFCoordinatorV2Plus.sol";

/// @title MockVRFCoordinator - Mock VRF Coordinator for testing
/// @notice Simulates Chainlink VRF V2.5 Coordinator behavior
contract MockVRFCoordinator is IVRFCoordinatorV2Plus {
    /// @notice Struct to store request info
    struct Request {
        address consumer;
        uint32 numWords;
        bool fulfilled;
    }

    /// @notice Counter for request IDs
    uint256 private _nextRequestId = 1;

    /// @notice Mapping of request ID to request info
    mapping(uint256 => Request) public requests;

    /// @notice Mapping of subscription ID to balance
    mapping(uint256 => uint96) public subscriptionBalances;

    /// @notice Mapping of subscription ID to owner
    mapping(uint256 => address) public subscriptionOwners;

    /// @notice Mapping of subscription ID to consumers
    mapping(uint256 => address[]) public subscriptionConsumers;

    /// @notice Next subscription ID
    uint256 private _nextSubId = 1;

    /// @notice Event for request tracking
    event RandomWordsRequested(
        uint256 indexed requestId,
        address indexed consumer,
        uint256 subId,
        uint32 numWords
    );

    /// @notice Event for fulfillment
    event RandomWordsFulfilled(uint256 indexed requestId, uint256[] randomWords);

    /// @inheritdoc IVRFCoordinatorV2Plus
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        override
        returns (uint256 requestId)
    {
        requestId = _nextRequestId++;

        requests[requestId] = Request({
            consumer: msg.sender,
            numWords: req.numWords,
            fulfilled: false
        });

        emit RandomWordsRequested(requestId, msg.sender, req.subId, req.numWords);
    }

    /// @notice Fulfill a random words request (for testing)
    /// @param requestId The request ID to fulfill
    /// @param randomWords The random words to return
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        Request storage request = requests[requestId];
        require(request.consumer != address(0), "Request not found");

        // Convert calldata to memory for internal call
        uint256[] memory words = new uint256[](randomWords.length);
        for (uint256 i = 0; i < randomWords.length; i++) {
            words[i] = randomWords[i];
        }

        _fulfillRandomWords(requestId, words);
    }

    /// @notice Fulfill with auto-generated random words (for testing)
    /// @param requestId The request ID to fulfill
    function fulfillRandomWordsWithRandomness(uint256 requestId) external {
        Request storage request = requests[requestId];
        require(request.consumer != address(0), "Request not found");

        uint256[] memory randomWords = new uint256[](request.numWords);
        for (uint32 i = 0; i < request.numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encodePacked(requestId, i, block.timestamp, block.prevrandao)));
        }

        _fulfillRandomWords(requestId, randomWords);
    }

    /// @notice Internal fulfill logic
    function _fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal {
        Request storage request = requests[requestId];
        require(!request.fulfilled, "Already fulfilled");

        request.fulfilled = true;

        // Call the consumer's callback
        (bool success,) = request.consumer.call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, randomWords)
        );
        require(success, "Callback failed");

        emit RandomWordsFulfilled(requestId, randomWords);
    }

    /// @inheritdoc IVRFCoordinatorV2Plus
    function getSubscription(uint256 subId)
        external
        view
        override
        returns (uint96 balance, uint96 reqCount, address owner, address[] memory consumers)
    {
        return (subscriptionBalances[subId], 0, subscriptionOwners[subId], subscriptionConsumers[subId]);
    }

    /// @inheritdoc IVRFCoordinatorV2Plus
    function addConsumer(uint256 subId, address consumer) external override {
        require(subscriptionOwners[subId] == msg.sender, "Not owner");
        subscriptionConsumers[subId].push(consumer);
    }

    /// @inheritdoc IVRFCoordinatorV2Plus
    function removeConsumer(uint256 subId, address consumer) external override {
        require(subscriptionOwners[subId] == msg.sender, "Not owner");
        address[] storage consumers = subscriptionConsumers[subId];
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == consumer) {
                consumers[i] = consumers[consumers.length - 1];
                consumers.pop();
                break;
            }
        }
    }

    /// @inheritdoc IVRFCoordinatorV2Plus
    function createSubscription() external override returns (uint256 subId) {
        subId = _nextSubId++;
        subscriptionOwners[subId] = msg.sender;
    }

    /// @inheritdoc IVRFCoordinatorV2Plus
    function cancelSubscription(uint256 subId, address to) external override {
        require(subscriptionOwners[subId] == msg.sender, "Not owner");
        uint96 balance = subscriptionBalances[subId];
        subscriptionBalances[subId] = 0;
        if (balance > 0) {
            payable(to).transfer(balance);
        }
    }

    /// @inheritdoc IVRFCoordinatorV2Plus
    function pendingRequestExists(uint256 /* subId */, address /* consumer */)
        external
        pure
        override
        returns (bool)
    {
        return false;
    }

    /// @notice Fund a subscription (for testing)
    /// @param subId The subscription ID
    function fundSubscription(uint256 subId) external payable {
        subscriptionBalances[subId] += uint96(msg.value);
    }

    /// @notice Check if a request exists
    /// @param requestId The request ID
    /// @return True if the request exists
    function requestExists(uint256 requestId) external view returns (bool) {
        return requests[requestId].consumer != address(0);
    }

    /// @notice Check if a request is fulfilled
    /// @param requestId The request ID
    /// @return True if fulfilled
    function isRequestFulfilled(uint256 requestId) external view returns (bool) {
        return requests[requestId].fulfilled;
    }

    /// @notice Allow receiving ETH
    receive() external payable {}
}
