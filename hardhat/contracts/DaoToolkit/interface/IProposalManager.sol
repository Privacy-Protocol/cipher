// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {euint8, euint64} from "@fhevm/solidity/lib/FHE.sol";

/// @title IProposalManager
/// @author Obaloluwa
/// @notice Interface for the ProposalManager contract.
interface IProposalManager {
    //////////////EVENTS///////////////////
    /// @notice Emitted when a new proposal is created.
    /// @param proposalId The ID of the newly created proposal.
    /// @param ballotSize The number of available voting options.
    /// @param votingPeriod The duration the voting will be open, in seconds.
    event ProposalCreated(uint indexed proposalId, uint8 ballotSize, uint64 votingPeriod);

    /// @notice Emitted when a user submits an encrypted vote for a proposal.
    /// @param proposalId The ID of the proposal being voted on.
    event VoteSubmitted(uint indexed proposalId);

    /// @notice Emitted when the voting period for a proposal ends.
    /// @param proposalId The ID of the proposal.
    event VotingEnded(uint indexed proposalId);

    /// @notice Emitted when the results of a live proposal are revealed.
    /// @param proposalId The ID of the proposal.
    /// @param decryptedTallies The decrypted results of the voting.
    event AggregateResultsRevealed(uint indexed proposalId, uint64[] indexed decryptedTallies);

    /// @notice Emitted when the results of a closed proposal are revealed.
    /// @param proposalId The ID of the proposal.
    /// @param voteCounts The decrypted results of the voting.
    event FinalResultsRevealed(uint indexed proposalId, uint[] indexed voteCounts);

    //////////////ERRORS///////////////////
    error ProposalManager__ProposalAlreadyExists();
    error ProposalManager__InvalidVotingPeriod();
    error ProposalManager__InvalidBallotSize();
    error ProposalManager__VotingPeriodEnded();
    error ProposalManager__ProposalNotExists();
    error ProposalManager__NullifierAlreadyUsed();
    error ProposalManager__VotingPeriodNotEnded();
    error ProposalManager__InvalidMembershipRoot();
    error ProposalManager__InvalidVoteProof();

    /// @notice Configuration of a proposal.
    /// @param ballotSize The number of available voting options (e.g., 2: Yes/No, 3: For/Against/Abstain).
    /// @param votingStart The timestamp when voting begins.
    /// @param votingEnd The timestamp when voting ends.
    /// @param membershipRoot The fixed membership root used by the vote-verification circuit.
    /// @param exists True if the proposal has been initialized.
    /// @param voteCounts Array storing the total vote weights for each option.
    struct ProposalConfig {
        uint8 ballotSize;
        uint votingStart;
        uint votingEnd;
        bytes32 membershipRoot;
        bool exists;
        bool allowLiveReveal;
        uint[] voteCounts;
    }

    /// @notice Retrieves the basic configuration variables of a stored proposal.
    /// @dev This generated getter exposes the scalar fields of the struct but not the dynamically sized array.
    /// @param _proposalId The ID of the proposal to query.
    /// @return proposal The ProposalConfig of the proposal.
    function getProposalById(uint _proposalId) external view returns (ProposalConfig memory proposal);

    /// @notice Creates a new proposal.
    /// @param _proposalId The unique identifier for the new proposal.
    /// @param _ballotSize The number of options available to vote on.
    /// @param _votingPeriod The duration the voting will be open, in seconds.
    /// @param _membershipRoot The DAO membership root used for vote proofs on this proposal.
    /// @return proposal The newly created ProposalConfig representing the initial state.
    function propose(
        uint _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod,
        bool _allowLiveReveal,
        bytes32 _membershipRoot
    ) external returns (ProposalConfig memory proposal);

    /// @notice Submits an encrypted vote and a nullifier-backed membership proof for a particular proposal.
    /// @param _proposalId The ID of the proposal being voted on.
    /// @param _nullifierHash The proposal-scoped nullifier emitted by the vote-verification circuit.
    /// @param _zkProof The serialized Noir proof bytes. The verifier integration is stubbed for now.
    /// @param voteData The ABI-encoded tuple of (bytes32 encryptedVote, bytes voteProof).
    function submitEncryptedVote(
        uint _proposalId,
        bytes32 _nullifierHash,
        bytes calldata _zkProof,
        bytes calldata voteData
    ) external;

    /// @notice Ends the voting period for a proposal, makes the encrypted tallies publicly decryptable, and reveals the results.
    /// @param _proposalId The ID of the proposal to end voting on.
    /// @param abiEncodedResults The KMS plaintexts encoded results.
    /// @param decryptionProof The KMS decryption proof.
    function endVoting(uint _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof) external;

    /// @notice Reveals the current encrypted tallies for a live proposal.
    /// @param _proposalId The ID of the proposal to retrieve the encrypted tallies for.
    /// @param abiEncodedResults The KMS plaintexts encoded results.
    /// @param decryptionProof The KMS decryption proof.
    /// @return decryptedTallies The decrypted tallies for the proposal.
    function revealAggregateTallies(
        uint _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) external returns (uint64[] memory decryptedTallies);
}
