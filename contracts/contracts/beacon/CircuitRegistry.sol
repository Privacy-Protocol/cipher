// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Vendored from the Beacon repo (`beacon/src/CircuitRegistry.sol`) so Hardhat can deploy a real
// Beacon catalog in Cipher's cross-product integration test. Keep in sync with Beacon; do not edit
// here.

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICircuitRegistry} from "./interfaces/ICircuitRegistry.sol";

/// @title CircuitRegistry
/// @author Privacy Protocol (Beacon)
/// @notice The Beacon circuit catalog. Maps an immutable, content-addressed `circuitId` to its
///         deployed verifier and metadata. Catalog-only: entries are added by the owner and, once
///         registered, are never mutated — a new circuit version is a new `circuitId` + verifier.
///         An entry can only be flipped active/inactive.
/// @dev    Ownership is a single owner for now; migrate to a multisig before mainnet (the owner is
///         the only governance surface — it can add and (de)activate catalog entries).
contract CircuitRegistry is ICircuitRegistry, Ownable {
    mapping(bytes32 circuitId => Circuit) private _circuits;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @inheritdoc ICircuitRegistry
    function circuitId(string calldata name, uint32 version) public pure returns (bytes32) {
        return keccak256(abi.encode(name, version));
    }

    /// @notice Registers a new catalog circuit. Reverts if the id is already taken.
    /// @param name Human-readable circuit name (part of the id preimage).
    /// @param version Circuit version (part of the id preimage); bump for any circuit change.
    /// @param verifier The deployed {IVerifier} for this circuit (must have code).
    /// @param vkHash Verification-key hash for off-chain tamper-evidence.
    /// @param publicInputs Expected number of public inputs (must be > 0).
    /// @param schema SDK/human reference for the public-input layout.
    /// @return id The content-addressed circuit id.
    function registerCircuit(
        string calldata name,
        uint32 version,
        address verifier,
        bytes32 vkHash,
        uint16 publicInputs,
        string calldata schema
    ) external onlyOwner returns (bytes32 id) {
        if (verifier == address(0) || verifier.code.length == 0) revert CircuitRegistry__InvalidVerifier();
        if (publicInputs == 0) revert CircuitRegistry__InvalidPublicInputs();

        id = circuitId(name, version);
        if (_circuits[id].verifier != address(0)) revert CircuitRegistry__AlreadyRegistered(id);

        _circuits[id] = Circuit({
            verifier: verifier,
            vkHash: vkHash,
            publicInputs: publicInputs,
            active: true,
            schema: schema
        });

        emit CircuitRegistered(id, name, version, verifier, vkHash, publicInputs);
    }

    /// @notice Enables or disables an already-registered circuit without mutating its other fields.
    function setCircuitActive(bytes32 id, bool active) external onlyOwner {
        if (_circuits[id].verifier == address(0)) revert CircuitRegistry__NotRegistered(id);
        _circuits[id].active = active;
        emit CircuitActiveSet(id, active);
    }

    /// @inheritdoc ICircuitRegistry
    function getCircuit(bytes32 id) external view returns (Circuit memory) {
        return _circuits[id];
    }

    /// @inheritdoc ICircuitRegistry
    function isRegistered(bytes32 id) external view returns (bool) {
        return _circuits[id].verifier != address(0);
    }
}
