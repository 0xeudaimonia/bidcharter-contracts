pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {CharterFactory} from "src/CharterFactory.sol";
import {console} from "forge-std/console.sol";

contract CharterFactoryScript is Script {
    CharterFactory public factory;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("CONTRACT_OWNER");
        address usdt = vm.envAddress("USDT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        
        factory = new CharterFactory(usdt, owner);

        console.log("deployed CharterFactory Address", address(factory));
        
        vm.stopBroadcast();
    }
}