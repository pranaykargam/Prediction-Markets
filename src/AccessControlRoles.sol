// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Access control role constants
/// @notice Shared role IDs used by factory, market and oracle contracts.
contract AccessControlRoles {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
}
