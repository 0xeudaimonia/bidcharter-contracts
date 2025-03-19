// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// Adjust the import path according to your project structure.
import "./mock/TestCharterAuction.sol";
import "./mock/MockUSDT.sol";

/// @dev Test contract for CharterAuction using Foundry.
contract CharterAuctionTest is Test {
    TestCharterAuction auction;
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
        auction = new TestCharterAuction(address(usdt), entryFee, minRaisedFunds, broker);

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

    /// @notice Test the bidAtBlindRound function.
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

    /// @notice Test the double blind bid detection function.
    function testDoubleBlindBidDetection() public {
        // Create a bid info hash for bidder1.
        bytes32 bidInfo1 = keccak256(abi.encodePacked(bidder1, uint256(100e18)));
        // Set bidder1's blind bid info using our helper.
        bytes32[] memory infos = new bytes32[](1);
        infos[0] = bidInfo1;
        vm.prank(bidder1);
        auction.bidAtBlindRound(bidInfo1);

        // Test that the same bid info is detected as a duplicate.
        bool result = auction.testCheckDoubleBlindBidWrapper(bidInfo1, bidder1);
        assertTrue(result, "Should detect a double blind bid with identical bid info");

        // Create a different bid info.
        bytes32 bidInfo2 = keccak256(abi.encodePacked(bidder1, uint256(200e18)));
        result = auction.testCheckDoubleBlindBidWrapper(bidInfo2, bidder1);
        assertFalse(result, "Should not detect a duplicate when bid info is different");
    }

    function testSearchBlindBidderFound() public {
        // Set up blind round with two bidders.
        // Add bidder1 with some dummy bid infos.
        bytes32[] memory infos1 = new bytes32[](1);
        infos1[0] = keccak256(abi.encodePacked(bidder1, uint256(100e18)));
        vm.prank(bidder1);
        auction.bidAtBlindRound(infos1[0]);

        // Add bidder2 with some dummy bid infos.
        bytes32[] memory infos2 = new bytes32[](1);
        infos2[0] = keccak256(abi.encodePacked(bidder2, uint256(200e18)));
        vm.prank(bidder2);
        auction.bidAtBlindRound(infos2[0]);

        // Test that searchBlindBidder returns the correct index.
        // bidder1 is at index 0, bidder2 at index 1.
        uint256 index1 = auction.testSearchBlindBidder(bidder1);
        uint256 index2 = auction.testSearchBlindBidder(bidder2);

        assertEq(index1, 0, "Bidder1 should be at index 0");
        assertEq(index2, 1, "Bidder2 should be at index 1");
    }

    function testSearchBlindBidderNotFound() public view {
        uint256 index = auction.testSearchBlindBidder(address(0));
        assertEq(index, auction.getBlindRoundBidders().length, "When no bidders exist, index returned should be the length of the array");
    }

    function testSortPricesBasicOrder() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 100;
        prices[1] = 300;
        prices[2] = 200;
        prices[3] = 500;
        prices[4] = 400;

        uint256[] memory sorted = auction.testSortPrices(prices);
        assertEq(sorted[0], 500);
        assertEq(sorted[1], 400);
        assertEq(sorted[2], 300);
    }

    function testSortPricesWithDuplicates() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 300;
        prices[1] = 300;
        prices[2] = 500;
        prices[3] = 500;
        prices[4] = 400;

        uint256[] memory sorted = auction.testSortPrices(prices);
        assertEq(sorted[0], 500);
        assertEq(sorted[1], 500);
        assertEq(sorted[2], 400);
    }

    function testSortPricesSmallArray() public view {
        uint256[] memory prices = new uint256[](2);
        prices[0] = 100;
        prices[1] = 200;

        uint256[] memory sorted = auction.testSortPrices(prices);
        assertEq(sorted[0], 200);
        assertEq(sorted[1], 100);
        assertEq(sorted.length, 2);
    }

    function testSortPricesEmptyArray() public view {
        uint256[] memory prices = new uint256[](0);
        uint256[] memory sorted = auction.testSortPrices(prices);
        assertEq(sorted.length, 0);
    }

    function testSortPricesAlreadySorted() public view {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 500;
        prices[1] = 400;
        prices[2] = 300;
        prices[3] = 200;
        prices[4] = 100;

        uint256[] memory sorted = auction.testSortPrices(prices);
        assertEq(sorted[0], 500);
        assertEq(sorted[1], 400);
        assertEq(sorted[2], 300);
    }

    function testSortPricesLargeNumbers() public view {
        uint256[] memory prices = new uint256[](4);
        prices[0] = type(uint256).max - 2;
        prices[1] = type(uint256).max;
        prices[2] = type(uint256).max - 1;
        prices[3] = type(uint256).max - 3;

        uint256[] memory sorted = auction.testSortPrices(prices);
        assertEq(sorted[0], type(uint256).max);
        assertEq(sorted[1], type(uint256).max - 1);
        assertEq(sorted[2], type(uint256).max - 2);
    }

    function testGeometricMean() public view {
        uint256[] memory values = new uint256[](3);
        values[0] = 2e18;
        values[1] = 3e18;
        values[2] = 6e18;

        uint256 result = auction.testGeometricMean(values);
        assertApproxEqAbs(result, 3302e15, 1e15);
    }

    function testGeometricMeanSameValues() public view {
        uint256[] memory values = new uint256[](3);
        values[0] = 2e18;
        values[1] = 2e18;
        values[2] = 2e18;

        uint256 result = auction.testGeometricMean(values);
        assertApproxEqAbs(result, 2e18, 1e15);
    }

    function testGeometricMeanSingleValue() public view {
        uint256[] memory values = new uint256[](1);
        values[0] = 2e18;

        uint256 result = auction.testGeometricMean(values);
        assertApproxEqAbs(result, 2e18, 1e15);
    }

    function testGeometricMeanSmallNumbers() public view {
        uint256[] memory values = new uint256[](3);
        values[0] = 2e18;
        values[1] = 3e18;
        values[2] = 4e18;

        uint256 result = auction.testGeometricMean(values);
        assertApproxEqAbs(result, 2.8845e18, 1e15);
    }

    function testGeometricMeanManyValues() public view {
        uint256[] memory values = new uint256[](5);
        values[0] = 1e18;
        values[1] = 2e18;
        values[2] = 3e18;
        values[3] = 4e18;
        values[4] = 5e18;

        uint256 result = auction.testGeometricMean(values);
        assertApproxEqAbs(result, 2605e15, 1e15);
    }

    function testGeometricMeanPrecision() public view {
        uint256[] memory values = new uint256[](2);
        values[0] = 2e18;
        values[1] = 8e18;

        uint256 result = auction.testGeometricMean(values);
        assertApproxEqAbs(result, 4e18, 1e15);
    }

    function testEndAuction() public {
        // Setup initial conditions
        vm.startPrank(broker);
        
        address[] memory rewarders = new address[](1);
        
        // Position 1: price 100
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        
        // Position 2: price 150 (closest to target)
        rewarders[0] = address(0x2);
        auction.testSetPosition(150e18, rewarders);
        
        // Position 3: price 200
        rewarders[0] = address(0x3);
        auction.testSetPosition(200e18, rewarders);

        // End the auction
        auction.endAuction();

        // Assert the winner is the bidder with price closest to target
        assertEq(auction.winner(), address(0x2));
        
        vm.stopPrank();
    }

    function testEndAuctionWithTooManyPositions() public {
        vm.startPrank(broker);
        
        // Create more than MIN_POSITIONS positions
        for (uint256 i = 0; i < 4; i++) {
            address[] memory rewarders = new address[](1);
            rewarders[0] = address(uint160(i + 1));
            auction.testSetPosition(uint256(100e18 + i * 50e18), rewarders);
        }

        // Expect revert when trying to end auction with too many positions
        vm.expectRevert(CharterAuction.InvalidNumberOfPositions.selector);
        auction.endAuction();
        
        vm.stopPrank();
    }

    function testEndAuctionWithExactTargetPrice() public {
        vm.startPrank(broker);
        
        // Create positions where one matches the target exactly
        address[] memory rewarders = new address[](1);
        
        // Position 1: price 100
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        
        // Position 2: price 150 (will be target)
        rewarders[0] = address(0x2);
        auction.testSetPosition(150e18, rewarders);
        
        // Position 3: price 200
        rewarders[0] = address(0x3);
        auction.testSetPosition(200e18, rewarders);

        auction.endAuction();

        // Assert the winner is the bidder with exact target price
        assertEq(auction.winner(), address(0x2));
        
        vm.stopPrank();
    }

    function testEndAuctionWithEqualDeltas() public {
        vm.startPrank(broker);
        
        // Create positions with equal deltas from target
        address[] memory rewarders = new address[](1);
        
        // Position 1: price 125 (-25 from target)
        rewarders[0] = address(0x1);
        auction.testSetPosition(125e18, rewarders);
        
        // Position 2: price 150 (target)
        rewarders[0] = address(0x2);
        auction.testSetPosition(150e18, rewarders);
        
        // Position 3: price 175 (+25 from target)
        rewarders[0] = address(0x3);
        auction.testSetPosition(175e18, rewarders);

        auction.endAuction();

        // Assert the winner is the first position with minimum delta
        assertEq(auction.winner(), address(0x1));
        
        vm.stopPrank();
    }
}
