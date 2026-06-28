// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IVerifier} from "./VoteSubmissionVerifier.sol";
import {IVerifierHub} from "../beacon/interfaces/IVerifierHub.sol";

/// @title MembershipHubAdapter
/// @author Privacy Protocol (Cipher × Beacon)
/// @notice A thin {IVerifier} shim that routes Cipher's DAO membership verification through Beacon's
///         {IVerifierHub} (the proof oracle) instead of an embedded per-DAO verifier. From
///         {PrivateDaoAdapter}'s point of view this is just another `voteSubmissionVerifier`: it
///         implements the same `verify(proof, publicInputs)` shape, so the DAO consumes Beacon with
///         zero change to its constructor or verification logic.
/// @dev    The shim is stateless and immutable. It pins a single catalog `circuitId` at deploy time
///         (Beacon's `membership` circuit, whose public inputs are `[scope, root, nullifier]` — and
///         Cipher passes `scope = proposalId mod p`). Nullifier/replay tracking stays in the DAO.
contract MembershipHubAdapter is IVerifier {
    /// @notice The Beacon verification hub this shim forwards to.
    IVerifierHub public immutable hub;
    /// @notice The catalog circuit id pinned for membership verification (Beacon `membership` v1).
    bytes32 public immutable circuitId;

    error MembershipHubAdapter__InvalidHub();
    error MembershipHubAdapter__InvalidCircuitId();

    /// @param hub_ The deployed Beacon {VerifierHub}.
    /// @param circuitId_ The membership catalog circuit id to verify against.
    constructor(IVerifierHub hub_, bytes32 circuitId_) {
        if (address(hub_).code.length == 0) revert MembershipHubAdapter__InvalidHub();
        if (circuitId_ == bytes32(0)) revert MembershipHubAdapter__InvalidCircuitId();
        hub = hub_;
        circuitId = circuitId_;
    }

    /// @notice Verifies a membership proof by delegating to Beacon's hub for the pinned circuit.
    /// @dev    `view` (a STATICCALL-able forward) satisfies the non-view {IVerifier} interface the
    ///         DAO expects. The hub re-checks the public-input count and routes to the registered
    ///         UltraHonk verifier; a `true` result is unforgeable (SNARK soundness).
    /// @inheritdoc IVerifier
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool) {
        return hub.verify(circuitId, proof, publicInputs);
    }
}
