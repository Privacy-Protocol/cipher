// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {externalEuint8, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {IGovernorConfidential} from "../../Governance/interfaces/IGovernorConfidential.sol";

/// @title IPrivateDaoAdapter
/// @author Obaloluwa
/// @notice External interface for {PrivateDaoAdapter}: a confidential, OpenZeppelin-style Governor
///         (FHE-encrypted ballots + encrypted tally) with an OPTIONAL zero-knowledge membership
///         gate. It extends {IGovernorConfidential} (propose / state / execute / etc.) and adds the
///         confidential voting, result-decryption, and membership-gate surface.
/// @dev    Use this interface to call a deployed adapter from another contract. To deploy your own
///         DAO, inherit the concrete {PrivateDaoAdapter} instead.
interface IPrivateDaoAdapter is IGovernorConfidential {
    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted when the ZK membership gate is (re)configured (constructor and {setZkMembership}).
    event PDA__ZkMembershipConfigured(address indexed verifier, bytes32 indexed membershipRoot, bool enabled);

    /// @notice Emitted when the membership root is rotated via {setMembershipRoot}.
    event PDA__MembershipRootUpdated(bytes32 indexed previousRoot, bytes32 indexed newRoot);

    /// @notice Emitted when a membership-gated vote is accepted (a fresh nullifier was spent).
    event PDA__MembershipVoteCast(uint256 indexed proposalId, bytes32 nullifierHash);

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error PDA__InvalidVerifier();
    error PDA__InvalidMembershipRoot();
    error PDA__FieldElementOutOfRange();
    error PDA__NullifierAlreadyUsed();
    error PDA__InvalidMembershipProof();
    /// @dev Thrown when an un-gated vote entrypoint is used while the ZK gate is enabled.
    error PDA__MembershipProofRequired();
    /// @dev Thrown when a ZK-only action is used while the gate is disabled.
    error PDA__MembershipProofNotEnabled();

    // -----------------------------------------------------------------------
    // Membership gate configuration & introspection
    // -----------------------------------------------------------------------

    /// @notice Whether the optional ZK membership gate is enabled (a verifier is configured).
    function zkMembershipEnabled() external view returns (bool);

    /// @notice The Noir membership-proof verifier, or `address(0)` when the gate is disabled.
    function voteSubmissionVerifier() external view returns (address);

    /// @notice The global DAO membership root, or `bytes32(0)` when the gate is disabled.
    function membershipRoot() external view returns (bytes32);

    /// @notice Whether `nullifierHash` has already been spent on `proposalId`.
    function nullifierUsed(uint256 proposalId, bytes32 nullifierHash) external view returns (bool);

    /// @notice Owner-only: enable, disable, or reconfigure the ZK gate at runtime.
    /// @param verifier A deployed Noir verifier to enable the gate, or `address(0)` to disable it.
    /// @param newMembershipRoot The membership root when enabling; must be `bytes32(0)` when disabling.
    function setZkMembership(address verifier, bytes32 newMembershipRoot) external;

    /// @notice Owner-only: rotate the membership root (only while the gate is enabled).
    function setMembershipRoot(bytes32 newMembershipRoot) external;

    // -----------------------------------------------------------------------
    // Confidential voting
    // -----------------------------------------------------------------------

    /// @notice Cast an encrypted, token-weighted vote after proving DAO membership in zero knowledge.
    /// @param proposalId The proposal being voted on.
    /// @param support The encrypted ballot choice (0 Against / 1 For / 2 Abstain) as an external handle.
    /// @param supportProof The FHE input proof attesting to `support`.
    /// @param nullifierHash The proposal-scoped nullifier emitted by the membership circuit.
    /// @param membershipProof The serialized Noir proof of membership for the current `membershipRoot`.
    /// @dev The circuit's `proposal_id` public input is taken modulo the BN254 field; the off-chain
    ///      prover must derive its `proposal_id` (and nullifier) from the same reduced value.
    function castEncryptedVoteWithMembershipProof(
        uint256 proposalId,
        externalEuint8 support,
        bytes calldata supportProof,
        bytes32 nullifierHash,
        bytes calldata membershipProof
    ) external returns (euint64);

    /// @notice Cast an encrypted vote via the inherited entrypoint. Reverts with
    ///         {PDA__MembershipProofRequired} while the ZK gate is enabled.
    function castEncryptedVote(
        uint256 proposalId,
        externalEuint8 support,
        bytes calldata supportProof
    ) external returns (euint64);

    /// @notice Returns the encrypted Against / For / Abstain tally handles for a proposal.
    function proposalVotes(
        uint256 proposalId
    ) external view returns (euint64 againstVotes, euint64 forVotes, euint64 abstainVotes);

    // -----------------------------------------------------------------------
    // Result decryption lifecycle
    // -----------------------------------------------------------------------

    /// @notice After the deadline, makes the encrypted result booleans publicly decryptable.
    function requestProposalResultDecryption(uint256 proposalId) external;

    /// @notice The encrypted result handles (quorum reached, vote succeeded) for a proposal.
    function encryptedProposalResult(
        uint256 proposalId
    ) external view returns (ebool encryptedQuorumReached, ebool encryptedVoteSucceeded);

    /// @notice Finalizes the result with the KMS-decrypted booleans + proof; resolves {state}.
    /// @param abiEncodedProposalResult abi.encode(bool quorumReached, bool voteSucceeded).
    /// @param decryptionProof The KMS decryption proof, re-verified on-chain.
    function finalizeProposalResult(
        uint256 proposalId,
        bytes memory abiEncodedProposalResult,
        bytes memory decryptionProof
    ) external;

    /// @notice Whether the (finalized) proposal reached quorum. Reverts if not yet finalized.
    function quorumReached(uint256 proposalId) external view returns (bool);

    /// @notice Whether the (finalized) proposal succeeded. Reverts if not yet finalized.
    function voteSucceeded(uint256 proposalId) external view returns (bool);
}
