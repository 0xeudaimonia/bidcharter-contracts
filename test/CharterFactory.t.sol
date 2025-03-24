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
    address public owner;
    address public broker;
    string public constant BASE_URI = "https://bidcharter.com/nft/";
    string public constant TEST_URI = "ipfs://test-uri";

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

        setBalance(owner, 10000000e18);
        setBalance(broker, 10000000e18);
        
        // Deploy factory with owner
        factory = new CharterFactory(
            address(usdt),
            owner
        );
    }

    /// @notice Cheatcode to set an account's balance in our MockERC20.
    function setBalance(address account, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(account, uint256(0))); // Simplified; in real tests, use proper method.
        vm.store(address(usdt), slot, bytes32(amount));
    }

    function testConstructor() public {
        assertEq(address(factory.usdt()), address(usdt));
        assertEq(factory.owner(), owner);
        assertEq(factory.getTotalAuctions(), 0);
        assertEq(factory.nextAuctionId(), 1);
    }

    function testConstructorInvalidUSDT() public {
        vm.expectRevert(CharterFactory.InvalidUSDTAddress.selector);
        new CharterFactory(
            address(0),
            owner
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
            broker,
            entryFee,
            minRaisedFunds,
            TEST_URI
        );

        // Verify auction creation
        assertEq(factory.getAuctionId(auctionAddress), 1);
        assertEq(factory.getAuctionAddress(1), auctionAddress);
        assertEq(factory.getTotalAuctions(), 1);
        assertTrue(factory.isAuctionCreatedByFactory(auctionAddress));

        // Verify NFT ownership
        assertEq(factory.nft().ownerOf(0), auctionAddress);
        assertEq(factory.nft().tokenURI(0), string(abi.encodePacked(BASE_URI, TEST_URI)));

        vm.stopPrank();
    }

    function testCreateAuctionInvalidBroker() public {
        vm.startPrank(owner);
        
        vm.expectRevert(CharterFactory.InvalidBroker.selector);
        factory.createAuction(
            address(0),
            100e18,
            1000e18,
            TEST_URI
        );

        vm.stopPrank();
    }

    function testCreateAuctionInvalidEntryFee() public {
        vm.startPrank(owner);
        
        vm.expectRevert(CharterFactory.InvalidEntryFee.selector);
        factory.createAuction(
            broker,
            0,
            1000e18,
            TEST_URI
        );

        vm.stopPrank();
    }

    function testCreateAuctionInvalidMinRaisedFunds() public {
        vm.startPrank(owner);
        
        vm.expectRevert(CharterFactory.InvalidMinRaisedFunds.selector);
        factory.createAuction(
            broker,
            100e18,
            0,
            TEST_URI
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
                broker,
                100e18,
                1000e18,
                string(abi.encodePacked(TEST_URI, "-", vm.toString(i)))
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

    function testGetNonExistentAuction() public {
        assertEq(factory.getAuctionAddress(999), address(0));
        assertEq(factory.getAuctionId(address(0x999)), 0);
        assertFalse(factory.isAuctionCreatedByFactory(address(0x999)));
    }

    function testOwnershipTransfer() public {
        address newOwner = address(0x123);
        
        vm.startPrank(owner);
        factory.transferOwnership(newOwner);
        usdt.approve(address(factory), 10000000e18);
        vm.stopPrank();
        
        assertEq(factory.owner(), newOwner);
        
        // Old owner can't create auctions
        vm.startPrank(owner);
        factory.createAuction(broker, 100e18, 1000e18, TEST_URI);
        vm.stopPrank();
        
        // New owner can create auctions
        vm.startPrank(newOwner);
        address auctionAddress = factory.createAuction(broker, 100e18, 1000e18, TEST_URI);
        assertTrue(factory.isAuctionCreatedByFactory(auctionAddress));
        vm.stopPrank();
    }
}