// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Result oracle interface
/// @notice Defines the oracle rails for requesting and reporting match outcomes.
interface IResultOracle {
    event ResultRequested(uint256 indexed matchId, address indexed requester);
    event ResultReported(uint256 indexed matchId, uint8 outcome);

    function requestResult(uint256 matchId) external;
    function pushResult(uint256 matchId, uint8 outcome) external;
}