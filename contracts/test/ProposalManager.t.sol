// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {ProposalManager} from "../src/DaoToolkit/ProposalMananger.sol";
import {
    IProposalManager
} from "../src/DaoToolkit/interface/IProposalManager.sol";

contract ProposalManagerTest is Test {
    ProposalManager public proposalManager;

    function setUp() public {
        proposalManager = new ProposalManager();
    }

    function test_Propose() public {
        uint proposalId = 1;
        uint8 ballotSize = 2; // Yes, No
        uint64 votingPeriod = 1 days;

        proposalManager.propose(proposalId, ballotSize, votingPeriod);

        (
            uint8 fetchedBallotSize,
            uint fetchedVotingStart,
            uint fetchedVotingEnd,
            bool exists
        ) = proposalManager.proposals(proposalId);

        assertTrue(exists);
        assertEq(fetchedBallotSize, ballotSize);
        assertEq(fetchedVotingStart, block.timestamp);
        assertEq(fetchedVotingEnd, block.timestamp + votingPeriod);
    }

    function test_SubmitEncryptedVote() public {
        uint proposalId = 1;
        uint8 ballotSize = 2; // Yes, No
        uint64 votingPeriod = 1 days;

        proposalManager.propose(proposalId, ballotSize, votingPeriod);

        uint8 voteOption = 0; // Yes
        proposalManager.submitEncryptedVote(proposalId, voteOption);

        // Fast forward block time past the voting period to allow tallying
        vm.warp(block.timestamp + votingPeriod + 1);

        uint[] memory voteCounts = proposalManager.tallyEncryptedVotes(
            proposalId
        );
        assertEq(voteCounts.length, 2);
        assertEq(voteCounts[0], 1);
        assertEq(voteCounts[1], 0);
    }

    function test_TallyEncryptedVotes() public {
        uint proposalId = 1;
        uint8 ballotSize = 3; // For, Against, Abstain
        uint64 votingPeriod = 7 days;

        proposalManager.propose(proposalId, ballotSize, votingPeriod);

        // Vote
        proposalManager.submitEncryptedVote(proposalId, 0); // For
        proposalManager.submitEncryptedVote(proposalId, 0); // For
        proposalManager.submitEncryptedVote(proposalId, 1); // Against

        // Try tallying before period ends, should revert
        vm.expectRevert(
            IProposalManager.ProposalManager__VotingPeriodEnded.selector
        );
        proposalManager.tallyEncryptedVotes(proposalId);

        // Fast forward to after voting period
        vm.warp(block.timestamp + votingPeriod + 1);

        uint[] memory voteCounts = proposalManager.tallyEncryptedVotes(
            proposalId
        );

        assertEq(voteCounts.length, 3);
        assertEq(voteCounts[0], 2); // 2 For votes
        assertEq(voteCounts[1], 1); // 1 Against vote
        assertEq(voteCounts[2], 0); // 0 Abstain votes
    }
}
