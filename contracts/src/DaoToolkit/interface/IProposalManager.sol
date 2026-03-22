// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title IProposalManager
/// @author Obaloluwa
/// @notice Interface for the ProposalManager contract.
interface IProposalManager {
    //////////////EVENTS///////////////////
    event ProposalCreated(
        uint indexed proposalId,
        uint8 ballotSize,
        uint64 votingPeriod
    );
    event VoteSubmitted(uint indexed proposalId, bytes encryptedVote);
    event VotesTallied(uint indexed proposalId, uint[] voteCounts);

    //////////////ERRORS///////////////////
    error ProposalManager__ProposalAlreadyExists();
    error ProposalManager__InvalidVotingPeriod();
    error ProposalManager__InvalidBallotSize();
    error ProposalManager__VotingPeriodEnded();
    error ProposalManager__ProposalNotExists();
    error ProposalManager__UserAlreadyVoted();

    /// @notice Configuration of a proposal.
    /// @param ballotSize The number of available voting options (e.g., 2: Yes/No, 3: For/Against/Abstain).
    /// @param votingStart The timestamp when voting begins.
    /// @param votingEnd The timestamp when voting ends.
    /// @param exists True if the proposal has been initialized.
    /// @param voteCounts Array storing the total vote weights for each option.
    struct ProposalConfig {
        uint8 ballotSize;
        uint votingStart;
        uint votingEnd;
        bool exists;
        uint[] voteCounts;
    }

    /// @notice Retrieves the basic configuration variables of a stored proposal.
    /// @dev This generated getter exposes the scalar fields of the struct but not the dynamically sized array.
    /// @param _proposalId The ID of the proposal to query.
    /// @return proposal The ProposalConfig of the proposal.
    function getProposalById(
        uint _proposalId
    ) external view returns (ProposalConfig memory proposal);

    /// @notice Creates a new proposal.
    /// @param _proposalId The unique identifier for the new proposal.
    /// @param _ballotSize The number of options available to vote on.
    /// @param _votingPeriod The duration the voting will be open, in seconds.
    /// @return proposal The newly created ProposalConfig representing the initial state.
    function propose(
        uint _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod
    ) external returns (ProposalConfig memory proposal);

    /// @notice Submits a vote (or an encrypted vote logic footprint) for a particular proposal.
    /// @param _proposalId The ID of the proposal being voted on.
    /// @param _encryptedVote The encrypted vote.
    function submitEncryptedVote(
        uint _proposalId,
        bytes calldata _encryptedVote
    ) external;

    /// @notice Displays or calculates the final vote tally for a proposal.
    /// @param _proposalId The ID of the proposal.
    /// @return voteCounts An array containing the aggregated total weights of votes per option.
    function tallyEncryptedVotes(
        uint _proposalId
    ) external returns (uint[] memory voteCounts);
}
