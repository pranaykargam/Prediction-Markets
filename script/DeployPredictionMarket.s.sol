// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

contract DeployPredictionMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy with 1 ETH, token value 0.01 ETH (1e16 wei), 50% YES, 10% lock
        new PredictionMarket{value: 1 ether}(
            vm.addr(deployerPrivateKey), // owner
            vm.addr(deployerPrivateKey), // oracle (using same address for simplicity)
            "Will ETH reach $10k by end of 2024?",
            0.01 ether, // initialTokenValue
            50, // 50% YES
            10  // 10% lock
        );

        vm.stopBroadcast();
    }
}