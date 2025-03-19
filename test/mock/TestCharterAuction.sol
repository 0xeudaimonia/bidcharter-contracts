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
    
}