// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Vendored from the Beacon repo (`beacon/src/VerifierHub.sol`) so Hardhat can deploy a real Beacon
// hub in Cipher's cross-product integration test. Keep in sync with Beacon; do not edit here.

import {IVerifierHub} from "./interfaces/IVerifierHub.sol";
import {ICircuitRegistry} from "./interfaces/ICircuitRegistry.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";

/// @title VerifierHub
/// @author Privacy Protocol (Beacon)
/// @notice Stateless, trustless verification entrypoint. Looks a circuit up in the
///         {CircuitRegistry}, validates the public-input count, and routes verification to the
///         registered {IVerifier}. Holds no app state — consumers track spent nullifiers themselves.
/// @dev    `verify` is `view`: the registered verifier is a pure cryptographic check, reached via
///         `STATICCALL`. A `true` result is therefore unforgeable (SNARK soundness).
contract VerifierHub is IVerifierHub {
    /// @notice The catalog this hub verifies against.
    ICircuitRegistry public immutable registry;

    error VerifierHub__UnknownCircuit(bytes32 circuitId);
    error VerifierHub__InactiveCircuit(bytes32 circuitId);
    error VerifierHub__PublicInputCountMismatch(uint16 expected, uint256 provided);
    error VerifierHub__InvalidRegistry();

    constructor(address registry_) {
        if (registry_ == address(0) || registry_.code.length == 0) revert VerifierHub__InvalidRegistry();
        registry = ICircuitRegistry(registry_);
    }

    /// @inheritdoc IVerifierHub
    function verify(bytes32 circuitId, bytes calldata proof, bytes32[] calldata publicInputs)
        external
        view
        returns (bool)
    {
        ICircuitRegistry.Circuit memory c = registry.getCircuit(circuitId);

        if (c.verifier == address(0)) revert VerifierHub__UnknownCircuit(circuitId);
        if (!c.active) revert VerifierHub__InactiveCircuit(circuitId);
        if (publicInputs.length != c.publicInputs) {
            revert VerifierHub__PublicInputCountMismatch(c.publicInputs, publicInputs.length);
        }

        return IVerifier(c.verifier).verify(proof, publicInputs);
    }
}
