// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarketToken.sol";
import "../src/FifaAMMPool.sol";
import "../src/FifaPredictionMarket.sol";
import "../src/FifaTournamentRegistry.sol";
import "../src/FifaOracleRouter.sol";

contract FifaOracleRouterTest is Test {
    PredictionMarketToken usdc;
    PredictionMarketToken yes;
    PredictionMarketToken no;
    AMMPool pool;
    MatchRegistry registry;
    FifaOracleRouter router;
    PredictionMarket market;

    uint256 private constant ORACLE_KEY = 0xD00D;
    address oracleNode;

    function setUp() public {
        oracleNode = vm.addr(ORACLE_KEY);

        usdc = new PredictionMarketToken("USD Coin", "USDC", address(this));
        yes = new PredictionMarketToken("YES Token", "YES", address(this));
        no = new PredictionMarketToken("NO Token", "NO", address(this));

        pool = new AMMPool(address(usdc), address(yes), address(no), address(0), 30);
        registry = new MatchRegistry(address(this));
        router = new FifaOracleRouter(address(registry), oracleNode);

        market = new PredictionMarket(
            address(usdc),
            address(yes),
            address(no),
            address(pool),
            address(router),
            42,
            "Home",
            "Away",
            uint64(block.timestamp + 3600)
        );

        pool.setMarket(address(market));
        yes.setMinter(address(market));
        no.setMinter(address(market));
        registry.registerMatch(42, "Home", "Away", uint64(block.timestamp + 3600), address(market));
        market.closeMarket();
    }

    function testDirectOracleSubmission() public {
        vm.prank(oracleNode);
        router.submitResult(42, 1);

        assertEq(market.winningOutcome(), 1);
    }

    function testUnauthorizedSubmissionReverts() public {
        vm.expectRevert();
        router.submitResult(42, 1);
    }

    function testSignedResultSubmission() public {
        bytes32 digest = _signedResultDigest(42, 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        router.submitSignedResult(42, 1, signature);
        assertEq(market.winningOutcome(), 1);
    }

    function testSignatureReplayReverts() public {
        bytes32 digest = _signedResultDigest(42, 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ORACLE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        router.submitSignedResult(42, 1, signature);

        vm.expectRevert("FifaOracleRouter: signature used");
        router.submitSignedResult(42, 1, signature);
    }

    function _signedResultDigest(uint256 matchId, uint8 outcome) private view returns (bytes32) {
        bytes32 digest = keccak256(abi.encodePacked(address(router), block.chainid, matchId, outcome));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }
}
