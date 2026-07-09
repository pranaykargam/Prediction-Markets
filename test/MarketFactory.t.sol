// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarketToken.sol";
import "../src/FifaMarketFactory.sol";
import "../src/FifaTournamentRegistry.sol";
import "../src/FifaOracleRouter.sol";

contract MarketFactoryTest is Test {
    PredictionMarketToken usdc;
    MatchRegistry registry;
    FifaOracleRouter oracle;
    MarketFactory factory;

    function setUp() public {
        usdc = new PredictionMarketToken("USD Coin", "USDC", address(this));
        registry = new MatchRegistry(address(this));
        oracle = new FifaOracleRouter(address(registry), address(0xA11CE));
        factory = new MarketFactory(address(usdc), address(registry), 30);
        registry.setFactory(address(factory));
    }

    function testCreateMarketRegistersMatch() public {
        uint64 kickoff = uint64(block.timestamp + 7200);
        address market = factory.createMarket(1, "Team A", "Team B", kickoff, address(oracle));

        assertEq(registry.marketFor(1), market);

        uint256[] memory ids = registry.allMatchIds();
        assertEq(ids.length, 1);
        assertEq(ids[0], 1);
    }

    function testDuplicateMarketCreationReverts() public {
        uint64 kickoff = uint64(block.timestamp + 7200);
        factory.createMarket(2, "Team C", "Team D", kickoff, address(oracle));

        vm.expectRevert("MarketFactory: already exists");
        factory.createMarket(2, "Team C", "Team D", kickoff, address(oracle));
    }
}
