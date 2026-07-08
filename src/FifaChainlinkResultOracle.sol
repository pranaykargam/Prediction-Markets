// SPDX-License-Identifier: MIT
pragma solidity ^0.5.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../utils/AccessControlRoles.sol";
import "./IResultOracle.sol";
import "../factory/MatchRegistry.sol";
import "../core/PredictionMarket.sol";

/// @title Chainlink result oracle
/// @notice Emits requests and allows authorized Chainlink node to push match results.
contract ChainlinkResultOracle is AccessControl, AccessControlRoles, IResultOracle {
    MatchRegistry public immutable registry;
    bytes32 public jobId;

    event ChainlinkRequestSent(uint256 indexed matchId, bytes32 indexed jobId);
    event ChainlinkResultReceived(uint256 indexed matchId, uint8 outcome);

    constructor(
        address registryAddress,
        address oracleNode,
        bytes32 _jobId
    ) {
        require(registryAddress != address(0), "ChainlinkResultOracle: zero registry");
        require(oracleNode != address(0), "ChainlinkResultOracle: zero oracle node");

        registry = MatchRegistry(registryAddress);
        jobId = _jobId;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, oracleNode);
    }

    function requestResult(uint256 matchId) external override {
        address market = registry.marketFor(matchId);
        require(market != address(0), "ChainlinkResultOracle: unknown match");
        emit ResultRequested(matchId, msg.sender);
        emit ChainlinkRequestSent(matchId, jobId);
    }

    function pushResult(uint256 matchId, uint8 outcome) external override onlyRole(ORACLE_ROLE) {
        address market = registry.marketFor(matchId);
        require(market != address(0), "ChainlinkResultOracle: unknown match");
        PredictionMarket(market).reportOutcome(outcome);
        emit ResultReported(matchId, outcome);
        emit ChainlinkResultReceived(matchId, outcome);
    }

    function updateJobId(bytes32 newJobId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        jobId = newJobId;
    }
}