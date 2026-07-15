// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Settlement entry point exposed to result-oracle adapters.
interface IPredictionMarket {
    function reportOutcome(uint8 outcome) external;
}
