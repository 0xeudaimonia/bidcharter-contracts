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
    address bidder4 = address(0x7);
    address bidder5 = address(0x8);

    // Set entry fee to 2 USDT (scaled by 1e18) and minimum funds for blind round to 10 USDT.
    uint256 entryFee = 2e18;
    uint256 minRaisedFunds = 10e18;

    // Add event test
    event NewRoundStarted(uint256 indexed round);
    event BidPosition(uint256 indexed round, uint256 positionIndex, address indexed bidder, uint256 entryFee);
    event RewardWithdrawn(address indexed rewarder, uint256 amount);
    event BlindBidEntered(uint256 indexed round, address indexed bidder, bytes32 bidInfo);
    event NFTWithdrawn(address indexed winner);
    event RewardsWithdrawn(address indexed broker, uint256 amount);
    event BidPositions(uint256 indexed round, uint256[] positionIndexes, address indexed bidder, uint256 entryFee);
    event EndAuction(uint256 indexed round, uint256 winningPrice, address indexed winner);

    function setUp() public {
        // Deploy the mock USDT token.
        usdt = new MockUSDT();
        // Mint tokens by setting balance manually (for testing only).
        usdt.balanceOf(bidder1); // for clarity, although not needed
        usdt.balanceOf(bidder2);
        usdt.balanceOf(bidder3);
        usdt.balanceOf(bidder4);
        usdt.balanceOf(bidder5);

        broker = address(0x4);
        // For testing purposes, manually set balances.
        // In practice, use a mint function or a pre-minted token.
        // NOTE: Using cheatcodes here to set storage directly.
        setBalance(bidder1, 10000000e18);
        setBalance(bidder2, 10000000e18);
        setBalance(bidder3, 10000000e18);
        setBalance(bidder4, 10000000e18);
        setBalance(bidder5, 10000000e18);
        setBalance(broker, 10000000e18);

        // Deploy the NFT contract.
        nft = new CharterNFT(address(this));

        nft.setMinterRole(address(this));
        // Mint a token for the auction.
        uint256 nftId = nft.mint(address(this));

        // Deploy the auction contract.
        auction = new TestCharterAuction(address(usdt), entryFee, minRaisedFunds, broker, address(nft), nftId);

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

    function testSearchPosition() public {
        vm.startPrank(broker);
        
        // Setup initial position
        address[] memory rewarders = new address[](1);
        rewarders[0] = address(0x1);
        bidPrice = 100e18;
        auction.testSetPosition(bidPrice, rewarders);
        
        // Search for existing position
        uint256 foundIndex = auction.testSearchPosition(0, bidPrice);
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
        uint256 notFoundIndex = auction.testSearchPosition(0, 200e18);
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
            uint256 foundIndex = auction.testSearchPosition(0, prices[i]);
            assertEq(foundIndex, i, "Should find position at correct index");
        }
        
        vm.stopPrank();
    }

    function testSearchPositionEmptyPositions() public {
        vm.startPrank(broker);
        
        // Search in empty positions array
        uint256 index = auction.testSearchPosition(0, 100e18);
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
        uint256 foundIndex = auction.testSearchPosition(0, duplicatePrice);
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
        uint256 foundIndex = auction.testSearchPosition(0, 0);
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

    
  function testBidAtBlindRound() public {
        // Prepare bid data
        uint256 bidAmount = 502e18;
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, bidAmount));

        console.logBytes32(bidInfo);

        // Approve USDT spending
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);

        // Expect BlindBidEntered event
        vm.expectEmit(true, true, false, true);
        emit BlindBidEntered(0, bidder1, bidInfo);

        // Place bid
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();

        // Verify USDT transfer
        assertEq(usdt.balanceOf(address(auction)), entryFee);
        assertEq(usdt.balanceOf(bidder1), 10000000e18 - entryFee);
    }

    function testBidAtBlindRoundWhenEnded() public {
        // Try to bid after round ended
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(500e18)));

        auction.testEndBlindRound();
        
        vm.expectRevert(CharterAuction.BlindRoundEnded.selector);
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();
    }

    function testBidAtBlindRoundInsufficientBalance() public {
        // Create new bidder with insufficient balance
        address poorBidder = address(0x4);
        usdt.mint(poorBidder, entryFee - 1);

        // Try to bid with insufficient balance
        vm.startPrank(poorBidder);
        usdt.approve(address(auction), entryFee - 1);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        
        vm.expectRevert(abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientAllowance.selector,
            address(auction),
            entryFee - 1,
            entryFee
        ));
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();
    }

    function testBidAtBlindRoundDoubleBid() public {
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee * 2);

        // First bid
        bytes32 bidInfo1 = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        auction.bidAtBlindRound(bidInfo1);

        // Try to bid again
        bytes32 bidInfo2 = keccak256(abi.encodePacked(bidder1, uint256(600e18)));
        vm.expectRevert(CharterAuction.DoubleBlindBid.selector);
        auction.bidAtBlindRound(bidInfo2);
        vm.stopPrank();
    }

    // function testBidAtBlindRoundExceedingMinRaisedFunds() public {
    //     // Calculate how many bids needed to exceed minRaisedFunds
    //     uint256 maxBids = auction.minRaisedFundsAtBlindRound() / auction.entryFee();
        
    //     // Create and fund multiple bidders
    //     for (uint256 i = 0; i < maxBids; i++) {
    //         address bidder = address(uint160(0x1000 + i));
    //         usdt.mint(bidder, entryFee);
            
    //         vm.startPrank(bidder);
    //         usdt.approve(address(auction), entryFee);
    //         bytes32 bidInfo = keccak256(abi.encodePacked(bidder, uint256(500e18)));
    //         auction.bidAtBlindRound(bidInfo);
    //         vm.stopPrank();
    //     }

    //     // Try to bid after reaching minRaisedFunds
    //     vm.startPrank(bidder1);
    //     usdt.approve(address(auction), entryFee);
    //     bytes32 bidInfo1 = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        
    //     vm.expectRevert(CharterAuction.BlindRoundEnded.selector);
    //     auction.bidAtBlindRound(bidInfo1);
    //     vm.stopPrank();
    // }

    function testBidAtBlindRoundMultipleBidders() public {
        // First bidder
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo1 = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        auction.bidAtBlindRound(bidInfo1);
        vm.stopPrank();

        // Second bidder
        vm.startPrank(bidder2);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo2 = keccak256(abi.encodePacked(bidder2, uint256(600e18)));
        auction.bidAtBlindRound(bidInfo2);
        vm.stopPrank();

        // Verify total raised funds
        assertEq(usdt.balanceOf(address(auction)), entryFee * 2);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function testSqrt() public view {
        // Test perfect squares
        assertEq(auction.exposed_sqrt(0), 0);
        assertEq(auction.exposed_sqrt(1), 1);
        assertEq(auction.exposed_sqrt(4), 2);
        assertEq(auction.exposed_sqrt(9), 3);
        assertEq(auction.exposed_sqrt(16), 4);
        assertEq(auction.exposed_sqrt(25), 5);
        assertEq(auction.exposed_sqrt(100), 10);
        assertEq(auction.exposed_sqrt(10000), 100);
        assertEq(auction.exposed_sqrt(1000000), 1000);
    }

    function testSqrtLargeNumbers() public view {
        // Test large numbers
        assertEq(auction.exposed_sqrt(2**128), 2**64);
        assertEq(auction.exposed_sqrt(2**250), 2**125);
        assertEq(auction.exposed_sqrt(type(uint128).max), 18446744073709551615);
    }

    function testSqrtNonPerfectSquares() public view {
        // Test non-perfect squares (should return floor of square root)
        assertEq(auction.exposed_sqrt(2), 1);
        assertEq(auction.exposed_sqrt(3), 1);
        assertEq(auction.exposed_sqrt(5), 2);
        assertEq(auction.exposed_sqrt(8), 2);
        assertEq(auction.exposed_sqrt(99), 9);
        assertEq(auction.exposed_sqrt(1000), 31);
        assertEq(auction.exposed_sqrt(65536), 256);
    }

    function testSqrtFuzzPerfectSquares(uint8 x) public view {
        // Skip 0 as it's already tested
        vm.assume(x > 0);
        uint256 square = uint256(x) * uint256(x);
        assertEq(auction.exposed_sqrt(square), x);
    }

    function testSqrtFuzzGeneral(uint256 x) public view {

        // Test different ranges
        if (x % 3 == 0) {
            // Small numbers
            x = bound(x, 0, 1000);
        } else if (x % 3 == 1) {
            // Medium numbers
            x = bound(x, 1001, 1000000);
        } else {
            // Large numbers
            x = bound(x, 1000001, type(uint64).max);
        }

        uint256 result = auction.exposed_sqrt(x);
        
        // Properties that should hold for any square root:
        // 1. result² ≤ x
        // 2. (result + 1)² > x
        
        if (x > 0) {
            // Check result is not too small
            assert(result * result <= x);
            
            // Check result is not too large
            // Handle the case where result is max uint256
            if (result < type(uint256).max) {
                assert((result + 1) * (result + 1) > x || (result + 1) * (result + 1) < result * result); // second condition checks for overflow
            }
        } else {
            // x = 0 case
            assertEq(result, 0);
        }
    }

    function testSqrtGas() public {
        // Test gas consumption for different input sizes
        uint256[] memory inputs = new uint256[](5);
        inputs[0] = 4;                    // small number
        inputs[1] = 1000000;              // medium number
        inputs[2] = 2**128;               // large power of 2
        inputs[3] = type(uint128).max;    // maximum uint256
        inputs[4] = 123456789;            // arbitrary number

        for (uint256 i = 0; i < inputs.length; i++) {
            uint256 startGas = gasleft();
            auction.exposed_sqrt(inputs[i]);
            uint256 gasUsed = startGas - gasleft();
            emit log_named_uint("Gas used for sqrt", gasUsed);
        }
    }

    function BidMultiple(address[] memory bidders, uint256[] memory bidPrices) internal {
        for (uint256 i = 0; i < bidders.length; i++) {
            vm.startPrank(bidders[i]);
            usdt.approve(address(auction), entryFee);
            bytes32 bidInfo = keccak256(abi.encodePacked(bidders[i], bidPrices[i]));
            auction.bidAtBlindRound(bidInfo);
            vm.stopPrank();
        }
    }   

    function testEndBlindRound() public {

        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 500e18;
        bidPrices[1] = 600e18;
        bidPrices[2] = 700e18;
        bidPrices[3] = 800e18;
        bidPrices[4] = 900e18;

        // Create dynamic arrays for bidders and prices
        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Place bids
        BidMultiple(bidders, bidPrices);

        // End blind round
        vm.prank(broker);
        vm.expectEmit(true, false, false, false);
        emit NewRoundStarted(0);
        auction.endBlindRound(bidPrices);

        // Verify round ended
        assertTrue(auction.isBlindRoundEnded());

        // Verify positions were created correctly
        uint256 bidPrice1 = auction.getRoundPositionBidPrice(0, 0);
        address rewarder1 = auction.getRoundPositionsRewarder(0, 0, 0);
        assertEq(bidPrice1, bidPrices[0]);
        assertEq(rewarder1, bidder1);

        uint256 bidPrice2 = auction.getRoundPositionBidPrice(0, 1);
        address rewarder2 = auction.getRoundPositionsRewarder(0, 1, 0);
        assertEq(bidPrice2, bidPrices[1]);
        assertEq(rewarder2, bidder2);
    }

    function testEndBlindRoundAlreadyEnded() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 500e18;
        bidPrices[1] = 600e18;
        bidPrices[2] = 700e18;
        bidPrices[3] = 800e18;
        bidPrices[4] = 900e18;

        // Create dynamic arrays for bidders and prices
        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;
        // Place a valid bid
        BidMultiple(bidders, bidPrices);

        // End round first time
        vm.startPrank(broker);
        auction.endBlindRound(bidPrices);

        // Try to end again
        vm.expectRevert(CharterAuction.BlindRoundEnded.selector);
        auction.endBlindRound(bidPrices);
        vm.stopPrank();
    }

    function testEndBlindRoundNoBidders() public {
        uint256[] memory bidPrices = new uint256[](0);
        
        vm.prank(broker);
        vm.expectRevert(CharterAuction.NoBidders.selector);
        auction.endBlindRound(bidPrices);
    }

    function testEndBlindRoundInvalidNumberOfBidPrices() public {
        // Place one bid
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();

        // Try to end with wrong number of prices
        uint256[] memory bidPrices = new uint256[](2);
        bidPrices[0] = 500e18;
        bidPrices[1] = 600e18;

        vm.prank(broker);
        vm.expectRevert(CharterAuction.InvalidNumberOfBidPrices.selector);
        auction.endBlindRound(bidPrices);
    }

    function testEndBlindRoundNotBroker() public {
        // Place a bid
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();

        // Try to end round as non-broker
        uint256[] memory bidPrices = new uint256[](1);
        bidPrices[0] = 500e18;

        vm.prank(bidder1);
        vm.expectRevert(CharterAuction.NotBroker.selector);
        auction.endBlindRound(bidPrices);
    }

    function testEndBlindRoundInvalidBidInfo() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 500e18;
        bidPrices[1] = 600e18;
        bidPrices[2] = 700e18;
        bidPrices[3] = 800e18;
        bidPrices[4] = 900e18;

        // Create dynamic arrays for bidders and prices
        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;
        // Place valid bids
        BidMultiple(bidders, bidPrices);

        bidPrices[2] = 701e18;

        vm.prank(broker);
        vm.expectRevert(CharterAuction.InvalidBidInfo.selector);
        auction.endBlindRound(bidPrices);
    }

    function testEndBlindRoundInsufficientRaisedFunds() public {
        uint256 nftId = nft.mint(address(this));
        // Deploy the auction contract.
        auction = new TestCharterAuction(address(usdt), entryFee, 1000e18, broker, address(nft), nftId);

        // Place a bid
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(500e18)));
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();

        uint256[] memory bidPrices = new uint256[](1);
        bidPrices[0] = 500e18;

        vm.prank(broker);
        vm.expectRevert(CharterAuction.CannotEndBlindRound.selector);
        auction.endBlindRound(bidPrices);
    }

    function testGetTargetPrice() public {
        // Place 4 bids with different prices
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Mint USDT and place bids
        BidMultiple(bidders, bidPrices);

        // End blind round
        vm.prank(broker);
        auction.endBlindRound(bidPrices);

        // Get target price and verify
        // For 4 positions, targetStep = sqrt(4) = 2
        // So we should collect prices[0] and prices[2]
        // Target price should be geometric mean of [100e18, 300e18]
        uint256 expectedPrice = auction.exposed_geometricMean(
            _arrayOf(100e18, 300e18, 500e18)
        );
        assertEq(auction.exposed_getTargetPrice(0), expectedPrice);
    }

    function testGetTargetPriceWithDifferentSizes() public {
        // Test with 9 positions (targetStep = 3)
        uint256[] memory bidPrices = new uint256[](9);
        address[] memory bidders = new address[](9);
        
        for (uint256 i = 0; i < 9; i++) {
            bidPrices[i] = (i + 1) * 100e18;
            bidders[i] = address(uint160(0x20 + i));
            
            usdt.mint(bidders[i], entryFee);
            vm.startPrank(bidders[i]);
            usdt.approve(address(auction), entryFee);
            bytes32 bidInfo = keccak256(abi.encodePacked(bidders[i], bidPrices[i]));
            auction.bidAtBlindRound(bidInfo);
            vm.stopPrank();
        }

        vm.prank(broker);
        auction.endBlindRound(bidPrices);

        // For 9 positions, targetStep = sqrt(9) = 3
        // Should collect prices[0], prices[3], prices[6]
        uint256 expectedPrice = auction.exposed_geometricMean(
            _arrayOf(900e18, 600e18, 300e18)
        );
        assertEq(auction.exposed_getTargetPrice(0), expectedPrice);
    }

    function testGetTargetPriceEmpty() public view {
        assertEq(auction.exposed_getTargetPrice(0), 0);
    }

    function testGetTargetPriceSinglePosition() public {
        // Place single bid
        usdt.mint(bidder1, entryFee);
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        bytes32 bidInfo = keccak256(abi.encodePacked(bidder1, uint256(100e18)));
        auction.bidAtBlindRound(bidInfo);
        vm.stopPrank();

        auction.set_minRaisedFundsAtBlindRound(entryFee);

        vm.prank(broker);
        auction.endBlindRound(_arrayOf(100e18));

        assertEq(auction.exposed_getTargetPrice(0), 100e18);
    }

    // Helper function to create uint256 arrays
    function _arrayOf(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        return arr;
    }

    function _arrayOf(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }

    function _arrayOf(uint256 a) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = a;
        return arr;
    }

    function testBidPosition() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;
        // Complete blind round and turn to next round
        _completeBlindRound(bidders, bidPrices);
        
        // Bid on position
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        
        vm.expectEmit(true, true, true, true);
        emit BidPosition(0, 0, bidder1, entryFee);
        
        auction.bidPosition(0);
        vm.stopPrank();

        // Verify bid was recorded
        (uint256 bidPrice0, address[] memory rewarders) = auction.exposed_getRoundPosition(0, 0);
        assertGt(bidPrice0, 0);
        assertEq(rewarders[0], bidder1);
    }

    function testBidPositionFailures() public {
        // Test bidding before blind round ends
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.BlindRoundStep.selector);
        auction.bidPosition(0);
        vm.stopPrank();

        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;
        // Complete blind round and turn to next round
        _completeBlindRound(bidders, bidPrices);

        // Test invalid position index
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.InvalidPositionIndex.selector);
        auction.bidPosition(999);
        vm.stopPrank();

        // Test insufficient balance
        address poorBidder = address(0x9);
        vm.startPrank(poorBidder);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.InsufficientBalance.selector);
        auction.bidPosition(0);
        vm.stopPrank();

        // Test double bid
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee * 2);
        auction.bidPosition(0);
        vm.expectRevert(CharterAuction.DoubleBid.selector);
        auction.bidPosition(0);
        vm.stopPrank();
    }

    function testBidPositionRewards() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;
        // Complete blind round and turn to next round
        _completeBlindRound(bidders, bidPrices);

        // First bidder bids on position
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        auction.bidPosition(0);
        vm.stopPrank();

        // Second bidder bids on same position
        vm.startPrank(bidder2);
        usdt.approve(address(auction), entryFee);
        auction.bidPosition(0);
        vm.stopPrank();

        // Verify rewards distribution
        assertEq(auction.rewards(bidder1), entryFee * 2);
    }

    // Helper function to complete blind round
    function _completeBlindRound(address[] memory bidders, uint256[] memory bidPrices) internal {
        // Mint USDT and place bids
        BidMultiple(bidders, bidPrices);

        vm.prank(broker);
        auction.endBlindRound(bidPrices);
    }

    function testBidPositionRewardsMultipleBids(address[] memory bidders, uint256[] memory positions) internal {
        for (uint256 i = 0; i < positions.length; i++) {
            vm.startPrank(bidders[i]);
            usdt.approve(address(auction), entryFee);
            auction.bidPosition(positions[i]);
            vm.stopPrank();
        }
    }

    function testHundredRoundsOfBidding() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Complete blind round first
        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;

        // Run 100 rounds
        for (uint256 round = 0; round < 100; round++) {
            // Place bids in current round
            testBidPositionRewardsMultipleBids(bidders, positions);

            // Turn to next round
            vm.startPrank(broker);
            vm.expectEmit(true, false, false, false);
            emit NewRoundStarted(round + 1);
            auction.turnToNextRound();
            vm.stopPrank();

            // Verify round state
            assertTrue(auction.testIsRoundEnded(round));
            assertEq(auction.currentRound(), round + 1);

            // Verify positions and prices in new round
            for (uint256 i = 0; i < bidders.length; i++) {
                // Get the geometric mean of previous prices for this bidder
                uint256[] memory previousPrices = new uint256[](1);
                previousPrices[0] = bidPrices[i];
                uint256 expectedPrice = auction.testGeometricMean(previousPrices);

                // Find the position with this price
                bool found = false;
                for (uint256 j = 0; j < 5; j++) {
                    (address[] memory rewarders, uint256 positionPrice) = auction.testGetPosition(j);
                    if (positionPrice == expectedPrice) {
                        found = true;
                        assertEq(rewarders[0], bidders[i]);
                        break;
                    }
                }
                assertTrue(found, "Position not found for bidder");
            }

            // Verify rewards accumulation
            for (uint256 i = 0; i < bidders.length; i++) {
                uint256 expectedReward = entryFee * (round + 1);
                assertGe(auction.rewards(bidders[i]), expectedReward, 
                    "Reward should accumulate each round");
            }

            // Verify contract balance increases
            uint256 expectedBalance = entryFee * bidders.length * (round + 2); // +2 includes blind round
            assertEq(usdt.balanceOf(address(auction)), expectedBalance, 
                "Contract balance should increase with each round");
        }
    }

    function testTurnToNextRound() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Complete blind round first
        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;
        testBidPositionRewardsMultipleBids(bidders, positions);

        // Turn to next round
        vm.startPrank(broker);
        vm.expectEmit(true, false, false, false);
        emit NewRoundStarted(1);
        auction.turnToNextRound();
        vm.stopPrank();

        // Verify round state
        assertTrue(auction.testIsRoundEnded(0));
        assertEq(auction.currentRound(), 1);

        // Verify positions and prices in new round
        for (uint256 i = 0; i < bidders.length; i++) {
            // Get the geometric mean of previous prices for this bidder
            uint256[] memory previousPrices = new uint256[](1);
            previousPrices[0] = bidPrices[i];
            uint256 expectedPrice = auction.testGeometricMean(previousPrices);

            // Find the position with this price
            bool found = false;
            for (uint256 j = 0; j < 5; j++) {
                (address[] memory rewarders, uint256 positionPrice) = auction.testGetPosition(j);
                if (positionPrice == expectedPrice) {
                    found = true;
                    assertEq(rewarders[0], bidders[i]);
                    break;
                }
            }
            assertTrue(found, "Position not found for bidder");
        }
    }

    function testTurnToNextRoundFailures() public {
        // Test turning before blind round ends
        vm.startPrank(broker);
        vm.expectRevert(CharterAuction.BlindRoundStep.selector);
        auction.turnToNextRound();
        vm.stopPrank();

        // Test turning after round already ended
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;
        testBidPositionRewardsMultipleBids(bidders, positions);

        vm.startPrank(broker);
        auction.turnToNextRound();
        vm.expectRevert(CharterAuction.NoBidders.selector);
        auction.turnToNextRound();

        testBidPositionRewardsMultipleBids(bidders, positions);

        auction.testSetWinner(bidder1);
        vm.expectRevert(CharterAuction.AuctionAlreadyEnded.selector);
        auction.turnToNextRound();
        vm.stopPrank();
    }

    function testTurnToNextRoundWithMultipleRounds() public {
        // Test turning after round already ended
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;
        
        // Complete multiple rounds
        for (uint256 round = 0; round < 3; round++) {
            
            testBidPositionRewardsMultipleBids(bidders, positions);
            
            vm.prank(broker);
            auction.turnToNextRound();

            // Verify round progression
            assertEq(auction.currentRound(), round + 1);
            assertTrue(auction.testIsRoundEnded(round));
        }
    }

    function testTurnToNextRoundAfterAuctionEnded() public {
        // Test turning after round already ended
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        // Set auction as ended
        vm.prank(broker);
        auction.testSetWinner(bidder1);

        // Try to turn to next round after auction ended
        vm.prank(broker);
        vm.expectRevert(CharterAuction.AuctionAlreadyEnded.selector);
        auction.turnToNextRound();
    }

    function testExtractAllBidPrices() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Complete blind round
        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;

        // Place bids in first round
        testBidPositionRewardsMultipleBids(bidders, positions);

        // Turn to next round
        vm.prank(broker);
        auction.turnToNextRound();

        // Place bids in second round
        testBidPositionRewardsMultipleBids(bidders, positions);

        // Extract prices for first bidder
        uint256[] memory extractedPrices = auction.exposed_extractAllBidPrices(0);

        // Verify array length (blind round + 2 rounds)
        assertEq(extractedPrices.length, 2);

        // Get bidder info for verification
        (address actualBidder, uint256[] memory currentRoundPrices) = auction.testGetBidderInfo(0);
        assertEq(actualBidder, bidder1);

        // Verify prices from current round
        assertEq(currentRoundPrices[0], bidPrices[0]);

        // Verify nextBidPrices from previous rounds
        (uint256 bidPrice0, ) = auction.exposed_getRoundPosition(0, 0);
        (uint256 bidPrice1, ) = auction.exposed_getRoundPosition(1, 0);
        assertEq(extractedPrices[0], bidPrice0);
        assertEq(extractedPrices[1], bidPrice1);
    }

    function testExtractAllBidPricesEmptyBidder() public {
        // Try to extract prices for non-existent bidder index
        vm.expectRevert();
        auction.exposed_extractAllBidPrices(999);
    }

    function testExtractAllBidPricesMultipleRounds() public {
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;

        address[] memory bidders = new address[](3);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;

        auction.set_minRaisedFundsAtBlindRound(entryFee * 3);

        // Complete blind round
        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](3);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;

        // Complete multiple rounds
        for (uint256 round = 0; round < 3; round++) {
            testBidPositionRewardsMultipleBids(bidders, positions);
            
            vm.prank(broker);
            auction.turnToNextRound();
        }

        testBidPositionRewardsMultipleBids(bidders, positions);

        // Extract prices for first bidder
        uint256[] memory extractedPrices = auction.exposed_extractAllBidPrices(0);

        // Verify array length (current round + 4 rounds history)
        assertEq(extractedPrices.length, 4);

        // Verify prices from each round
        for (uint256 i = 0; i < 4; i++) {
            if (i == 0) {
                (address actualBidder, uint256[] memory currentRoundPrices) = auction.testGetBidderInfo(0);
                assertEq(actualBidder, bidder1);
                assertEq(extractedPrices[i], currentRoundPrices[0]);
            } else {
                (bidPrice, ) = auction.exposed_getRoundPosition(i - 1, 0);
                assertEq(extractedPrices[i], bidPrice);
            }
        }
    }

    function testExtractAllBidPricesMultipleBidsInRound() public {
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;

        address[] memory bidders = new address[](3);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;

        auction.set_minRaisedFundsAtBlindRound(entryFee * 3);

        // Complete blind round
        _completeBlindRound(bidders, bidPrices);

        // Place multiple bids in first round
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee * 2);
        auction.bidPosition(0);
        auction.bidPosition(1);
        vm.stopPrank();

        // Extract prices
        uint256[] memory extractedPrices = auction.exposed_extractAllBidPrices(0);
        
        // Verify array length (2 current bids + 1 blind round)
        assertEq(extractedPrices.length, 2);
        
        // Verify the current round bids
        (address actualBidder, uint256[] memory currentRoundPrices) = auction.testGetBidderInfo(0);
        assertEq(actualBidder, bidder1);
        assertEq(currentRoundPrices.length, 2);
        
        for (uint256 i = 0; i < currentRoundPrices.length; i++) {
            assertEq(extractedPrices[i], currentRoundPrices[i]);
        }
    }

    function testWithdrawNFT() public {
        // Setup winner
        vm.prank(broker);
        auction.testSetWinner(bidder1);

        // Try to withdraw NFT
        vm.startPrank(bidder1);
        vm.expectEmit(true, false, false, false);
        emit NFTWithdrawn(bidder1);
        auction.withdrawNFT();
        vm.stopPrank();

        // Verify NFT ownership
        assertEq(nft.ownerOf(0), bidder1);
    }

    function testWithdrawNFTNotWinner() public {
        // Setup winner
        vm.prank(broker);
        auction.testSetWinner(bidder1);

        // Try to withdraw as non-winner
        vm.prank(bidder2);
        vm.expectRevert(CharterAuction.NotWinner.selector);
        auction.withdrawNFT();
    }

    function testWithdrawNFTNoNFT() public {
        // Setup winner
        vm.prank(broker);
        auction.testSetWinner(bidder1);

        // First withdrawal
        vm.startPrank(bidder1);
        auction.withdrawNFT();

        // Try to withdraw again
        vm.expectRevert(CharterAuction.NoNFT.selector);
        auction.withdrawNFT();
        vm.stopPrank();
    }

    function testWithdrawNFTWinnerNotSet() public {
        // Try to withdraw without winner being set
        vm.prank(bidder1);
        vm.expectRevert(CharterAuction.NotWinner.selector);
        auction.withdrawNFT();
    }

    function testWithdrawNFTMultipleAttempts() public {
        // Setup winner
        vm.prank(broker);
        auction.testSetWinner(bidder1);

        // Successful withdrawal
        vm.startPrank(bidder1);
        auction.withdrawNFT();

        // Verify NFT ownership
        assertEq(nft.ownerOf(0), bidder1);

        // Try to withdraw again
        vm.expectRevert(CharterAuction.NoNFT.selector);
        auction.withdrawNFT();
        vm.stopPrank();
    }

    function testBrokerWithdrawRewards() public {
        uint256 withdrawAmount = 100e18;
        
        // Setup: Transfer USDT to auction contract
        vm.startPrank(broker);
        usdt.transfer(address(auction), withdrawAmount);
        
        // Get initial balances
        uint256 initialBrokerBalance = usdt.balanceOf(broker);
        uint256 initialContractBalance = usdt.balanceOf(address(auction));
        
        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit RewardsWithdrawn(broker, withdrawAmount);
        
        // Withdraw rewards
        auction.withdrawRewards(withdrawAmount);
        vm.stopPrank();
        
        // Verify balances
        assertEq(usdt.balanceOf(broker), initialBrokerBalance + withdrawAmount, "Broker should receive rewards");
        assertEq(usdt.balanceOf(address(auction)), initialContractBalance - withdrawAmount, "Contract balance should decrease");
    }

    function testBrokerWithdrawRewardsNotBroker() public {
        uint256 withdrawAmount = 100e18;
        
        // Try to withdraw as non-broker
        vm.startPrank(bidder1);
        vm.expectRevert(CharterAuction.NotBroker.selector);
        auction.withdrawRewards(withdrawAmount);
        vm.stopPrank();
    }

    function testBrokerWithdrawRewardsInsufficientBalance() public {
        uint256 contractBalance = 50e18;
        uint256 withdrawAmount = 100e18;
        
        // Setup: Transfer USDT to auction contract
        vm.startPrank(broker);
        usdt.transfer(address(auction), contractBalance);
        
        // Try to withdraw more than available
        vm.expectRevert(); // Should revert with ERC20 insufficient balance error
        auction.withdrawRewards(withdrawAmount);
        vm.stopPrank();
    }

    function testBrokerWithdrawRewardsMultipleTimes() public {
        uint256 firstWithdraw = 50e18;
        uint256 secondWithdraw = 30e18;
        
        // Setup: Transfer USDT to auction contract
        vm.startPrank(broker);
        usdt.transfer(address(auction), firstWithdraw + secondWithdraw);
        
        // First withdrawal
        uint256 initialBalance = usdt.balanceOf(broker);
        auction.withdrawRewards(firstWithdraw);
        assertEq(usdt.balanceOf(broker), initialBalance + firstWithdraw);
        
        // Second withdrawal
        auction.withdrawRewards(secondWithdraw);
        assertEq(usdt.balanceOf(broker), initialBalance + firstWithdraw + secondWithdraw);
        vm.stopPrank();
    }

    function testBrokerWithdrawRewardsZeroAmount() public {
        // Try to withdraw zero amount
        vm.startPrank(broker);
        auction.withdrawRewards(0);
        vm.stopPrank();
        
        // No revert expected, but no state change should occur
        // Could add additional assertions if zero amount should be rejected
    }

    function testBrokerWithdrawRewardsAfterBids() public {
        // Setup initial bids to generate rewards
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;

        address[] memory bidders = new address[](3);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;

        auction.set_minRaisedFundsAtBlindRound(entryFee * 3);

        // Complete blind round and place bids
        _completeBlindRound(bidders, bidPrices);
        
        uint256[] memory positions = new uint256[](3);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        testBidPositionRewardsMultipleBids(bidders, positions);

        // Get accumulated entry fees
        uint256 totalFees = entryFee * bidders.length * 2; // Blind round + regular round
        
        // Withdraw accumulated fees
        vm.startPrank(broker);
        vm.expectEmit(true, false, false, true);
        emit RewardsWithdrawn(broker, totalFees);
        
        auction.withdrawRewards(totalFees);
        vm.stopPrank();
        
        // Verify broker received the fees
        assertEq(usdt.balanceOf(broker), 10000000e18 + totalFees);
    }

    function testBidPositions() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Complete blind round
        _completeBlindRound(bidders, bidPrices);

        // Create position indexes array
        uint256[] memory positionIndexes = new uint256[](2);
        positionIndexes[0] = 0;
        positionIndexes[1] = 1;

        // Get initial balances
        uint256 initialBalance = usdt.balanceOf(bidder1);
        uint256 initialContractBalance = usdt.balanceOf(address(auction));

        // Bid on multiple positions
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee * 2);
        
        vm.expectEmit(true, false, true, true);
        emit BidPositions(0, positionIndexes, bidder1, entryFee);
        
        auction.bidPositions(positionIndexes);
        vm.stopPrank();

        // Verify balances
        assertEq(usdt.balanceOf(bidder1), initialBalance - (entryFee * 2));
        assertEq(usdt.balanceOf(address(auction)), initialContractBalance + (entryFee * 2));

        // Verify bids were recorded
        (address actualBidder, uint256[] memory bidderPrices) = auction.testGetBidderInfo(0);
        assertEq(actualBidder, bidder1);
        assertEq(bidderPrices.length, 2);
        assertEq(bidderPrices[0], bidPrices[0]);
        assertEq(bidderPrices[1], bidPrices[1]);

        // Verify rewards distribution
        assertEq(auction.rewards(bidders[0]), entryFee);
        assertEq(auction.rewards(bidders[1]), entryFee);
    }

    function testBidPositionsRoundEnded() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        // End the round
        vm.prank(broker);
        auction.testEndCurrentRound();

        // Try to bid after round ended
        uint256[] memory positionIndexes = new uint256[](1);
        positionIndexes[0] = 0;

        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.RoundEnded.selector);
        auction.bidPositions(positionIndexes);
        vm.stopPrank();
    }

    function testBidPositionsBeforeBlindRound() public {
        uint256[] memory positionIndexes = new uint256[](1);
        positionIndexes[0] = 0;

        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.BlindRoundStep.selector);
        auction.bidPositions(positionIndexes);
        vm.stopPrank();
    }

    function testBidPositionsInsufficientBalance() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        address poorBidder = address(0x123);
        uint256[] memory positionIndexes = new uint256[](2);
        positionIndexes[0] = 0;
        positionIndexes[1] = 1;

        vm.startPrank(poorBidder);
        usdt.approve(address(auction), entryFee * 2);
        vm.expectRevert(CharterAuction.InsufficientBalance.selector);
        auction.bidPositions(positionIndexes);
        vm.stopPrank();
    }

    function testBidPositionsInvalidIndex() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positionIndexes = new uint256[](1);
        positionIndexes[0] = 999;

        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.InvalidPositionIndex.selector);
        auction.bidPositions(positionIndexes);
        vm.stopPrank();
    }

    function testBidPositionsDoubleBid() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positionIndexes = new uint256[](1);
        positionIndexes[0] = 0;

        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee * 2);
        
        // First bid should succeed
        auction.bidPositions(positionIndexes);
        
        // Second bid on same position should fail
        vm.expectRevert(CharterAuction.DoubleBid.selector);
        auction.bidPositions(positionIndexes);
        vm.stopPrank();
    }

    function testBidPositionsAuctionEnded() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        // Set winner to end auction
        vm.prank(broker);
        auction.testSetWinner(bidder1);

        uint256[] memory positionIndexes = new uint256[](1);
        positionIndexes[0] = 0;

        vm.startPrank(bidder2);
        usdt.approve(address(auction), entryFee);
        vm.expectRevert(CharterAuction.AuctionAlreadyEnded.selector);
        auction.bidPositions(positionIndexes);
        vm.stopPrank();
    }

    function testEndAuction() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        // Complete blind round
        _completeBlindRound(bidders, bidPrices);

        // Place bids in first round
        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;
        testBidPositionRewardsMultipleBids(bidders, positions);

        // Turn to next round
        vm.prank(broker);
        auction.turnToNextRound();

        // Get target price
        // uint256 targetPrice = auction.exposed_getTargetPrice();

        // Place bids close to target price
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        auction.bidPosition(2); // Bid closest to target price
        vm.stopPrank();

        // End auction
        vm.prank(broker);
        vm.expectEmit(true, false, true, true);
        emit EndAuction(1, bidPrices[1], bidders[1]);
        auction.endAuction();

        // Verify winner
        assertEq(auction.winner(), bidders[1]);
    }

    function testEndAuctionInvalidNumberOfPositions() public {
        uint256[] memory bidPrices = new uint256[](5);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;
        bidPrices[3] = 400e18;
        bidPrices[4] = 500e18;

        address[] memory bidders = new address[](5);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;
        bidders[3] = bidder4;
        bidders[4] = bidder5;

        _completeBlindRound(bidders, bidPrices);

        // Place more than MIN_POSITIONS bids
        uint256[] memory positions = new uint256[](5);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        positions[3] = 3;
        positions[4] = 4;
        testBidPositionRewardsMultipleBids(bidders, positions);

        vm.prank(broker);
        auction.turnToNextRound();

        // Try to end auction as non-broker with too many positions
        vm.prank(bidder1);
        vm.expectRevert(CharterAuction.InvalidNumberOfPositions.selector);
        auction.endAuction();
    }

    function testEndAuctionRoundAlreadyEnded() public {
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;

        address[] memory bidders = new address[](3);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;

        auction.set_minRaisedFundsAtBlindRound(entryFee * 3);

        _completeBlindRound(bidders, bidPrices);

        uint256[] memory positions = new uint256[](3);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        testBidPositionRewardsMultipleBids(bidders, positions);

        vm.prank(broker);
        auction.turnToNextRound();

        testBidPositionRewardsMultipleBids(bidders, positions);

        // End the round
        vm.prank(broker);
        auction.testEndCurrentRound();

        // Try to end auction after round ended
        vm.prank(broker);
        vm.expectRevert(CharterAuction.RoundAlreadyEnded.selector);
        auction.endAuction();
    }

    function testEndAuctionInBlindRound() public {
        // Try to end auction during blind round
        vm.prank(broker);
        vm.expectRevert(CharterAuction.StillInBlindRound.selector);
        auction.endAuction();
    }

    function testEndAuctionAlreadyEnded() public {
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;

        address[] memory bidders = new address[](3);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;

        auction.set_minRaisedFundsAtBlindRound(entryFee * 3);

        _completeBlindRound(bidders, bidPrices);

        // Place more than MIN_POSITIONS bids
        uint256[] memory positions = new uint256[](3);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        testBidPositionRewardsMultipleBids(bidders, positions);

        vm.prank(broker);
        auction.turnToNextRound();

        testBidPositionRewardsMultipleBids(bidders, positions);

        // End auction first time
        vm.prank(broker);
        auction.endAuction();

        // Try to end auction again
        vm.prank(broker);
        vm.expectRevert(CharterAuction.AuctionAlreadyEnded.selector);
        auction.endAuction();
    }

    function testEndAuctionClosestToTarget() public {
        uint256[] memory bidPrices = new uint256[](3);
        bidPrices[0] = 100e18;
        bidPrices[1] = 200e18;
        bidPrices[2] = 300e18;

        address[] memory bidders = new address[](3);
        bidders[0] = bidder1;
        bidders[1] = bidder2;
        bidders[2] = bidder3;

        auction.set_minRaisedFundsAtBlindRound(entryFee * 3);

        _completeBlindRound(bidders, bidPrices);

        // Place more than MIN_POSITIONS bids
        uint256[] memory positions = new uint256[](3);
        positions[0] = 0;
        positions[1] = 1;
        positions[2] = 2;
        testBidPositionRewardsMultipleBids(bidders, positions);

        vm.prank(broker);
        auction.turnToNextRound();

        // uint256 targetPrice = auction.exposed_getTargetPrice();

        // Place bids with known distances from target
        vm.startPrank(bidder1);
        usdt.approve(address(auction), entryFee);
        auction.bidPosition(0); // Far from target
        vm.stopPrank();

        vm.startPrank(bidder2);
        usdt.approve(address(auction), entryFee);
        auction.bidPosition(1); // Closer to target
        vm.stopPrank();

        vm.startPrank(bidder3);
        usdt.approve(address(auction), entryFee);
        auction.bidPosition(2); // Closest to target
        vm.stopPrank();

        // End auction
        vm.prank(broker);
        auction.endAuction();

        // Verify winner is bidder with closest price to target
        assertEq(auction.winner(), bidders[1]);
    }
}
