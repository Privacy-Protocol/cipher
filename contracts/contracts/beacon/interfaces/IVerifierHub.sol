// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Vendored from the Beacon repo (`beacon/src/interfaces/IVerifierHub.sol`). This is also the
// interface Cipher's MembershipHubAdapter consumes to reach a deployed Beacon hub. Keep in sync
// with Beacon; do not edit here.

/// @title IVerifierHub
/// @notice The trustless verification entrypoint for Beacon. A consumer contract calls {verify}
///         with a catalog `circuitId` and a proof; the hub routes to the registered verifier and
///         returns the result. Verification is the only trust anchor — a `true` result cannot be
///         forged (SNARK soundness). The hub is stateless: replay/nullifier tracking is the
///         consumer's responsibility.
interface IVerifierHub {
    /// @param circuitId The catalog circuit to verify against (pin this as a constant in your contract).
    /// @param proof The serialized UltraHonk proof.
    /// @param publicInputs The public inputs the consumer binds the result to (e.g. [scope, root, nullifier]).
    /// @return True iff `proof` is valid for `publicInputs` under `circuitId`.
    function verify(bytes32 circuitId, bytes calldata proof, bytes32[] calldata publicInputs)
        external
        view
        returns (bool);
}
