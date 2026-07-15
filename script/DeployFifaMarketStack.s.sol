// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MatchRegistry} from "../src/FifaTournamentRegistry.sol";
import {MarketFactory} from "../src/FifaMarketFactory.sol";
import {FifaOracleRouter} from "../src/FifaOracleRouter.sol";
import {PredictionMarket} from "../src/FifaPredictionMarket.sol";

/// @notice Deploys the registry, factory, oracle router, one market, and its initial liquidity.
/// @dev The broadcasting account must hold and approve the configured USDC amount.
contract DeployFifaMarketStack is Script {
    function run() external returns (address marketAddress) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        address usdc = vm.envAddress("USDC_ADDRESS");
        address oracleNode = vm.envAddress("ORACLE_NODE_ADDRESS");
        uint256 matchId = vm.envUint("MATCH_ID");
        uint64 kickoff = uint64(vm.envUint("KICKOFF_TIME"));
        uint256 initialLiquidity = vm.envUint("INITIAL_LIQUIDITY");

        vm.startBroadcast(privateKey);
        MatchRegistry registry = new MatchRegistry(deployer);
        MarketFactory factory = new MarketFactory(usdc, address(registry), uint16(vm.envOr("POOL_FEE_BPS", uint256(30))));
        registry.setFactory(address(factory));
        FifaOracleRouter router = new FifaOracleRouter(address(registry), oracleNode);

        marketAddress = factory.createMarket(
            matchId,
            vm.envString("HOME_TEAM"),
            vm.envString("AWAY_TEAM"),
            kickoff,
            address(router)
        );
        PredictionMarket market = PredictionMarket(marketAddress);
        market.usdc().approve(marketAddress, initialLiquidity);
        market.addLiquidity(initialLiquidity, initialLiquidity, initialLiquidity);
        vm.stopBroadcast();
    }
}
