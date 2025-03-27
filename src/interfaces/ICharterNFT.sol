// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface ICharterNFT is IERC721, IERC721Receiver, IERC721Metadata {
    function mint(address to) external returns (uint256);
    function burn(uint256 tokenId) external;
    function setMinterRole(address minter) external;
    function setBurnerRole(address burner) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}