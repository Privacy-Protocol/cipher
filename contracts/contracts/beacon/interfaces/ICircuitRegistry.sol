// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Vendored from the Beacon repo (`beacon/src/interfaces/ICircuitRegistry.sol`) for Cipher's
// cross-product integration test. Keep in sync with Beacon; do not edit here.

/// @title ICircuitRegistry
/// @notice The Beacon catalog: maps an immutable `circuitId` to its deployed verifier and metadata.
interface ICircuitRegistry {
    /// @param verifier      The deployed per-circuit {IVerifier}; `address(0)` means "not registered".
    /// @param vkHash        Verification-key hash, for off-chain tamper-evidence against the published circuit.
    /// @param publicInputs  Expected `publicInputs.length` for this circuit.
    /// @param active        Whether the circuit may currently be used (entries are deactivatable, never mutated).
    /// @param schema        SDK/human reference describing the public-input layout (e.g. "scope,root,nullifier").
    struct Circuit {
        address verifier;
        bytes32 vkHash;
        uint16 publicInputs;
        bool active;
        string schema;
    }

    event CircuitRegistered(
        bytes32 indexed circuitId,
        string name,
        uint32 version,
        address indexed verifier,
        bytes32 vkHash,
        uint16 publicInputs
    );
    event CircuitActiveSet(bytes32 indexed circuitId, bool active);

    error CircuitRegistry__AlreadyRegistered(bytes32 circuitId);
    error CircuitRegistry__NotRegistered(bytes32 circuitId);
    error CircuitRegistry__InvalidVerifier();
    error CircuitRegistry__InvalidPublicInputs();

    /// @notice Deterministic, content-addressed id for a catalog circuit.
    /// @dev `circuitId = keccak256(abi.encode(name, version))`.
    function circuitId(string calldata name, uint32 version) external pure returns (bytes32);

    /// @notice Returns a circuit's full metadata (zeroed struct if it was never registered).
    function getCircuit(bytes32 circuitId_) external view returns (Circuit memory);

    /// @notice Whether a circuit id has ever been registered.
    function isRegistered(bytes32 circuitId_) external view returns (bool);
}
