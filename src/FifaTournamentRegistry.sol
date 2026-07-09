// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Match registry
/// @notice Stores match metadata and market address for each World Cup match.
contract MatchRegistry {
    struct MatchInfo {
        string home;
        string away;
        uint64 kickoffTime;
        address market;
    }

    address public factory;
    mapping(uint256 => MatchInfo) public matches;
    uint256[] public matchIds;

    event MatchRegistered(uint256 indexed matchId, address indexed market);
    event FactoryUpdated(address indexed previousFactory, address indexed newFactory);

    modifier onlyFactory() {
        require(msg.sender == factory, "MatchRegistry: only factory");
        _;
    }

    constructor(address _factory) {
        require(_factory != address(0), "MatchRegistry: zero factory");
        factory = _factory;
    }

    function setFactory(address newFactory) external onlyFactory {
        require(newFactory != address(0), "MatchRegistry: zero factory");
        emit FactoryUpdated(factory, newFactory);
        factory = newFactory;
    }

    function registerMatch(
        uint256 matchId,
        string calldata home,
        string calldata away,
        uint64 kickoffTime,
        address market
    ) external onlyFactory {
        require(matches[matchId].market == address(0), "MatchRegistry: already registered");
        require(market != address(0), "MatchRegistry: zero market");

        matches[matchId] = MatchInfo({home: home, away: away, kickoffTime: kickoffTime, market: market});
        matchIds.push(matchId);

        emit MatchRegistered(matchId, market);
    }

    function marketFor(uint256 matchId) external view returns (address) {
        return matches[matchId].market;
    }

    function allMatchIds() external view returns (uint256[] memory) {
        return matchIds;
    }
}
