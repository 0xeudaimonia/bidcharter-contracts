// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// Adjust the import path according to your project structure.
import "src/CharterAuction.sol";
import "./mock/MockUSDT.sol";

/// @dev Test contract for CharterAuction using Foundry.
contract CharterAuctionTest is Test {
    CharterAuction public auction;
    MockUSDT public usdt;
    address public broker;
    uint256 public bidPrice;

    address bidder1 = address(0x1);
    address bidder2 = address(0x2);
    address bidder3 = address(0x3);

    // Set entry fee to 2 USDT (scaled by 1e18) and minimum funds for blind round to 10 USDT.
    uint256 entryFee = 2e18;
    uint256 minRaisedFunds = 10e18;

    function setUp() public {
        // Deploy the mock USDT token.
        usdt = new MockUSDT();
        // Mint tokens by setting balance manually (for testing only).
        usdt.balanceOf(bidder1); // for clarity, although not needed
        usdt.balanceOf(bidder2);
        usdt.balanceOf(bidder3);

        broker = address(0x4);
        // For testing purposes, manually set balances.
        // In practice, use a mint function or a pre-minted token.
        // NOTE: Using cheatcodes here to set storage directly.
        setBalance(bidder1, 100e18);
        setBalance(bidder2, 100e18);
        setBalance(bidder3, 100e18);
        setBalance(broker, 100e18);


        // Deploy the auction contract.
        auction = new CharterAuction(address(usdt), entryFee, minRaisedFunds, broker);

        // Approve auction contract to spend tokens from bidders.
        vm.prank(bidder1);
        usdt.approve(address(auction), 100e18);
        vm.prank(bidder2);
        usdt.approve(address(auction), 100e18);
        vm.prank(bidder3);
        usdt.approve(address(auction), 100e18);
    }

    /// @notice Cheatcode to set an account's balance in our MockERC20.
    function setBalance(address account, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(account, uint256(0))); // Simplified; in real tests, use proper method.
        vm.store(address(usdt), slot, bytes32(amount));
    }

    function testBlindBidEntry() public {
        // Bidder1 enters the blind round.
        vm.prank(bidder1);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(100e18)));
        auction.bidAtBlindRound(bidInfo);

        // Retrieve blind round info from the contract.
        // Because blindRound is public, the getter is auto-generated.
        address bidder = auction.getBlindBidder(0);
        assertEq(bidder, bidder1, "Bidder1 should be recorded");
        assertEq(auction.getBlindRoundBidders().length, 1, "There should be one bid info");
        assertEq(auction.getBlindRoundBidInfo(0, 0), bidInfo, "Bid info should match");
    }

    function testBidAtBlindRound() public {
        vm.startPrank(broker);
        usdt.approve(address(auction), 1000 * 10**18);
        
        bytes32 prevBidInfo = keccak256(abi.encodePacked(address(broker), bidPrice));
        auction.bidAtBlindRound(prevBidInfo);
        
        // Get the bidder info directly using the getter function
        address bidder = auction.getBlindBidder(0);
        bytes32 bidInfo = auction.getBlindRoundBidInfo(0, 0);
        
        assertEq(bidder, address(broker));
        assertEq(bidInfo, prevBidInfo);
        
        vm.stopPrank();
    }

    // Additional tests should be written to cover:
    // - Ending the blind round (endBlindRound) with proper bid price array.
    // - Testing geometricMean computation.
    // - Testing position bidding (bidPosition) and reward accrual.
    // - Testing auction ending (endAuction) and round transitions.
}
