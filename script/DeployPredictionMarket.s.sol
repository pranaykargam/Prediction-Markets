// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PredictionMarketToken} from "../src/PredictionMarketToken.sol";
import {AMMPool} from "../src/FifaAMMPool.sol";
import {PredictionMarket} from "../src/FifaPredictionMarket.sol";

contract DeployPredictionMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        uint256 matchId = vm.envUint("MATCH_ID");
        uint64 kickoffTime = uint64(vm.envUint("KICKOFF_TIME"));

        PredictionMarketToken yesToken = new PredictionMarketToken("WC YES", "YES", deployer);
        PredictionMarketToken noToken = new PredictionMarketToken("WC NO", "NO", deployer);
        AMMPool pool = new AMMPool(usdc, address(yesToken), address(noToken), address(0), 30);

        PredictionMarket market = new PredictionMarket(
            usdc,
            address(yesToken),
            address(noToken),
            address(pool),
            oracle,
            matchId,
            vm.envString("HOME_TEAM"),
            vm.envString("AWAY_TEAM"),
            kickoffTime
        );

        pool.setMarket(address(market));
        yesToken.setMinter(address(market));
        noToken.setMinter(address(market));

        vm.stopBroadcast();
    }
}
