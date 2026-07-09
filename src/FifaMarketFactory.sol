// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./AccessControlRoles.sol";
import "./PredictionMarketToken.sol";
import "./FifaAMMPool.sol";
import "./FifaPredictionMarket.sol";
import "./FifaTournamentRegistry.sol";

/// @title Market factory
/// @notice Deploys prediction markets, outcome tokens, AMM pools, and registers matches.
contract MarketFactory is AccessControl, AccessControlRoles {
    struct MarketParams {
        uint256 matchId;
        string home;
        string away;
        uint64 kickoffTime;
        address oracle;
    }

    address public immutable usdc;
    MatchRegistry public immutable registry;
    uint16 public immutable poolFeeBps;

    event MarketCreated(uint256 indexed matchId, address indexed market);

    constructor(
        address _usdc,
        address _registry,
        uint16 _poolFeeBps
    ) {
        require(_usdc != address(0), "MarketFactory: zero usdc");
        require(_registry != address(0), "MarketFactory: zero registry");
        require(_poolFeeBps < 10000, "MarketFactory: invalid fee");

        usdc = _usdc;
        registry = MatchRegistry(_registry);
        poolFeeBps = _poolFeeBps;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MARKET_CREATOR_ROLE, msg.sender);
    }

    function createMarket(
        uint256 matchId,
        string calldata home,
        string calldata away,
        uint64 kickoffTime,
        address oracle
    ) external onlyRole(MARKET_CREATOR_ROLE) returns (address) {
        MarketParams memory params = MarketParams({
            matchId: matchId,
            home: home,
            away: away,
            kickoffTime: kickoffTime,
            oracle: oracle
        });

        _validateMarketParams(params);
        (PredictionMarketToken yesToken, PredictionMarketToken noToken) = _deployOutcomeTokens(matchId);
        AMMPool pool = new AMMPool(usdc, address(yesToken), address(noToken), address(0), poolFeeBps);
        PredictionMarket market = _deployMarket(params, yesToken, noToken, pool);

        pool.setMarket(address(market));
        yesToken.setMinter(address(market));
        noToken.setMinter(address(market));

        registry.registerMatch(matchId, home, away, kickoffTime, address(market));

        emit MarketCreated(matchId, address(market));
        return address(market);
    }

    function _validateMarketParams(MarketParams memory params) private view {
        require(params.oracle != address(0), "MarketFactory: zero oracle");
        require(registry.marketFor(params.matchId) == address(0), "MarketFactory: already exists");
        require(params.kickoffTime > block.timestamp, "MarketFactory: kickoff must be future");
    }

    function _deployOutcomeTokens(uint256 matchId)
        private
        returns (PredictionMarketToken yesToken, PredictionMarketToken noToken)
    {
        yesToken = new PredictionMarketToken(
            string(abi.encodePacked("WC YES #", _toString(matchId))),
            "YES",
            address(this)
        );

        noToken = new PredictionMarketToken(
            string(abi.encodePacked("WC NO #", _toString(matchId))),
            "NO",
            address(this)
        );
    }

    function _deployMarket(
        MarketParams memory params,
        PredictionMarketToken yesToken,
        PredictionMarketToken noToken,
        AMMPool pool
    ) private returns (PredictionMarket) {
        return new PredictionMarket(
            usdc,
            address(yesToken),
            address(noToken),
            address(pool),
            params.oracle,
            params.matchId,
            params.home,
            params.away,
            params.kickoffTime
        );
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
