// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {externalEuint8, euint64} from "@fhevm/solidity/lib/FHE.sol";

import {IVotesConfidential} from "../Governance/interfaces/IVotesConfidential.sol";
import {GovernorCountingSimpleConfidential} from "../Governance/GovernorCountingSimpleConfidential.sol";
import {GovernorVotesConfidential} from "../Governance/GovernorVotesConfidential.sol";
import {GovernorVotesQuorumFractionConfidential} from "../Governance/GovernorVotesQuorumFractionConfidential.sol";
import {GovernorConfidential} from "../Governance/GovernorConfidential.sol";
import {IVerifier} from "./VoteSubmissionVerifier.sol";

/// @title PrivateDaoAdapter
/// @author Obaloluwa
/// @notice A confidential OpenZeppelin-style Governor that is private (FHE-encrypted ballots) by
///         default, with an OPTIONAL zero-knowledge membership gate.
///
///         - ZK disabled (no verifier, zero root): behaves like {MyGovernor}; members vote with
///           the inherited `castEncryptedVote*` entrypoints. Confidentiality still holds;
///           eligibility is purely token-weight based.
///         - ZK enabled (a real verifier + non-zero membership root): the inherited un-gated
///           entrypoints are disabled and every vote must go through
///           {castEncryptedVoteWithMembershipProof}, supplying a Noir proof of membership in the
///           Poseidon merkle tree plus a one-time nullifier.
///
///         Voting weight is always token-sourced and the vote is bound to `msg.sender`; the proof
///         only proves the caller belongs to the DAO member set. The gate can be configured at
///         deployment and re-configured at runtime by the owner via {setZkMembership}.
/// @dev    Toggling the gate is an owner action that changes which vote path is valid; do it
///         between proposals, not while one is in its active voting window.
contract PrivateDaoAdapter is
    ZamaEthereumConfig,
    GovernorConfidential,
    GovernorCountingSimpleConfidential,
    GovernorVotesConfidential,
    GovernorVotesQuorumFractionConfidential,
    Ownable,
    ReentrancyGuard
{
    /// @dev BN254 scalar field order. Public inputs handed to the verifier must be canonical (< this).
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @notice The Noir membership-proof verifier, or `address(0)` when the ZK gate is disabled.
    IVerifier public voteSubmissionVerifier;

    /// @notice Single global DAO membership root used by every proposal's vote proofs.
    ///         Zero (and unused) when the ZK gate is disabled.
    bytes32 public membershipRoot;

    /// @notice Tracks spent nullifiers per proposal so one DAO member cannot vote twice
    ///         (e.g. from multiple addresses) on the same proposal.
    mapping(uint256 proposalId => mapping(bytes32 nullifierHash => bool used)) public nullifierUsed;

    event PDA__MembershipRootUpdated(bytes32 indexed previousRoot, bytes32 indexed newRoot);
    event PDA__MembershipVoteCast(uint256 indexed proposalId, bytes32 nullifierHash);
    event PDA__ZkMembershipConfigured(address indexed verifier, bytes32 indexed membershipRoot, bool enabled);

    error PDA__InvalidVerifier();
    error PDA__InvalidMembershipRoot();
    error PDA__FieldElementOutOfRange();
    error PDA__NullifierAlreadyUsed();
    error PDA__InvalidMembershipProof();
    error PDA__MembershipProofRequired();
    error PDA__MembershipProofNotEnabled();

    /// @param _token The confidential votes token (voting weight source).
    /// @param _voteSubmissionVerifier The Noir membership verifier to enable the ZK gate, or
    ///        `address(0)` to deploy a plain confidential DAO with the ZK gate disabled.
    /// @param _membershipRoot The initial membership root when ZK is enabled; must be `bytes32(0)`
    ///        when ZK is disabled.
    constructor(
        IVotesConfidential _token,
        address _voteSubmissionVerifier,
        bytes32 _membershipRoot
    )
        GovernorConfidential("PrivateDaoAdapter")
        GovernorVotesConfidential(address(_token))
        GovernorVotesQuorumFractionConfidential(4)
        Ownable(msg.sender)
    {
        _configureZkMembership(_voteSubmissionVerifier, _membershipRoot);
    }

    /// @notice Whether the optional ZK membership gate is enabled (a verifier is configured).
    function zkMembershipEnabled() public view returns (bool) {
        return address(voteSubmissionVerifier) != address(0);
    }

    /// @notice Enables, disables, or reconfigures the ZK membership gate at runtime.
    /// @param _voteSubmissionVerifier A deployed Noir verifier to enable the gate, or `address(0)`
    ///        to disable it.
    /// @param _membershipRoot The membership root to use when enabling; must be `bytes32(0)` when
    ///        disabling.
    /// @dev See the contract notice: change the gate between proposals, not during active voting.
    function setZkMembership(address _voteSubmissionVerifier, bytes32 _membershipRoot) external onlyOwner {
        _configureZkMembership(_voteSubmissionVerifier, _membershipRoot);
    }

    /// @dev Shared validation for the constructor and {setZkMembership}. A non-zero verifier (with
    ///      code) plus a non-zero canonical root enables the gate; a zero verifier with a zero root
    ///      disables it. Any other combination is a misconfiguration and reverts.
    function _configureZkMembership(address _voteSubmissionVerifier, bytes32 _membershipRoot) internal {
        if (_voteSubmissionVerifier != address(0)) {
            if (_voteSubmissionVerifier.code.length == 0) revert PDA__InvalidVerifier();
            if (_membershipRoot == bytes32(0)) revert PDA__InvalidMembershipRoot();
            _requireCanonicalField(_membershipRoot);

            voteSubmissionVerifier = IVerifier(_voteSubmissionVerifier);
            membershipRoot = _membershipRoot;

            emit PDA__ZkMembershipConfigured(_voteSubmissionVerifier, _membershipRoot, true);
        } else {
            // A membership root without a verifier is a misconfiguration.
            if (_membershipRoot != bytes32(0)) revert PDA__InvalidMembershipRoot();

            voteSubmissionVerifier = IVerifier(address(0));
            membershipRoot = bytes32(0);

            emit PDA__ZkMembershipConfigured(address(0), bytes32(0), false);
        }
    }

    function votingDelay() public pure override returns (uint256) {
        return 7200; // 1 day
    }

    function votingPeriod() public pure override returns (uint256) {
        return 50400; // 1 week
    }

    /// @notice Updates the global DAO membership root (e.g. after the member set changes).
    /// @dev Only callable when the ZK gate is enabled.
    function setMembershipRoot(bytes32 _membershipRoot) external onlyOwner {
        if (!zkMembershipEnabled()) revert PDA__MembershipProofNotEnabled();
        if (_membershipRoot == bytes32(0)) revert PDA__InvalidMembershipRoot();
        _requireCanonicalField(_membershipRoot);

        bytes32 previousRoot = membershipRoot;
        membershipRoot = _membershipRoot;

        emit PDA__MembershipRootUpdated(previousRoot, _membershipRoot);
    }

    /// @notice Casts an encrypted, token-weighted vote after proving DAO membership.
    /// @param proposalId The proposal being voted on.
    /// @param support The encrypted ballot choice (Against / For / Abstain) as an external handle.
    /// @param supportProof The FHE input proof attesting to `support`.
    /// @param nullifierHash The proposal-scoped nullifier emitted by the membership circuit.
    /// @param membershipProof The serialized Noir proof of membership for `membershipRoot`.
    /// @dev The circuit's `proposal_id` public input is taken modulo the BN254 field, so the
    ///      off-chain prover must derive its `proposal_id` (and therefore the nullifier) from the
    ///      same reduced value.
    function castEncryptedVoteWithMembershipProof(
        uint256 proposalId,
        externalEuint8 support,
        bytes calldata supportProof,
        bytes32 nullifierHash,
        bytes calldata membershipProof
    ) external nonReentrant returns (euint64) {
        if (!zkMembershipEnabled()) revert PDA__MembershipProofNotEnabled();
        _verifyMembership(proposalId, nullifierHash, membershipProof);

        return _castEncryptedVote(proposalId, _msgSender(), support, supportProof, "");
    }

    function _verifyMembership(uint256 proposalId, bytes32 nullifierHash, bytes calldata membershipProof) internal {
        _requireCanonicalField(nullifierHash);
        if (nullifierUsed[proposalId][nullifierHash]) revert PDA__NullifierAlreadyUsed();

        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = bytes32(proposalId % SNARK_SCALAR_FIELD);
        publicInputs[1] = membershipRoot;
        publicInputs[2] = nullifierHash;

        if (!voteSubmissionVerifier.verify(membershipProof, publicInputs)) {
            revert PDA__InvalidMembershipProof();
        }

        nullifierUsed[proposalId][nullifierHash] = true;

        emit PDA__MembershipVoteCast(proposalId, nullifierHash);
    }

    function _requireCanonicalField(bytes32 value) internal pure {
        if (uint256(value) >= SNARK_SCALAR_FIELD) revert PDA__FieldElementOutOfRange();
    }

    // ------------------------------------------------------------------------
    // Inherited un-gated vote entrypoints. When the ZK gate is enabled, voting MUST go through
    // {castEncryptedVoteWithMembershipProof} so the membership proof is enforced, and these revert.
    // When the ZK gate is disabled, they pass through to the plain confidential governor.
    // ------------------------------------------------------------------------

    function castEncryptedVote(
        uint256 proposalId,
        externalEuint8 support,
        bytes calldata supportProof
    ) public virtual override returns (euint64) {
        if (zkMembershipEnabled()) revert PDA__MembershipProofRequired();
        return super.castEncryptedVote(proposalId, support, supportProof);
    }

    function castEncryptedVoteWithReason(
        uint256 proposalId,
        externalEuint8 support,
        string calldata reason,
        bytes calldata supportProof
    ) public virtual override returns (euint64) {
        if (zkMembershipEnabled()) revert PDA__MembershipProofRequired();
        return super.castEncryptedVoteWithReason(proposalId, support, reason, supportProof);
    }

    function castEncryptedVoteWithReasonAndParams(
        uint256 proposalId,
        externalEuint8 support,
        string calldata reason,
        bytes memory params,
        bytes calldata supportProof
    ) public virtual override returns (euint64) {
        if (zkMembershipEnabled()) revert PDA__MembershipProofRequired();
        return super.castEncryptedVoteWithReasonAndParams(proposalId, support, reason, params, supportProof);
    }

    function castEncryptedVoteBySig(
        uint256 proposalId,
        externalEuint8 support,
        address voter,
        bytes memory signature,
        bytes calldata supportProof
    ) public virtual override returns (euint64) {
        if (zkMembershipEnabled()) revert PDA__MembershipProofRequired();
        return super.castEncryptedVoteBySig(proposalId, support, voter, signature, supportProof);
    }

    function castEncryptedVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        externalEuint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature,
        bytes calldata supportProof
    ) public virtual override returns (euint64) {
        if (zkMembershipEnabled()) revert PDA__MembershipProofRequired();
        return
            super.castEncryptedVoteWithReasonAndParamsBySig(
                proposalId,
                support,
                voter,
                reason,
                params,
                signature,
                supportProof
            );
    }
}
