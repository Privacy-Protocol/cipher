//SPDX-License-Identifier:MIT
pragma solidity ^0.8.33;

import {IProposalManager} from "./interface/IProposalManager.sol";

/// @title ProposalManager
/// @author Obaloluwa
/// @notice Stores config for each proposal.``
contract ProposalManager is IProposalManager {
    // bytes32 membershipRoot;          // Merkle root of eligible voters
    // bytes32 tallyEncryptionKeyRef;   // Ref/hash/id for tally pubkey or params
    // RevealMode revealMode;           // final only or live aggregate

    mapping(uint => ProposalConfig) public proposals;

    function propose(
        uint _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod
    ) external returns (ProposalConfig memory proposal) {
        if (proposals[_proposalId].exists) {
            revert ProposalManager__ProposalAlreadyExists();
        }

        if (_votingPeriod == 0) {
            revert ProposalManager__InvalidVotingPeriod();
        }

        if (_ballotSize == 0) {
            revert ProposalManager__InvalidBallotSize();
        }

        proposals[_proposalId] = ProposalConfig({
            ballotSize: _ballotSize,
            votingStart: block.timestamp,
            votingEnd: block.timestamp + _votingPeriod,
            voteCounts: new uint[](_ballotSize),
            exists: true
        });

        emit ProposalCreated(_proposalId, _ballotSize, _votingPeriod);

        return proposals[_proposalId];
    }

    //function to submit encrypted vote
    function submitEncryptedVote(uint _proposalId, uint8 voteOption) external {
        if (!proposals[_proposalId].exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp > proposals[_proposalId].votingEnd) {
            revert ProposalManager__VotingPeriodEnded();
        }

        // TODO: adjust this later after MVP
        uint8 voterWeight = 1;

        proposals[_proposalId].voteCounts[voteOption] += voterWeight;

        emit VoteSubmitted(_proposalId, voteOption);

        // TODO: add logic to check if the voter has already voted
        // TODO: add logic to check if the voter is eligible to vote
    }

    //function to count encrypted vote
    function tallyEncryptedVotes(
        uint _proposalId
    ) external returns (uint[] memory voteCounts) {
        if (!proposals[_proposalId].exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp < proposals[_proposalId].votingEnd) {
            revert ProposalManager__VotingPeriodEnded();
        }

        voteCounts = proposals[_proposalId].voteCounts;

        emit VotesTallied(_proposalId, voteCounts);
    }

    function getProposalById(
        uint _proposalId
    ) external view returns (ProposalConfig memory proposal) {
        if (!proposals[_proposalId].exists) {
            revert ProposalManager__ProposalNotExists();
        }

        return proposals[_proposalId];
    }
}
