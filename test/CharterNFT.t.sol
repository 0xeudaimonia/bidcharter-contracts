// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {CharterNFT} from "src/CharterNFT.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract CharterNFTTest is Test {
    CharterNFT public nft;
    address public admin;
    address public minter;
    address public user;
    address public burner;

    function setUp() public {
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        user = makeAddr("user");
        burner = makeAddr("burner");
        // Deploy contract with admin and minter roles
        nft = new CharterNFT(admin, minter, burner);
    }

    function test_InitialSetup() public view {
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), minter));
        assertEq(nft.name(), "CharterNFT");
        assertEq(nft.symbol(), "CNFT");
    }

    function test_BaseURI() public {
        uint256 tokenId = 0;
        vm.expectRevert(abi.encodeWithSelector(
            IERC721Errors.ERC721NonexistentToken.selector,
            tokenId
        ));
        nft.tokenURI(tokenId);
    }

    function test_mint() public {
        // Switch to minter account
        vm.startPrank(minter);
        
        string memory uri = "test-uri";
        uint256 tokenId = nft.mint(user, uri);
        
        assertEq(nft.ownerOf(tokenId), user);
        assertEq(nft.tokenURI(tokenId), "https://bidcharter.com/nft/test-uri");
        
        vm.stopPrank();
    }

    function test_mintRevertUnauthorized() public {
        vm.startPrank(user);
        
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            user,
            nft.MINTER_ROLE()
        ));
        nft.mint(user, "test-uri");
        
        vm.stopPrank();
    }


    function test_transfer() public {
        // Mint a token first
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(user, "test-uri");
        vm.stopPrank();

        // Switch to token owner and transfer
        address recipient = makeAddr("recipient");
        vm.startPrank(user);
        nft.transferFrom(user, recipient, tokenId);
        
        // Verify transfer
        assertEq(nft.ownerOf(tokenId), recipient);
        
        vm.stopPrank();
    }

    function test_transferRevertUnauthorized() public {
        // Mint a token first
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(user, "test-uri");
        vm.stopPrank();

        // Try to transfer from unauthorized account
        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(unauthorized);
        
        vm.expectRevert(abi.encodeWithSelector(
            IERC721Errors.ERC721InsufficientApproval.selector,
            unauthorized,
            tokenId
        ));
        nft.transferFrom(user, unauthorized, tokenId);
        
        vm.stopPrank();
    }

    function test_approve() public {
        // Mint a token first
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(user, "test-uri");
        vm.stopPrank();

        // Approve another address
        address approved = makeAddr("approved");
        vm.startPrank(user);
        nft.approve(approved, tokenId);
        
        // Verify approval
        assertEq(nft.getApproved(tokenId), approved);
        
        // Test that approved address can transfer
        address recipient = makeAddr("recipient");
        vm.startPrank(approved);
        nft.transferFrom(user, recipient, tokenId);
        assertEq(nft.ownerOf(tokenId), recipient);
        
        vm.stopPrank();
    }

    function test_approveRevertUnauthorized() public {
        // Mint a token first
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(user, "test-uri");
        vm.stopPrank();

        // Try to approve from unauthorized account
        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(unauthorized);
        
        vm.expectRevert(abi.encodeWithSelector(
            IERC721Errors.ERC721InvalidApprover.selector,
            unauthorized
        ));
        nft.approve(unauthorized, tokenId);
        
        vm.stopPrank();
    }


    function test_burn() public {
        // Mint a token first
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(burner, "test-uri");
        vm.stopPrank();

        // Switch to token owner and burn
        vm.startPrank(burner);
        nft.burn(tokenId);
        
        // Verify token is burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        nft.ownerOf(tokenId);
        
        vm.stopPrank();
    }

    function test_burnRevertUnauthorized() public {
        // Mint a token first
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(user, "test-uri");
        vm.stopPrank();

        // Try to burn from unauthorized account
        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(unauthorized);
        
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            unauthorized,
            nft.BURNER_ROLE()
        ));
        nft.burn(tokenId);
        
        vm.stopPrank();
    }

    function test_SupportsInterface() public view {
        // Test for ERC721 interface
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // Test for ERC721Metadata interface
        assertTrue(nft.supportsInterface(0x5b5e139f));
        // Test for AccessControl interface
        assertTrue(nft.supportsInterface(0x7965db0b));
    }
}