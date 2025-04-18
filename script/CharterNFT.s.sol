pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {CharterNFT} from "src/CharterNFT.sol";
import {console} from "forge-std/console.sol";

contract CharterNFTScript is Script {
    CharterNFT public nft;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("CONTRACT_OWNER");

        vm.startBroadcast(deployerPrivateKey);
        
        nft = new CharterNFT(owner);

        console.log("deployed CharterNFT Address", address(nft));
        
        vm.stopBroadcast();
    }
}