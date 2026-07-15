// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Read interface for the tournament match registry.
interface IMatchRegistry {
    function marketFor(uint256 matchId) external view returns (address);
    function allMatchIds() external view returns (uint256[] memory);
}
