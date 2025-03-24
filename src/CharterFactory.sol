// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CharterAuction } from "./CharterAuction.sol";
import { CharterNFT } from "./CharterNFT.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
/// @title CharterFactory
/// @notice Factory contract for creating new Charter Auctions and minting associated NFTs
contract CharterFactory is Ownable {
    // State variables
    CharterNFT public immutable nft;
    IERC20 public immutable usdt;
    uint256 public nextAuctionId;
    
    // Mapping from auction ID to auction contract
    mapping(uint256 => address) public auctions;
    // Mapping from auction address to auction ID
    mapping(address => uint256) public auctionIds;

    // Events
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed auctionAddress,
        address indexed broker,
        uint256 entryFee,
        uint256 minRaisedFunds,
        uint256 tokenId
    );

    // Errors
    error InvalidUSDTAddress();
    error InvalidEntryFee();
    error InvalidMinRaisedFunds();
    error InvalidBroker();

    /// @notice Constructor sets the NFT and USDT contract addresses
    /// @param _usdt The USDT token contract address
    constructor(
        address _usdt,
        address _owner
    ) Ownable(_owner) {
        if (_usdt == address(0)) revert InvalidUSDTAddress();
        
        usdt = IERC20(_usdt);
        nft = new CharterNFT(_owner, address(this), _owner);
        nextAuctionId = 1;
    }

    /// @notice Creates a new auction and mints an associated NFT
    /// @param _broker The broker address for the auction
    /// @param _entryFee The entry fee for the auction
    /// @param _minRaisedFunds The minimum funds to be raised
    /// @return auctionAddress The address of the created auction contract
    function createAuction(
        address _broker,
        uint256 _entryFee,
        uint256 _minRaisedFunds,
        string memory _nftURI
    ) external returns (address auctionAddress) {
        // Input validation
        if (_broker == address(0)) revert InvalidBroker();
        if (_entryFee == 0) revert InvalidEntryFee();
        if (_minRaisedFunds == 0) revert InvalidMinRaisedFunds();

        // Create new auction contract
        CharterAuction newAuction = new CharterAuction(
            address(usdt),
            _entryFee,
            _minRaisedFunds,
            _broker
        );
        
        uint256 auctionId = nextAuctionId;
        
        // Store auction information
        auctions[auctionId] = address(newAuction);
        auctionIds[address(newAuction)] = auctionId;
        
        // Mint NFT to broker
        uint256 tokenId = nft.mint(address(newAuction), _nftURI);
        
        // Increment auction ID
        nextAuctionId++;
        
        emit AuctionCreated(
            auctionId,
            address(newAuction),
            _broker,
            _entryFee,
            _minRaisedFunds,
            tokenId
        );
        
        return address(newAuction);
    }

    /// @notice Get auction address by ID
    /// @param auctionId The ID of the auction
    /// @return The auction contract address
    function getAuctionAddress(uint256 auctionId) external view returns (address) {
        return auctions[auctionId];
    }

    /// @notice Get auction ID by address
    /// @param auctionAddress The address of the auction contract
    /// @return The auction ID
    function getAuctionId(address auctionAddress) external view returns (uint256) {
        return auctionIds[auctionAddress];
    }

    /// @notice Get total number of auctions created
    /// @return The total number of auctions
    function getTotalAuctions() external view returns (uint256) {
        return nextAuctionId - 1;
    }

    /// @notice Check if an address is an auction created by this factory
    /// @param auctionAddress The address to check
    /// @return True if the address is an auction created by this factory
    function isAuctionCreatedByFactory(address auctionAddress) external view returns (bool) {
        return auctionIds[auctionAddress] != 0;
    }
}