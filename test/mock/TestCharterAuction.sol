// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/CharterAuction.sol"; // adjust the import path as needed

// Extend your contract to expose internal functions for testing.
contract TestCharterAuction is CharterAuction {
    constructor(
        address _usdt,
        uint256 _entryFee,
        uint256 _minRaisedFundsAtBlindRound,
        address _broker
    ) CharterAuction(_usdt, _entryFee, _minRaisedFundsAtBlindRound, _broker) {}

    // Public wrapper for the internal checkDoubleBlindBid function.
    function testCheckDoubleBlindBidWrapper(bytes32 bidInfo, address bidder)
        external
        view
        returns (bool)
    {
        return checkDoubleBlindBid(bidInfo, bidder);
    }

    // Helper function to set a bidder's blind bid info.
    function testSetBlindBidderInfo(address bidder, bytes32[] calldata bidInfos) external {
        uint256 index = searchBlindBidder(bidder);
        if (index < blindRound.bidders.length) {
            for (uint256 i = 0; i < bidInfos.length; i++) {
                blindRound.bidders[index].bidInfos.push(bidInfos[i]);
            }
        } else {
            blindRound.bidders.push(BlindBidderInfo({ bidder: bidder, bidInfos: bidInfos }));
        }
    }

    function testSearchBlindBidder(address bidder) external view returns (uint256) {
        return searchBlindBidder(bidder);
    }

    // Add this helper function for testing
    function testSortPrices(uint256[] memory prices) external pure returns (uint256[] memory) {
        return sortPrices(prices);
    }

    // Add this helper function for testing
    function testSetPosition(uint256 bidPrice, address[] memory rewarders) external {
        Position storage newPosition = rounds[currentRound].positions.push();
        newPosition.bidPrice = bidPrice;
        for (uint256 i = 0; i < rewarders.length; i++) {
            newPosition.rewarders.push(rewarders[i]);
        }
    }

    // Add this helper function for testing
    function testGeometricMean(uint256[] memory values) external pure returns (uint256) {
        return geometricMean(values);
    }

    // Add this helper function for testing
    function testTargetPrice() external view returns (uint256) {
        return getTargetPrice();
    }

    // Add these helper functions to CharterAuction.sol
    function testEndBlindRound() external {
        blindRound.ended = true;
    }

    function testSetRaisedFunds(uint256 amount) external {
        raisedFundAtBlindRound = amount;
    }

    // Add these helper functions to CharterAuction.sol
    function testCheckDoubleBid(uint256 _bidPrice, address _bidder) external view returns (bool) {
        return checkDoubleBid(_bidPrice, _bidder);
    }

    function testSetBidderInfo(address bidder, uint256[] memory bidPrices) external {
        BidderInfo storage newBidder = rounds[currentRound].bidders.push();
        newBidder.bidder = bidder;
        for (uint256 i = 0; i < bidPrices.length; i++) {
            newBidder.bidPrices.push(bidPrices[i]);
        }
    }

    // Add these helper functions to CharterAuction.sol
    function testSearchPosition(uint256 _bidPrice) external view returns (uint256) {
        return searchPosition(_bidPrice);
    }

    function testGetPositionsLength() external view returns (uint256) {
        return rounds[currentRound].positions.length;
    }

    // Add these helper functions to CharterAuction.sol
    function testSearchBidder(address _bidder) external view returns (uint256) {
        return searchBidder(_bidder);
    }

    function testGetBiddersLength() external view returns (uint256) {
        return rounds[currentRound].bidders.length;
    }

    // Add this helper to CharterAuction.sol
    function testGetTargetPrice() external view returns (uint256) {
        return getTargetPrice();
    }

    function testEndCurrentRound() external {
        rounds[currentRound].ended = true;
    }

    function testIsRoundEnded(uint256 roundIndex) external view returns (bool) {
        return rounds[roundIndex].ended;
    }
    
    function testGetPosition(uint256 index) external view returns (address[] memory rewarders, uint256 bidPrice) {
        Position storage position = rounds[currentRound].positions[index];
        return (position.rewarders, position.bidPrice);
    }

    function testTurnToNextRound() external {
        turnToNextRound();
    }

    function testGetBidderInfo(uint256 index) external view returns (address bidder, uint256[] memory prices) {
        BidderInfo storage info = rounds[currentRound].bidders[index];
        return (info.bidder, info.bidPrices);
    }

    // Add these helper functions to CharterAuction.sol
    function testSetRewards(address user, uint256 amount) external {
        rewards[user] = amount;
    }

    function testAddRewards(address user, uint256 amount) external {
        rewards[user] += amount;
    }
}