// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {euint8, euint64} from "@fhevm/solidity/lib/FHE.sol";

/// @title IPrivateDaoAdapter
/// @author Obaloluwa
/// @notice Interface for the PrivateDaoAdapter contract.
interface IPrivateDaoAdapter {
    //////////////EVENTS///////////////////
    /// @notice Emitted when a new proposal is created.
    /// @param proposalId The ID of the newly created proposal.
    /// @param ballotSize The number of available voting options.
    /// @param votingPeriod The duration the voting will be open, in seconds.
    event PDA__ProposalCreated(uint256 indexed proposalId, uint8 ballotSize, uint64 votingPeriod);

    /// @notice Emitted when a user submits an encrypted vote for a proposal.
    /// @param proposalId The ID of the proposal being voted on.
    event PDA__VoteSubmitted(uint256 indexed proposalId);

    /// @notice Emitted when the voting period for a proposal ends.
    /// @param proposalId The ID of the proposal.
    event PDA__VotingEnded(uint256 indexed proposalId);

    event PDA__ProposalCreatorUpdated(address indexed previousProposalCreator, address indexed newProposalCreator);
    event PDA__FinalizerUpdated(address indexed previousFinalizer, address indexed newFinalizer);

    /// @notice Emitted when the current encrypted tallies are returned.
    /// @param proposalId The ID of the proposal.
    /// @param encryptedTallies The current encrypted tally handles.
    event PDA__AggregateResultsRevealed(uint256 indexed proposalId, bytes32[] encryptedTallies);

    /// @notice Emitted when the results of a closed proposal are revealed.
    /// @param proposalId The ID of the proposal.
    /// @param revealedTallies The decrypted results of the voting.
    event PDA__FinalResultsRevealed(uint256 indexed proposalId, uint64[] indexed revealedTallies);

    //////////////ERRORS///////////////////
    error PDA__ProposalAlreadyExists();
    error PDA__InvalidVotingPeriod();
    error PDA__InvalidBallotSize();
    error PDA__VotingPeriodEnded();
    error PDA__ProposalNotExists();
    error PDA__NullifierAlreadyUsed();
    error PDA__VotingPeriodNotEnded();
    error PDA__InvalidMembershipRoot();
    error PDA__InvalidVoteData();
    error PDA__InvalidDecryptedTalliesLength();
    error PDA__VotingPeriodNotStarted();
    error PDA__LiveRevealNotAllowed();
    error PDA__VotingAlreadyEnded();
    error PDA__Unauthorized();
    error PDA__InvalidAddress();
    error PDA__InvalidVerifier();
    error PDA__FieldElementOutOfRange();
    error PDA__ResultsNotRevealed();

    /// @notice Configuration of a proposal.
    /// @param ballotSize The number of available voting options (e.g., 2: Yes/No, 3: For/Against/Abstain).
    /// @param votingStart The timestamp when voting begins.
    /// @param votingEnd The timestamp when voting ends.
    /// @param membershipRoot The fixed membership root used by the vote-verification circuit.
    /// @param ended True once final vote revelation has been executed.
    /// @param exists True if the proposal has been initialized.
    struct ProposalConfig {
        uint8 ballotSize;
        uint256 votingStart;
        uint256 votingEnd;
        bytes32 membershipRoot;
        bool ended;
        bool exists;
        bool allowLiveReveal;
    }

    /// @notice Retrieves the basic configuration variables of a stored proposal.
    /// @dev This generated getter exposes the scalar fields of the struct but not the dynamically sized array.
    /// @param _proposalId The ID of the proposal to query.
    /// @return proposal The ProposalConfig of the proposal.
    function getProposalById(uint256 _proposalId) external view returns (ProposalConfig memory proposal);

    /// @notice Creates a new proposal.
    /// @param _proposalId The unique identifier for the new proposal.
    /// @param _ballotSize The number of options available to vote on.
    /// @param _votingPeriod The duration the voting will be open, in seconds.
    /// @param _membershipRoot The DAO membership root used for vote proofs on this proposal.
    /// @return proposal The newly created ProposalConfig representing the initial state.
    function propose(
        uint256 _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod,
        bool _allowLiveReveal,
        bytes32 _membershipRoot
    ) external returns (ProposalConfig memory proposal);

    /// @notice Submits an encrypted vote and a nullifier-backed membership proof for a particular proposal.
    /// @param _proposalId The ID of the proposal being voted on.
    /// @param _nullifierHash The proposal-scoped nullifier emitted by the vote-verification circuit.
    /// @param _zkProof The serialized Noir proof bytes proving membership, nullifier correctness,
    /// and range validity of a hidden vote witness. This proof does not currently bind that witness to voteData.
    /// @param voteData The ABI-encoded tuple of (bytes32 encryptedVote, bytes voteProof).
    function submitEncryptedVote(
        uint256 _proposalId,
        bytes32 _nullifierHash,
        bytes calldata _zkProof,
        bytes calldata voteData
    ) external;

    /// @notice Ends the voting period for a proposal, makes the encrypted tallies publicly decryptable.
    /// @param _proposalId The ID of the proposal to end voting on.
    /// @param abiEncodedResults The KMS plaintexts encoded results.
    /// @param decryptionProof The KMS decryption proof.
    function endVoting(uint256 _proposalId, bytes calldata abiEncodedResults, bytes calldata decryptionProof)
        external;

    /// @notice Returns the current encrypted tally handles for a proposal without changing decryptability.
    /// @param _proposalId The ID of the proposal to retrieve the encrypted tallies for.
    /// @return currentEncryptedTallies The current encrypted tally handles for the proposal.
    function getCurrentEncryptedTallies(
        uint256 _proposalId
    ) external view returns (bytes32[] memory currentEncryptedTallies);

    /// @notice Retrieves the latest revealed tallies for a proposal.
    /// @param _proposalId The ID of the proposal to query.
    /// @return tallies The most recently revealed tallies.
    function getRevealedTallies(uint256 _proposalId) external view returns (uint64[] memory tallies);
}
