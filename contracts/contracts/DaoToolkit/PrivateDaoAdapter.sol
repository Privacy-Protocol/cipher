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
/// @notice A confidential OpenZeppelin-style Governor where every encrypted vote is gated by a
///         Noir zero-knowledge proof of DAO membership (Poseidon merkle tree) plus a one-time
///         nullifier. Voting weight is still token-sourced and the vote is bound to `msg.sender`,
///         exactly like {MyGovernor}; the proof only proves the caller belongs to the DAO member set.
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

    IVerifier public immutable voteSubmissionVerifier;

    /// @notice Single global DAO membership root used by every proposal's vote proofs.
    bytes32 public membershipRoot;

    /// @notice Tracks spent nullifiers per proposal so one DAO member cannot vote twice
    ///         (e.g. from multiple addresses) on the same proposal.
    mapping(uint256 proposalId => mapping(bytes32 nullifierHash => bool used)) public nullifierUsed;

    event PDA__MembershipRootUpdated(bytes32 indexed previousRoot, bytes32 indexed newRoot);
    event PDA__MembershipVoteCast(uint256 indexed proposalId, bytes32 nullifierHash);

    error PDA__InvalidAddress();
    error PDA__InvalidVerifier();
    error PDA__InvalidMembershipRoot();
    error PDA__FieldElementOutOfRange();
    error PDA__NullifierAlreadyUsed();
    error PDA__InvalidMembershipProof();
    error PDA__MembershipProofRequired();

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
        if (_voteSubmissionVerifier == address(0)) revert PDA__InvalidAddress();
        if (_voteSubmissionVerifier.code.length == 0) revert PDA__InvalidVerifier();
        if (_membershipRoot == bytes32(0)) revert PDA__InvalidMembershipRoot();
        _requireCanonicalField(_membershipRoot);

        voteSubmissionVerifier = IVerifier(_voteSubmissionVerifier);
        membershipRoot = _membershipRoot;
    }

    function votingDelay() public pure override returns (uint256) {
        return 7200; // 1 day
    }

    function votingPeriod() public pure override returns (uint256) {
        return 50400; // 1 week
    }

    /// @notice Updates the global DAO membership root (e.g. after the member set changes).
    function setMembershipRoot(bytes32 _membershipRoot) external onlyOwner {
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
    // Disable the inherited un-gated vote entrypoints. Voting MUST go through
    // {castEncryptedVoteWithMembershipProof} so the membership proof is enforced.
    // ------------------------------------------------------------------------

    function castEncryptedVote(uint256, externalEuint8, bytes calldata) public virtual override returns (euint64) {
        revert PDA__MembershipProofRequired();
    }

    function castEncryptedVoteWithReason(
        uint256,
        externalEuint8,
        string calldata,
        bytes calldata
    ) public virtual override returns (euint64) {
        revert PDA__MembershipProofRequired();
    }

    function castEncryptedVoteWithReasonAndParams(
        uint256,
        externalEuint8,
        string calldata,
        bytes memory,
        bytes calldata
    ) public virtual override returns (euint64) {
        revert PDA__MembershipProofRequired();
    }

    function castEncryptedVoteBySig(
        uint256,
        externalEuint8,
        address,
        bytes memory,
        bytes calldata
    ) public virtual override returns (euint64) {
        revert PDA__MembershipProofRequired();
    }

    function castEncryptedVoteWithReasonAndParamsBySig(
        uint256,
        externalEuint8,
        address,
        string calldata,
        bytes memory,
        bytes memory,
        bytes calldata
    ) public virtual override returns (euint64) {
        revert PDA__MembershipProofRequired();
    }
}
