// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./AccessControlRoles.sol";
import "./FifaTournamentRegistry.sol";
import "./FifaPredictionMarket.sol";
import "../Interfaces/IPredictionMarket.sol";

/// @notice Minimal interface for router-style FIFA oracle adapters.
interface IFifaOracle {
    event ResultSubmitted(uint256 indexed matchId, uint8 outcome, address indexed reporter);
    event SignedResultSubmitted(uint256 indexed matchId, uint8 outcome, address indexed signer, address indexed relayer);

    function submitResult(uint256 matchId, uint8 outcome) external;
    function submitSignedResult(uint256 matchId, uint8 outcome, bytes calldata signature) external;
}

/// @title Fifa Oracle Router
/// @notice Accepts direct pushes from authorized oracle nodes or relayed signed results.
/// Forwards final outcome to the corresponding PredictionMarket (via MatchRegistry lookup).
contract FifaOracleRouter is AccessControl, AccessControlRoles, IFifaOracle {
    using ECDSA for bytes32;

    MatchRegistry public immutable registry;

    // prevent signature replay
    mapping(bytes32 => bool) public usedSignatures;

    event OracleNodeAdded(address indexed node);
    event OracleNodeRemoved(address indexed node);

    constructor(address registryAddress, address initialOracleNode) {
        require(registryAddress != address(0), "FifaOracleRouter: zero registry");
        registry = MatchRegistry(registryAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (initialOracleNode != address(0)) {
            _grantRole(ORACLE_ROLE, initialOracleNode);
            emit OracleNodeAdded(initialOracleNode);
        }
    }

    /// @notice Direct submit by a trusted oracle node (has ORACLE_ROLE).
    function submitResult(uint256 matchId, uint8 outcome) external override onlyRole(ORACLE_ROLE) {
        _forwardResult(matchId, outcome);
        emit ResultSubmitted(matchId, outcome, msg.sender);
    }

    /// @notice Submit result relayed with a signature from an authorized oracle signer.
    /// The signer must hold ORACLE_ROLE.
    /// Signed message binds to this contract and chain to avoid cross-contract replay.
    function submitSignedResult(
        uint256 matchId,
        uint8 outcome,
        bytes calldata signature
    ) external override {
        require(outcome == 0 || outcome == 1, "FifaOracleRouter: invalid outcome");

        bytes32 digest = keccak256(abi.encodePacked(address(this), block.chainid, matchId, outcome));
        bytes32 ethDigest = _toEthSignedMessageHash(digest);

        address signer = ethDigest.recover(signature);
        require(signer != address(0), "FifaOracleRouter: invalid signature");
        require(hasRole(ORACLE_ROLE, signer), "FifaOracleRouter: signer not authorized");

        bytes32 sigKey = keccak256(signature);
        require(!usedSignatures[sigKey], "FifaOracleRouter: signature used");
        usedSignatures[sigKey] = true;

        _forwardResult(matchId, outcome);

        emit SignedResultSubmitted(matchId, outcome, signer, msg.sender);
    }

    /// @dev Internal forwarding: lookup market and call reportOutcome.
    function _forwardResult(uint256 matchId, uint8 outcome) internal {
        address marketAddr = registry.marketFor(matchId);
        require(marketAddr != address(0), "FifaOracleRouter: unknown match");
        IPredictionMarket(marketAddr).reportOutcome(outcome);
    }

    function _toEthSignedMessageHash(bytes32 digest) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    /// @notice Admin can add an oracle node allowed to call submitResult directly.
    function addOracleNode(address node) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(node != address(0), "FifaOracleRouter: zero node");
        _grantRole(ORACLE_ROLE, node);
        emit OracleNodeAdded(node);
    }

    /// @notice Admin can revoke an oracle node.
    function removeOracleNode(address node) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(ORACLE_ROLE, node), "FifaOracleRouter: not an oracle");
        _revokeRole(ORACLE_ROLE, node);
        emit OracleNodeRemoved(node);
    }

    /// @notice Helper to check if a signer is authorized.
    function isAuthorizedSigner(address signer) external view returns (bool) {
        return hasRole(ORACLE_ROLE, signer);
    }
}
