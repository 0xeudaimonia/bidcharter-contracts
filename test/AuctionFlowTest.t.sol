// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./mock/TestCharterAuction.sol";
import "src/CharterNFT.sol";
import "./mock/MockUSDT.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract CharterAuctionFlowTest is Test {
    TestCharterAuction auction;
    CharterNFT nft;
    MockUSDT public usdt;
    address public auctionOwner;
    address public admin;
    address public broker;
    uint256 public constant NUM_BIDDERS = 42; // More than 100 bidders
    address[] public bidders;
    uint256 public constant ENTRY_FEE = 2e18;
    uint256 public constant MIN_RAISED_FUNDS = 10e18;

    event NewRoundStarted(uint256 indexed round);
    event BidPositions(uint256 indexed round, uint256[] positionIndexes, address indexed bidder, uint256 entryFee);
    event EndAuction(uint256 indexed round, uint256 winningPrice, address indexed winner);

    function setUp() public {
        // Deploy contracts
        usdt = new MockUSDT();
        broker = address(0x999);
        auctionOwner = address(0x1000);
        admin = address(0x2000);

        nft = new CharterNFT(address(this));
        nft.setMinterRole(address(this));
        uint256 nftId = nft.mint(address(this));

        // Deploy auction
        auction = new TestCharterAuction(
            address(usdt),
            ENTRY_FEE,
            MIN_RAISED_FUNDS,
            broker,
            address(nft),
            nftId
        );

        // Transfer NFT to auctionmake
        nft.transferFrom(address(this), address(auction), nftId);

        // Create bidders
        for (uint256 i = 0; i < NUM_BIDDERS; i++) {
            address bidder = address(uint160(0x1000 + i));
            bidders.push(bidder);
            vm.deal(bidder, 100 ether);
            deal(address(usdt), bidder, 10000000e18);
            vm.prank(bidder);
            usdt.approve(address(auction), type(uint256).max);
        }
    }

    function testFullAuctionFlow() public {
        // 1. Blind Round
        uint256[] memory blindBidPrices = new uint256[](NUM_BIDDERS);
        for (uint256 i = 0; i < NUM_BIDDERS; i++) {
            blindBidPrices[i] = (i + 1) * 100e18;
            
            vm.startPrank(bidders[i]);
            bytes32 bidInfo = keccak256(abi.encodePacked(bidders[i], blindBidPrices[i]));
            auction.bidAtBlindRound(bidInfo);
            vm.stopPrank();
        }

        // End blind round
        vm.startPrank(broker);
        auction.endBlindRound(blindBidPrices);

        // 2. Multiple Regular Rounds (5 rounds)
        for (uint256 round = 0; round < 5; round++) {
            // Each bidder bids on positions
            for (uint256 i = 0; i < NUM_BIDDERS; i++) {
                vm.startPrank(bidders[i]);
                
                // Calculate optimal positions based on price history
                uint256[] memory positions = new uint256[](1);
                positions[0] = i;  // Distribute bids across positions
                auction.bidPositions(positions);
                vm.stopPrank();
            }

            vm.prank(broker);
            vm.expectEmit(true, false, false, false);
            emit NewRoundStarted(round + 1);
            auction.turnToNextRound();

            // Verify round progression
            assertEq(auction.currentRound(), round + 1);
            assertTrue(auction.testIsRoundEnded(round));
        }
        
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(bidders[i]);
            
            // Calculate optimal positions based on price history
            uint256[] memory positions = new uint256[](1);
            positions[0] = i;  // Distribute bids across positions
            auction.bidPositions(positions);
            vm.stopPrank();
        }

        vm.prank(broker);
        vm.expectEmit(true, false, false, false);
        emit NewRoundStarted(6);
        auction.turnToNextRound();
        
        // 3. End Auction
        vm.prank(broker);
        vm.expectEmit(true, false, true, false);
        emit EndAuction(6, auction.exposed_getTargetPrice(6), address(0));  // winner address will be determined
        auction.endAuction();

        // 4. Verify Final State
        address winner = auction.winner();
        assertTrue(winner != address(0), "Winner should be set");

        // Verify winner can withdraw NFT
        vm.prank(winner);
        auction.withdrawNFT();
        assertEq(nft.ownerOf(0), winner, "Winner should own NFT");

        // 5. Verify Rewards Distribution
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < NUM_BIDDERS; i++) {
            uint256 reward = auction.rewards(bidders[i]);
            if (reward > 0) {
                vm.startPrank(bidders[i]);
                deal(address(usdt), bidders[i], 10000000e18);
                auction.withdrawRewards();
                assertEq(usdt.balanceOf(bidders[i]), 10000000e18 + reward, "Reward withdrawal failed");
                totalRewards += reward;
                vm.stopPrank();
            }
        }
        assertGt(totalRewards, 0, "Should have distributed rewards");

        // 6. Verify Broker Rewards
        uint256 contractBalance = usdt.balanceOf(address(auction));
        if (contractBalance > 0) {
            vm.prank(broker);
            auction.withdrawRewards(contractBalance);
        }
    }

    /// @notice Helper function to verify bidder state
    function verifyBidderState(address bidder, uint256 round) internal view {
        (address actualBidder, uint256[] memory prices) = auction.testGetBidderInfo(round);
        if (prices.length > 0) {
            assertEq(actualBidder, bidder, "Bidder mismatch");
            assertGt(prices.length, 0, "Should have bid prices");
        }
    }

    /// @notice Helper function to verify round state
    function verifyRoundState(uint256 round) internal view {
        if (round > 0) {
            assertTrue(auction.testIsRoundEnded(round - 1), "Previous round should be ended");
        }
        assertFalse(auction.testIsRoundEnded(round), "Current round should not be ended");
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}