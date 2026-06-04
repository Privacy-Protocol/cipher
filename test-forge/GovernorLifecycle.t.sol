// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {GovernorTestBase} from "./base/GovernorTestBase.sol";

/// @dev Smoke test: validates the full deploy → mint votes → propose → vote → finalize machinery
/// before the property suites build on it. Mirrors the TypeScript happy-path test.
contract GovernorLifecycleTest is GovernorTestBase {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    function setUp() public override {
        super.setUp();
        _deployGovernor(4); // 4% quorum, as in MyGovernor

        _setVotes(alice, 10);
        _setVotes(bob, 20);
        _setVotes(carol, 5);
    }

    function test_happyPath_forWins() public {
        uint256 proposalId = _propose(alice, "fund the initiative");
        _activate(proposalId);

        _castVote(alice, proposalId, VOTE_FOR);
        _castVote(bob, proposalId, VOTE_FOR);
        _castVote(carol, proposalId, VOTE_AGAINST);

        assertTrue(governor.hasVoted(proposalId, alice));
        assertTrue(governor.hasVoted(proposalId, bob));
        assertTrue(governor.hasVoted(proposalId, carol));

        (uint64 against, uint64 forV, uint64 abstain) = _decryptVotes(proposalId);
        assertEq(forV, 30, "for");
        assertEq(against, 5, "against");
        assertEq(abstain, 0, "abstain");

        _advancePastDeadline(proposalId);

        (bool quorumReached, bool voteSucceeded) = _finalize(proposalId);
        assertTrue(quorumReached, "quorum");
        assertTrue(voteSucceeded, "succeeded");

        assertTrue(governor.quorumReached(proposalId));
        assertTrue(governor.voteSucceeded(proposalId));
        // ProposalState.Succeeded == 4
        assertEq(uint256(governor.state(proposalId)), 4);
    }
}
