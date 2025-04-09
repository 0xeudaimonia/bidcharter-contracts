pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {MockUSDT} from "../test/mock/MockUSDT.sol";
import {console} from "forge-std/console.sol";

contract MockUSDTScript is Script {
    MockUSDT public mockUSDT;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        
        mockUSDT = new MockUSDT();

        console.log("deployed MockUSDT Address", address(mockUSDT));
        
        vm.stopBroadcast();
    }
}