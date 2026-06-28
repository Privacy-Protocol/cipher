// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Vendored from the Beacon repo (`beacon/src/interfaces/IVerifier.sol`) so Hardhat can compile and
// deploy a real VerifierHub in Cipher's cross-product integration test. Keep byte-for-byte in sync
// with Beacon; do not edit here.

/// @title IVerifier
/// @notice Minimal interface every per-circuit verifier in the Beacon catalog implements.
/// @dev    This is the standard Noir → Solidity UltraHonk `HonkVerifier.verify` shape. The
///         verifier is a pure cryptographic check (no state writes), so it is exposed as `view`
///         and the {VerifierHub} reaches it via `STATICCALL`.
interface IVerifier {
    /// @param proof The serialized UltraHonk proof bytes.
    /// @param publicInputs The circuit's public inputs, each a 32-byte field element.
    /// @return True iff the proof is valid for `publicInputs` under this verifier's verification key.
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
