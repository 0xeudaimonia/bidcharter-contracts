// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { Strings } from "openzeppelin-contracts/contracts/utils/Strings.sol";
import { CharterFactory } from "src/CharterFactory.sol";
import { CharterAuction } from "src/CharterAuction.sol";
import { CharterNFT } from "src/CharterNFT.sol";
import { MockUSDT } from "./mock/MockUSDT.sol";

contract CharterFactoryTest is Test {
    CharterFactory public factory;
    MockUSDT public usdt;
    CharterNFT public nft;
    address public owner;
    address public broker;
    string public constant BASE_URI = "https://bidcharter.com/nft/";

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed broker,
        uint256 entryFee,
        uint256 minRaisedFunds,
        uint256 tokenId
    );

    function setUp() public {
        usdt = new MockUSDT();
        owner = address(0x1);
        broker = address(0x2);
        nft = new CharterNFT(owner);

        
        setBalance(owner, 10000000e18);
        setBalance(broker, 10000000e18);
        
        // Deploy factory with owner
        factory = new CharterFactory(
          address(usdt),
          address(nft)
        );
        
        vm.prank(owner);
        nft.setMinterRole(address(factory));
      }

    /// @notice Cheatcode to set an account's balance in our MockERC20.
    function setBalance(address account, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(account, uint256(0))); // Simplified; in real tests, use proper method.
        vm.store(address(usdt), slot, bytes32(amount));
    }

    function testConstructor() public view {
        assertEq(address(factory.usdt()), address(usdt));
        assertEq(factory.getTotalAuctions(), 0);
        assertEq(factory.nextAuctionId(), 1);
    }

    function testConstructorInvalidUSDT() public {
        vm.expectRevert(CharterFactory.InvalidUSDTAddress.selector);
        new CharterFactory(
            address(0),
            address(nft)
        );
    }

    function testCreateAuction() public {
        vm.startPrank(owner);
        
        uint256 entryFee = 100e18;
        uint256 minRaisedFunds = 1000e18;

        usdt.approve(address(factory), 10000000e18);

        // // Expect AuctionCreated event
        // vm.expectEmit(true, true, true, true);
        // emit AuctionCreated(1, address(auctionAddress), broker, entryFee, minRaisedFunds, 0);

        // Create auction
        address auctionAddress = factory.createAuction(
            entryFee,
            minRaisedFunds
        );

        // Verify auction creation
        assertEq(factory.getAuctionId(auctionAddress), 1);
        assertEq(factory.getAuctionAddress(1), auctionAddress);
        assertEq(factory.getTotalAuctions(), 1);
        assertTrue(factory.isAuctionCreatedByFactory(auctionAddress));

        // Verify NFT ownership
        assertEq(factory.nft().ownerOf(0), auctionAddress);
        assertEq(factory.nft().tokenURI(0), string(abi.encodePacked(BASE_URI, "0")));

        vm.stopPrank();
    }

    function testCreateAuctionInvalidEntryFee() public {
        vm.startPrank(owner);
        
        vm.expectRevert(CharterFactory.InvalidEntryFee.selector);
        factory.createAuction(
            0,
            1000e18
        );

        vm.stopPrank();
    }

    function testCreateAuctionInvalidMinRaisedFunds() public {
        vm.startPrank(owner);
        
        vm.expectRevert(CharterFactory.InvalidMinRaisedFunds.selector);
        factory.createAuction(
            100e18,
            0
        );

        vm.stopPrank();
    }

    function testCreateMultipleAuctions() public {
        vm.startPrank(owner);
        
        usdt.approve(address(factory), 10000000e18);

        uint256 numAuctions = 3;
        address[] memory auctionAddresses = new address[](numAuctions);
        
        for (uint256 i = 0; i < numAuctions; i++) {
            auctionAddresses[i] = factory.createAuction(
                100e18,
                1000e18
            );
            
            // Verify each auction
            assertEq(factory.getAuctionId(auctionAddresses[i]), i + 1);
            assertTrue(factory.isAuctionCreatedByFactory(auctionAddresses[i]));
            assertEq(factory.nft().ownerOf(i), auctionAddresses[i]);
        }
        
        assertEq(factory.getTotalAuctions(), numAuctions);
        assertEq(factory.nextAuctionId(), numAuctions + 1);

        vm.stopPrank();
    }

    function testGetNonExistentAuction() public view {
        assertEq(factory.getAuctionAddress(999), address(0));
        assertEq(factory.getAuctionId(address(0x999)), 0);
        assertFalse(factory.isAuctionCreatedByFactory(address(0x999)));
    }
}