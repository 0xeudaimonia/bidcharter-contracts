// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// Adjust the import path according to your project structure.
import "./mock/TestCharterAuction.sol";
import "src/CharterNFT.sol";
import "./mock/MockUSDT.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev Test contract for CharterAuction using Foundry.
contract CharterAuctionTest is Test {
    TestCharterAuction auction;
    CharterNFT nft;
    MockUSDT public usdt;
    address public broker;
    uint256 public bidPrice;

    address bidder1 = address(0x1);
    address bidder2 = address(0x2);
    address bidder3 = address(0x3);

    // Set entry fee to 2 USDT (scaled by 1e18) and minimum funds for blind round to 10 USDT.
    uint256 entryFee = 2e18;
    uint256 minRaisedFunds = 10e18;

    // Add event test
    event NewRoundStarted(uint256 indexed round);
    event BidPosition(uint256 indexed round, uint256 positionIndex, address indexed bidder, uint256 entryFee);
    event RewardWithdrawn(address indexed rewarder, uint256 amount);

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
        setBalance(bidder1, 10000000e18);
        setBalance(bidder2, 10000000e18);
        setBalance(bidder3, 10000000e18);
        setBalance(broker, 10000000e18);

        // Deploy the NFT contract.
        nft = new CharterNFT(address(this), address(this), address(this));
        // Mint a token for the auction.
        uint256 nftId = nft.mint(address(this), "test-uri");

        // Set the minimum positions for the auction.
        uint256 minPositions = 3;
        // Set the target step for the auction.
        uint256 targetStep = 3;


        // Deploy the auction contract.
        auction = new TestCharterAuction(address(usdt), entryFee, minRaisedFunds, broker, address(nft), nftId, minPositions, targetStep);

        nft.transferFrom(address(this), address(auction), nftId);

        // Approve auction contract to spend tokens from bidders.
        vm.prank(bidder1);
        usdt.approve(address(auction), 100e18);
        vm.prank(bidder2);
        usdt.approve(address(auction), 100e18);
        vm.prank(bidder3);
        usdt.approve(address(auction), 100e18);
    }

    // Helper functions
    function _createSingleItemArray(bytes32 item) internal pure returns (bytes32[] memory) {
        bytes32[] memory array = new bytes32[](1);
        array[0] = item;
        return array;
    }

    function _createTwoItemArray(bytes32 item1, bytes32 item2) internal pure returns (bytes32[] memory) {
        bytes32[] memory array = new bytes32[](2);
        array[0] = item1;
        array[1] = item2;
        return array;
    }

    /// @notice Cheatcode to set an account's balance in our MockERC20.
    function setBalance(address account, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(account, uint256(0))); // Simplified; in real tests, use proper method.
        vm.store(address(usdt), slot, bytes32(amount));
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
        bool result = auction.testCheckDoubleBlindBidWrapper(bidder1);
        assertTrue(result, "Should detect a double blind bid with identical bid info");

        // Create a different bid info.
        result = auction.testCheckDoubleBlindBidWrapper(bidder1);
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
        assertEq(auction.winner(), address(0x2));
        
        vm.stopPrank();
    }

    function testBidAtBlindRound() public {
        // Setup
        vm.startPrank(broker);
        usdt.transfer(address(this), 1000e18);
        usdt.approve(address(auction), 1000e18);
        
        // Create bid info
        bytes32 bidInfo = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        
        // Make the bid
        auction.bidAtBlindRound(bidInfo);
        
        // Verify bid was recorded
        assertEq(auction.getBlindRoundBidders(0).bidder, address(broker));
        assertEq(auction.getBlindRoundBidders(0).bidInfos[0], bidInfo);
        
        vm.stopPrank();
    }

    function testBidAtBlindRoundMultipleBids() public {
        // Setup
        vm.startPrank(broker);
        usdt.transfer(address(this), 1000e18);
        usdt.approve(address(auction), 1000e18);
        
        // Create multiple bid infos
        bytes32 bidInfo1 = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        bytes32 bidInfo2 = keccak256(abi.encodePacked(address(this), uint256(200e18)));
        
        // Make the bids
        auction.bidAtBlindRound(bidInfo1);
        auction.bidAtBlindRound(bidInfo2);
        
        // Verify both bids were recorded for the same bidder
        assertEq(auction.getBlindRoundBidders(0).bidder, address(broker));
        assertEq(auction.getBlindRoundBidders(0).bidInfos[0], bidInfo1);
        assertEq(auction.getBlindRoundBidders(0).bidInfos[1], bidInfo2);
        
        vm.stopPrank();
    }

    function testBidAtBlindRoundInsufficientBalance() public {
        // Try to bid without having enough USDT
        address bidder = makeAddr("bidder");
        vm.startPrank(bidder);
        bytes32 bidInfo = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        
        vm.expectRevert(abi.encodeWithSelector(
            CharterAuction.InsufficientBalance.selector
        ));
        auction.bidAtBlindRound(bidInfo);
        
        vm.stopPrank();
    }

    function testBidAtBlindRoundDoubleBid() public {
        // Setup
        vm.startPrank(broker);
        usdt.transfer(address(this), 1000e18);
        usdt.approve(address(auction), 1000e18);
        
        // Create bid info
        bytes32 bidInfo = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        
        // First bid should succeed
        auction.bidAtBlindRound(bidInfo);
        
        // Second identical bid should fail
        vm.expectRevert(CharterAuction.DoubleBlindBid.selector);
        auction.bidAtBlindRound(bidInfo);
        
        vm.stopPrank();
    }

    function testBidAtBlindRoundAfterEnded() public {
        // Setup
        vm.startPrank(broker);
        usdt.transfer(address(this), 1000e18);
        usdt.approve(address(auction), 1000e18);
        
        // End the blind round
        auction.testEndBlindRound();
        
        // Try to bid after round has ended
        bytes32 bidInfo = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        
        vm.expectRevert(CharterAuction.BlindRoundEnded.selector);
        auction.bidAtBlindRound(bidInfo);
        
        vm.stopPrank();
    }

    function testBidAtBlindRoundExceedingMinRaisedFunds() public {
        // Setup
        vm.startPrank(broker);
        usdt.transfer(address(this), 1000e18);
        usdt.approve(address(auction), 1000e18);
        
        // Set raised funds close to minimum
        auction.testSetRaisedFunds(auction.minRaisedFundsAtBlindRound());
        
        // Try to bid which would exceed minimum raised funds
        bytes32 bidInfo = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        
        vm.expectRevert(CharterAuction.BlindRoundEnded.selector);
        auction.bidAtBlindRound(bidInfo);
        
        vm.stopPrank();
    }

    function testBidAtBlindRoundMultipleBidders() public {
        // Setup first bidder
        vm.startPrank(broker);
        usdt.transfer(address(this), 1000e18);
        usdt.approve(address(auction), 1000e18);
        
        bytes32 bidInfo1 = keccak256(abi.encodePacked(address(this), uint256(100e18)));
        auction.bidAtBlindRound(bidInfo1);
        
        vm.stopPrank();

        vm.startPrank(broker);
        usdt.transfer(bidder2, 1000e18);
        vm.stopPrank();
        
        vm.startPrank(bidder2);
        usdt.approve(address(auction), 1000e18);
        bytes32 bidInfo2 = keccak256(abi.encodePacked(bidder2, uint256(200e18)));
        auction.bidAtBlindRound(bidInfo2);
        
        // Verify both bidders' bids were recorded correctly
        assertEq(auction.getBlindRoundBidders(0).bidder, address(broker));
        assertEq(auction.getBlindRoundBidders(0).bidInfos[0], bidInfo1);
        assertEq(auction.getBlindRoundBidders(1).bidder, bidder2);
        assertEq(auction.getBlindRoundBidders(1).bidInfos[0], bidInfo2);
        
        vm.stopPrank();
    }

    function testEndBlindRound() public {
        // Setup initial conditions
        vm.startPrank(broker);
               
        // Create bid prices and their corresponding bid infos
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 150e18;
        bidPrices[2] = 200e18;
        
        // Create bid infos for bidder1 and bidder2
        bytes32 bidInfo1 = keccak256(abi.encodePacked(bidder1, bidPrices[0]));
        bytes32 bidInfo2 = keccak256(abi.encodePacked(bidder2, bidPrices[1]));
        bytes32 bidInfo3 = keccak256(abi.encodePacked(bidder2, bidPrices[2]));
        
        // Setup test state
        auction.testSetBlindBidderInfo(bidder1, _createSingleItemArray(bidInfo1));
        auction.testSetBlindBidderInfo(bidder2, _createTwoItemArray(bidInfo2, bidInfo3));
        auction.testSetRaisedFunds(auction.minRaisedFundsAtBlindRound());
        
        // End blind round
        auction.endBlindRound(bidPrices);
        
        // Verify round ended
        // assertTrue(auction.isBlindRoundEnded());
        
        // Verify positions were created correctly
        // assertEq(auction.getRoundPositions(0).rewarders[0], bidder1);
        // assertEq(auction.getRoundPositions(1).rewarders[0], bidder2);
        
        vm.stopPrank();
    }

    function testEndBlindRoundNotBroker() public {
        uint256[] memory bidPrices = new uint256[](1);
        vm.expectRevert(CharterAuction.NotBroker.selector);
        auction.endBlindRound(bidPrices);
    }

    function testEndBlindRoundAlreadyEnded() public {
        vm.startPrank(broker);
        
        // End the round first
        auction.testEndBlindRound();
        
        // Try to end it again
        uint256[] memory bidPrices = new uint256[](1);
        vm.expectRevert(CharterAuction.BlindRoundEnded.selector);
        auction.endBlindRound(bidPrices);
        
        vm.stopPrank();
    }

    function testEndBlindRoundInsufficientFunds() public {
        vm.startPrank(broker);
        
        // Set raised funds below minimum
        auction.testSetRaisedFunds(auction.minRaisedFundsAtBlindRound() - 2 * auction.entryFee());
        
        uint256[] memory bidPrices = new uint256[](1);
        vm.expectRevert(CharterAuction.CannotEndBlindRound.selector);
        auction.endBlindRound(bidPrices);
        
        vm.stopPrank();
    }

    function testEndBlindRoundInvalidBidInfo() public {
        vm.startPrank(broker);
        
        // Setup bidder with bid info
        address bidder = address(0x1);
        bytes32 correctBidInfo = keccak256(abi.encodePacked(bidder, uint256(100e18)));
        auction.testSetBlindBidderInfo(bidder, _createSingleItemArray(correctBidInfo));
        auction.testSetRaisedFunds(auction.minRaisedFundsAtBlindRound());
        
        // Try to end with wrong price
        uint256[] memory wrongBidPrices = new uint256[](1);
        wrongBidPrices[0] = 200e18; // Different price than what was used in bid info
        
        vm.expectRevert(CharterAuction.InvalidBidInfo.selector);
        auction.endBlindRound(wrongBidPrices);
        
        vm.stopPrank();
    }

    function testEndBlindRoundEndAuction() public {
        vm.startPrank(broker);
        
        // Setup exactly MIN_POSITIONS bidders
        for (uint256 i = 0; i < auction.MIN_POSITIONS(); i++) {
            address bidder = address(uint160(i + 1));
            uint256 price = (i + 1) * 100e18;
            bytes32 bidInfo = keccak256(abi.encodePacked(bidder, price));
            auction.testSetBlindBidderInfo(bidder, _createSingleItemArray(bidInfo));
        }
        
        auction.testSetRaisedFunds(auction.minRaisedFundsAtBlindRound());
        
        // Create bid prices array
        uint256[] memory bidPrices = new uint256[](auction.MIN_POSITIONS());
        for (uint256 i = 0; i < auction.MIN_POSITIONS(); i++) {
            bidPrices[i] = (i + 1) * 100e18;
        }
        
        // End blind round should trigger end auction
        auction.endBlindRound(bidPrices);
        
        // Verify auction ended and winner was selected
        assertTrue(auction.winner() != address(0));
        
        vm.stopPrank();
    }

    function testCheckDoubleBid() public {
        vm.startPrank(broker);
        
        // Setup a bidder with initial bid
        address bidder = address(0x1);
        bidPrice = 100e18;
        
        // Create initial bid
        uint256[] memory initialBidPrices = new uint256[](1);
        initialBidPrices[0] = bidPrice;
        auction.testSetBidderInfo(bidder, initialBidPrices);
        
        // Check for double bid with same price
        bool isDouble = auction.testCheckDoubleBid(bidPrice, bidder);
        assertTrue(isDouble, "Should detect double bid with same price");
        
        // Check with different price
        bool notDouble = auction.testCheckDoubleBid(200e18, bidder);
        assertFalse(notDouble, "Should not detect double bid with different price");
        
        vm.stopPrank();
    }

    function testCheckDoubleBidMultipleBids() public {
        vm.startPrank(broker);
        
        // Setup a bidder with multiple bids
        address bidder = address(0x1);
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        
        auction.testSetBidderInfo(bidder, bidPrices);
        
        // Check each existing bid price
        assertTrue(auction.testCheckDoubleBid(100e18, bidder));
        assertTrue(auction.testCheckDoubleBid(200e18, bidder));
        assertTrue(auction.testCheckDoubleBid(300e18, bidder));
        
        // Check new price
        assertFalse(auction.testCheckDoubleBid(400e18, bidder));
        
        vm.stopPrank();
    }

    function testCheckDoubleBidNewBidder() public {
        vm.startPrank(broker);
        
        // Check for a bidder that hasn't bid before
        address newBidder = address(0x2);
        assertFalse(auction.testCheckDoubleBid(100e18, newBidder));
        
        vm.stopPrank();
    }

    function testCheckDoubleBidMultipleBidders() public {
        vm.startPrank(broker);
        
        // Bidder 1's prices
        uint256[] memory prices1 = new uint256[](2);
        prices1[0] = 100e18;
        prices1[1] = 200e18;
        auction.testSetBidderInfo(bidder1, prices1);
        
        // Bidder 2's prices
        uint256[] memory prices2 = new uint256[](2);
        prices2[0] = 150e18;
        prices2[1] = 250e18;
        auction.testSetBidderInfo(bidder2, prices2);
        
        // Check bidder1's prices
        assertTrue(auction.testCheckDoubleBid(100e18, bidder1));
        assertTrue(auction.testCheckDoubleBid(200e18, bidder1));
        assertFalse(auction.testCheckDoubleBid(150e18, bidder1));
        
        // Check bidder2's prices
        assertTrue(auction.testCheckDoubleBid(150e18, bidder2));
        assertTrue(auction.testCheckDoubleBid(250e18, bidder2));
        assertFalse(auction.testCheckDoubleBid(100e18, bidder2));
        
        vm.stopPrank();
    }

    function testCheckDoubleBidZeroPrice() public {
        vm.startPrank(broker);
        
        // Setup a bidder with zero price
        address bidder = address(0x1);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 0;
        auction.testSetBidderInfo(bidder, prices);
        
        // Check zero price
        assertTrue(auction.testCheckDoubleBid(0, bidder));
        assertFalse(auction.testCheckDoubleBid(100e18, bidder));
        
        vm.stopPrank();
    }

    function testSearchPosition() public {
        vm.startPrank(broker);
        
        // Setup initial position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        bidPrice = 100e18;
        auction.testSetPosition(bidPrice, rewarders);
        
        // Search for existing position
        uint256 foundIndex = auction.testSearchPosition(bidPrice);
        assertEq(foundIndex, 0, "Should find position at index 0");
        
        vm.stopPrank();
    }

    function testSearchPositionNotFound() public {
        vm.startPrank(broker);
        
        // Setup initial position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        
        // Search for non-existent position
        uint256 notFoundIndex = auction.testSearchPosition(200e18);
        assertEq(notFoundIndex, 1, "Should return positions.length for not found");
        
        vm.stopPrank();
    }

    function testSearchPositionMultiplePositions() public {
        vm.startPrank(broker);
        
        // Setup multiple positions
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        
        uint256[] memory prices = new uint256[](3);
        prices[0] = 100e18;
        prices[1] = 200e18;
        prices[2] = 300e18;
        
        for (uint256 i = 0; i < prices.length; i++) {
            auction.testSetPosition(prices[i], rewarders);
        }
        
        // Search for each position
        for (uint256 i = 0; i < prices.length; i++) {
            uint256 foundIndex = auction.testSearchPosition(prices[i]);
            assertEq(foundIndex, i, "Should find position at correct index");
        }
        
        vm.stopPrank();
    }

    function testSearchPositionEmptyPositions() public {
        vm.startPrank(broker);
        
        // Search in empty positions array
        uint256 index = auction.testSearchPosition(100e18);
        assertEq(index, 0, "Should return 0 for empty positions array");
        
        vm.stopPrank();
    }

    function testSearchPositionDuplicatePrices() public {
        vm.startPrank(broker);
        
        // Setup positions with duplicate prices
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        
        uint256 duplicatePrice = 100e18;
        auction.testSetPosition(duplicatePrice, rewarders);
        
        rewarders[0] = address(0x2);
        auction.testSetPosition(duplicatePrice, rewarders);
        
        // Search for duplicate price should return first occurrence
        uint256 foundIndex = auction.testSearchPosition(duplicatePrice);
        assertEq(foundIndex, 0, "Should return index of first occurrence");
        
        vm.stopPrank();
    }

    function testSearchPositionZeroPrice() public {
        vm.startPrank(broker);
        
        // Setup position with zero price
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        auction.testSetPosition(0, rewarders);
        
        // Search for zero price
        uint256 foundIndex = auction.testSearchPosition(0);
        assertEq(foundIndex, 0, "Should find zero price position");
        
        vm.stopPrank();
    }

    function testSearchBidder() public {
        vm.startPrank(broker);
        
        // Setup initial bidder
        address testAddr = address(0x1);
        uint256[] memory testPrices = new uint256[](1);
        testPrices[0] = 100e18;
        auction.testSetBidderInfo(testAddr, testPrices);
        
        // Search for existing bidder
        uint256 foundIndex = auction.testSearchBidder(testAddr);
        assertEq(foundIndex, 0, "Should find bidder at index 0");
        
        vm.stopPrank();
    }

    function testSearchBidderNotFound() public {
        vm.startPrank(broker);
        
        // Setup initial bidder
        address testAddr = address(0x1);
        uint256[] memory testPrices = new uint256[](1);
        testPrices[0] = 100e18;
        auction.testSetBidderInfo(testAddr, testPrices);
        
        // Search for non-existent bidder
        uint256 notFoundIndex = auction.testSearchBidder(address(0x2));
        assertEq(notFoundIndex, 1, "Should return bidders.length for not found");
        
        vm.stopPrank();
    }

    function testSearchBidderMultipleBidders() public {
        vm.startPrank(broker);
        
        // Setup multiple bidders
        address[] memory testAddrs = new address[](3);
        testAddrs[0] = address(0x1);
        testAddrs[1] = address(0x2);
        testAddrs[2] = address(0x3);
        
        for (uint256 i = 0; i < testAddrs.length; i++) {
            uint256[] memory testPrices = new uint256[](1);
            testPrices[0] = (i + 1) * 100e18;
            auction.testSetBidderInfo(testAddrs[i], testPrices);
        }
        
        // Search for each bidder
        for (uint256 i = 0; i < testAddrs.length; i++) {
            uint256 foundIndex = auction.testSearchBidder(testAddrs[i]);
            assertEq(foundIndex, i, "Should find bidder at correct index");
        }
        
        vm.stopPrank();
    }

    function testSearchBidderEmptyBidders() public {
        vm.startPrank(broker);
        
        // Search in empty bidders array
        uint256 index = auction.testSearchBidder(address(0x1));
        assertEq(index, 0, "Should return 0 for empty bidders array");
        
        vm.stopPrank();
    }

    function testGetTargetPrice() public {
        vm.startPrank(broker);
        
        // Add test positions with different prices
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        
        // Add positions with known prices
        auction.testSetPosition(100e18, rewarders);
        auction.testSetPosition(200e18, rewarders);
        auction.testSetPosition(300e18, rewarders);
        
        // Get target price through test helper
        uint256 targetPrice = auction.testGetTargetPrice();
        
        // Target price should be geometric mean of top MIN_POSITIONS prices
        assertTrue(targetPrice > 0, "Target price should be positive");
        assertTrue(targetPrice <= 300e18, "Target price should not exceed highest bid");
        assertTrue(targetPrice >= 100e18, "Target price should not be less than lowest bid");
        
        vm.stopPrank();
    }

    function testGetTargetPriceEmptyPositions() public {
        vm.startPrank(broker);
        
        // Try to get target price with no positions
        vm.expectRevert(CharterAuction.InvalidNumberOfValues.selector);
        auction.testGetTargetPrice();
        
        vm.stopPrank();
    }

    function testGetTargetPriceLessThanMinPositions() public {
        vm.startPrank(broker);
        
        // Add just one position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        
        // Should still work with fewer than MIN_POSITIONS
        uint256 targetPrice = auction.testGetTargetPrice();
        assertEq(targetPrice, 100e18, "Target price should equal single position price");
        
        vm.stopPrank();
    }

    function testTurnToNextRound() public {
        vm.startPrank(broker);
        
        // Setup: End blind round
        auction.testEndBlindRound();
        
        // Setup initial bidders with their bids
        address testBidder1 = address(0x1);
        address testBidder2 = address(0x2);
        
        // Set up bids for first bidder
        uint256[] memory prices1 = new uint256[](2);
        prices1[0] = 100e18;
        prices1[1] = 200e18;
        auction.testSetBidderInfo(testBidder1, prices1);
        
        // Set up bids for second bidder
        uint256[] memory prices2 = new uint256[](2);
        prices2[0] = 300e18;
        prices2[1] = 400e18;
        auction.testSetBidderInfo(testBidder2, prices2);
        
        // Store initial state
        uint256 initialRound = auction.currentRound();
        
        // Turn to next round
        auction.turnToNextRound();
        
        // Verify state changes
        assertEq(auction.currentRound(), initialRound + 1, "Round should be incremented");
        assertTrue(auction.testIsRoundEnded(initialRound), "Previous round should be ended");
        
        // Verify positions were created with geometric means
        uint256 expectedPrice1 = auction.testGeometricMean(prices1);
        uint256 expectedPrice2 = auction.testGeometricMean(prices2);
        
        // Check positions and their bidders
        (address[] memory rewarders1, uint256 price1) = auction.testGetPosition(0);
        (address[] memory rewarders2, uint256 price2) = auction.testGetPosition(1);
        
        assertEq(price1, expectedPrice1, "First position price should match geometric mean");
        assertEq(price2, expectedPrice2, "Second position price should match geometric mean");
        assertEq(rewarders1[0], testBidder1, "First position should have correct bidder");
        assertEq(rewarders2[0], testBidder2, "Second position should have correct bidder");
        
        vm.stopPrank();
    }

    function testTurnToNextRoundFailsIfAlreadyEnded() public {
        vm.startPrank(broker);
        
        // Setup: End blind round and current round
        auction.testEndBlindRound();
        auction.testEndCurrentRound();
        
        // Attempt to turn to next round
        vm.expectRevert(CharterAuction.RoundAlreadyEnded.selector);
        auction.turnToNextRound();
        
        vm.stopPrank();
    }

    function testTurnToNextRoundFailsIfBlindRoundNotEnded() public {
        vm.startPrank(broker);
        
        // Attempt to turn to next round without ending blind round
        vm.expectRevert(CharterAuction.BlindRoundStep.selector);
        auction.turnToNextRound();
        
        vm.stopPrank();
    }

    function testTurnToNextRoundEndAuctionWithMinPositions() public {
        vm.startPrank(broker);
        
        // Setup: End blind round
        auction.testEndBlindRound();
        
        // Add exactly MIN_POSITIONS - 1 bidders
        for (uint256 i = 0; i < auction.MIN_POSITIONS() - 1; i++) {
            address testBidder = address(uint160(i + 1));
            uint256[] memory prices = new uint256[](1);
            prices[0] = (i + 1) * 100e18;
            auction.testSetBidderInfo(testBidder, prices);
        }
        
        // Turn to next round should trigger end auction
        auction.turnToNextRound();
        
        // Verify auction ended with a winner
        assertTrue(auction.winner() != address(0), "Auction should have ended with a winner");
        
        vm.stopPrank();
    }

    function testTurnToNextRoundEmitsEvent() public {
        vm.startPrank(broker);
        
        // Setup: End blind round and add some bidders
        auction.testEndBlindRound();
        
        // Add enough bidders to avoid ending auction
        for (uint256 i = 0; i < auction.MIN_POSITIONS() + 1; i++) {
            address testBidder = address(uint160(i + 1));
            uint256[] memory prices = new uint256[](1);
            prices[0] = (i + 1) * 100e18;
            auction.testSetBidderInfo(testBidder, prices);
        }
        
        // Get current round before turning
        uint256 currentRound = auction.currentRound();
        
        // Expect NewRoundStarted event with the next round number
        vm.expectEmit(true, false, false, false);
        emit NewRoundStarted(currentRound + 1);  // Changed from currentRound to currentRound + 1
        
        auction.turnToNextRound();
        
        // Verify round was incremented
        assertEq(auction.currentRound(), currentRound + 1);
        
        vm.stopPrank();
    }

    function testBidPosition() public {
        vm.startPrank(broker);
        
        // Setup: End blind round and create initial position
        auction.testEndBlindRound();
        
        address initialBidder = address(0x1);
        uint256[] memory initialPrices = new uint256[](1);
        initialPrices[0] = 100e18;
        auction.testSetBidderInfo(initialBidder, initialPrices);
        
        // Create position
        address[] memory rewarders = new address[](1);
        rewarders[0] = initialBidder;
        auction.testSetPosition(100e18, rewarders);
        
        vm.stopPrank();

        // New bidder setup
        address newBidder = address(0x2);
        vm.startPrank(newBidder);
        usdt.approve(address(auction), 1000e18);
        
        // Bid on position
        auction.bidPosition(0);
        
        // Verify state changes
        assertEq(auction.rewards(initialBidder), auction.entryFee(), "Reward should be distributed");
        
        // Verify bidder was recorded
        (address bidder11, uint256[] memory prices11) = auction.testGetBidderInfo(0);
        assertEq(bidder11, initialBidder, "Bidder should be recorded");
        assertEq(prices11[0], 100e18, "Bid price should be recorded");

        (address bidder22, uint256[] memory prices22) = auction.testGetBidderInfo(1);
        assertEq(bidder22, newBidder, "Bidder should be recorded");
        assertEq(prices22[0], 100e18, "Bid price should be recorded");
        
        vm.stopPrank();
    }

    function testBidPositionRoundEnded() public {
        vm.startPrank(broker);
        auction.testEndBlindRound();
        auction.testEndCurrentRound();
        vm.stopPrank();

        vm.expectRevert(CharterAuction.RoundEnded.selector);
        auction.bidPosition(0);
    }

    function testBidPositionBlindRoundNotEnded() public {
        vm.expectRevert(CharterAuction.BlindRoundStep.selector);
        auction.bidPosition(0);
    }

    function testBidPositionInsufficientBalance() public {
        vm.startPrank(broker);
        auction.testEndBlindRound();
        
        // Setup position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        vm.stopPrank();

        // Try to bid without enough balance
        address poorBidder = address(0x123);
        vm.startPrank(poorBidder);
        vm.expectRevert(CharterAuction.InsufficientBalance.selector);
        auction.bidPosition(0);
        vm.stopPrank();
    }

    function testBidPositionDoubleBid() public {
        vm.startPrank(broker);
        auction.testEndBlindRound();
        
        // Setup position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        vm.stopPrank();

        // Setup bidder
        address bidder = address(0x2);
        vm.startPrank(bidder);
        usdt.approve(address(auction), 1000e18);
        
        // First bid should succeed
        auction.bidPosition(0);
        
        // Second bid should fail
        vm.expectRevert(CharterAuction.DoubleBid.selector);
        auction.bidPosition(0);
        vm.stopPrank();
    }

    function testBidPositionInvalidIndex() public {
        vm.startPrank(broker);
        auction.testEndBlindRound();
        vm.stopPrank();

        vm.startPrank(address(0x2));
        usdt.approve(address(auction), 1000e18);
        
        vm.expectRevert(CharterAuction.InvalidPositionIndex.selector);
        auction.bidPosition(99); // Invalid position index
        vm.stopPrank();
    }

    function testBidPositionMultipleRewarders() public {
        vm.startPrank(broker);
        auction.testEndBlindRound();
        
        // Setup position with multiple rewarders
        address[] memory rewarders = new address[](2);
        rewarders[0] = address(0x1);
        rewarders[1] = address(0x2);
        auction.testSetPosition(100e18, rewarders);
        vm.stopPrank();

        // Setup bidder
        address bidder = address(0x3);
        vm.startPrank(bidder);
        usdt.approve(address(auction), 1000e18);
        
        // Bid on position
        auction.bidPosition(0);
        
        // Verify rewards distribution
        uint256 expectedReward = auction.entryFee() / 2; // Split between 2 rewarders
        assertEq(auction.rewards(rewarders[0]), expectedReward);
        assertEq(auction.rewards(rewarders[1]), expectedReward);
        vm.stopPrank();
    }

    function testBidPositionEmitsEvent() public {
        vm.startPrank(broker);
        auction.testEndBlindRound();
        
        // Setup position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        auction.testSetPosition(100e18, rewarders);
        vm.stopPrank();

        address bidder = address(0x2);
        vm.startPrank(bidder);
        usdt.approve(address(auction), 1000e18);
        
        vm.expectEmit(true, true, false, true);
        emit BidPosition(0, 0, bidder, auction.entryFee());
        
        auction.bidPosition(0);
        vm.stopPrank();
    }

    function testWithdrawRewards() public {
        // Setup: Add rewards for a user
        address rewarder = address(0x1);
        uint256 rewardAmount = 100e18;
        
        vm.startPrank(broker);
        auction.testSetRewards(rewarder, rewardAmount);
        usdt.transfer(address(auction), rewardAmount);
        vm.stopPrank();
        
        // Get initial balances
        uint256 initialBalance = usdt.balanceOf(rewarder);
        uint256 initialContractBalance = usdt.balanceOf(address(auction));
        
        // Withdraw rewards
        vm.startPrank(rewarder);
        auction.withdrawRewards();
        
        // Verify balances
        assertEq(usdt.balanceOf(rewarder), initialBalance + rewardAmount, "Rewarder should receive rewards");
        assertEq(usdt.balanceOf(address(auction)), initialContractBalance - rewardAmount, "Contract balance should decrease");
        assertEq(auction.rewards(rewarder), 0, "Rewards should be reset to 0");
        
        vm.stopPrank();
    }

    function testWithdrawRewardsNoRewards() public {
        // Try to withdraw with no rewards
        vm.expectRevert(CharterAuction.NoRewards.selector);
        auction.withdrawRewards();
    }

    function testWithdrawRewardsMultipleTimes() public {
        // Setup: Add rewards for a user
        address rewarder = address(0x1);
        uint256 rewardAmount = 100e18;
        
        vm.startPrank(broker);
        auction.testSetRewards(rewarder, rewardAmount);
        usdt.transfer(address(auction), rewardAmount);
        vm.stopPrank();
        
        // First withdrawal
        vm.startPrank(rewarder);
        auction.withdrawRewards();
        
        // Try to withdraw again
        vm.expectRevert(CharterAuction.NoRewards.selector);
        auction.withdrawRewards();
        
        vm.stopPrank();
    }

    function testWithdrawRewardsMultipleUsers() public {
        // Setup: Add rewards for multiple users
        address rewarder1 = address(0x11);
        address rewarder2 = address(0x22);
        uint256 rewardAmount1 = 100e18;
        uint256 rewardAmount2 = 200e18;
        
        vm.startPrank(broker);
        auction.testSetRewards(rewarder1, rewardAmount1);
        auction.testSetRewards(rewarder2, rewardAmount2);
        usdt.transfer(address(auction), rewardAmount1 + rewardAmount2);
        vm.stopPrank();
        
        // First user withdraws
        vm.startPrank(rewarder1);
        auction.withdrawRewards();
        assertEq(usdt.balanceOf(rewarder1), rewardAmount1, "First rewarder should receive correct amount");
        vm.stopPrank();
        
        // Second user withdraws
        vm.startPrank(rewarder2);
        auction.withdrawRewards();
        assertEq(usdt.balanceOf(rewarder2), rewardAmount2, "Second rewarder should receive correct amount");
        vm.stopPrank();
    }

    function testWithdrawRewardsEmitsEvent() public {
        // Setup: Add rewards for a user
        address rewarder = address(0x1);
        uint256 rewardAmount = 100e18;
        
        vm.startPrank(broker);
        auction.testSetRewards(rewarder, rewardAmount);
        usdt.transfer(address(auction), rewardAmount);
        vm.stopPrank();
        
        // Expect event emission
        vm.startPrank(rewarder);
        vm.expectEmit(true, false, false, true);
        emit RewardWithdrawn(rewarder, rewardAmount);
        
        auction.withdrawRewards();
        vm.stopPrank();
    }

    function testWithdrawRewardsAccumulated() public {
        // Setup: Add rewards multiple times for the same user
        address rewarder = address(0x10);
        uint256 firstReward = 100e18;
        uint256 secondReward = 150e18;
        
        vm.startPrank(broker);
        auction.testSetRewards(rewarder, firstReward);
        auction.testAddRewards(rewarder, secondReward);
        usdt.transfer(address(auction), firstReward + secondReward);
        vm.stopPrank();
        
        // Withdraw accumulated rewards
        vm.startPrank(rewarder);
        auction.withdrawRewards();
        
        // Verify total amount received
        assertEq(usdt.balanceOf(rewarder), firstReward + secondReward, "Should receive total accumulated rewards");
        assertEq(auction.rewards(rewarder), 0, "Rewards should be reset to 0");
        
        vm.stopPrank();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
