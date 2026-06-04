// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {GovernorTestBase} from "./base/GovernorTestBase.sol";

/// @dev Stateless fuzz tests for {GovernorCountingSimpleConfidential} (plan items S6–S9, I1/I2/I11).
contract GovernorCountingTest is GovernorTestBase {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    // Keep summed weights within uint64 so the mock's cleartext supply mirror never overflows.
    uint64 internal constant MAX_WEIGHT = type(uint64).max / 4;

    function setUp() public override {
        super.setUp();
        _deployGovernor(4);
    }

    function test_countingMode() public view {
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain");
    }

    function test_proposalVotes_beforeAnyVote_areUninitialized() public {
        uint256 proposalId = _propose(alice, "no votes yet");
        (uint64 against, uint64 forV, uint64 abstain) = _decryptVotes(proposalId);
        assertEq(against, 0);
        assertEq(forV, 0);
        assertEq(abstain, 0);
    }

    // --- S6/S7: support routing + weight fidelity, incl. the spoiled-ballot weight-drop edge (I1) ---

    function testFuzz_supportRouting(uint8 support, uint64 weight) public {
        weight = uint64(bound(weight, 1, MAX_WEIGHT));
        _setVotes(alice, weight);

        uint256 proposalId = _propose(alice, "routing");
        _activate(proposalId);
        _castVote(alice, proposalId, support);

        (uint64 against, uint64 forV, uint64 abstain) = _decryptVotes(proposalId);

        if (support == VOTE_AGAINST) {
            assertEq(against, weight, "against");
            assertEq(forV, 0);
            assertEq(abstain, 0);
        } else if (support == VOTE_FOR) {
            assertEq(forV, weight, "for");
            assertEq(against, 0);
            assertEq(abstain, 0);
        } else if (support == VOTE_ABSTAIN) {
            assertEq(abstain, weight, "abstain");
            assertEq(against, 0);
            assertEq(forV, 0);
        } else {
            // Support outside {0,1,2}: the FHE.select branches all miss, so the weight is dropped
            // entirely (spoiled ballot). The voter is still marked as having voted.
            assertEq(against, 0, "drop against");
            assertEq(forV, 0, "drop for");
            assertEq(abstain, 0, "drop abstain");
            assertTrue(governor.hasVoted(proposalId, alice));
        }
    }

    // --- S8: voteSucceeded is a strict for > against comparison, incl. the tie (I11) ---

    function testFuzz_voteSucceeded_strictGreaterThan(uint64 forWeight, uint64 againstWeight) public {
        forWeight = uint64(bound(forWeight, 1, MAX_WEIGHT));
        againstWeight = uint64(bound(againstWeight, 1, MAX_WEIGHT));

        _setVotes(alice, forWeight);
        _setVotes(bob, againstWeight);

        uint256 proposalId = _propose(alice, "success comparison");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR);
        _castVote(bob, proposalId, VOTE_AGAINST);
        _advancePastDeadline(proposalId);

        (, bool voteSucceeded) = _finalize(proposalId);
        assertEq(voteSucceeded, forWeight > againstWeight, "succeeded == (for > against)");
    }

    function test_voteSucceeded_tieFails() public {
        _setVotes(alice, 1000);
        _setVotes(bob, 1000);

        uint256 proposalId = _propose(alice, "exact tie");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR);
        _castVote(bob, proposalId, VOTE_AGAINST);
        _advancePastDeadline(proposalId);

        (, bool voteSucceeded) = _finalize(proposalId);
        assertFalse(voteSucceeded, "tie must not succeed");
    }

    // --- S9: quorum is an inclusive for+abstain >= floor(supply*num/100) threshold (I11) ---

    function testFuzz_quorumThreshold(uint64 forWeight, uint64 extraSupply, uint256 numerator) public {
        numerator = bound(numerator, 0, 100);
        forWeight = uint64(bound(forWeight, 1, MAX_WEIGHT));
        extraSupply = uint64(bound(extraSupply, 0, MAX_WEIGHT));

        // Redeploy with the fuzzed numerator.
        _deployGovernor(numerator);

        _setVotes(alice, forWeight); // votes FOR
        _setVotes(bob, extraSupply); // holds weight but never votes (inflates total supply)

        uint256 proposalId = _propose(alice, "quorum threshold");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR);
        _advancePastDeadline(proposalId);

        (bool quorumReached,) = _finalize(proposalId);

        uint256 totalSupply = uint256(forWeight) + uint256(extraSupply);
        uint256 expectedQuorum = (totalSupply * numerator) / 100;
        bool expectedReached = uint256(forWeight) >= expectedQuorum; // FHE.le is inclusive
        assertEq(quorumReached, expectedReached, "quorumReached == (for+abstain >= quorum)");
    }

    /// @dev Exact-threshold case: for+abstain == quorum must reach quorum (FHE.le is inclusive).
    /// Random fuzzing rarely lands on exact equality, so this boundary is pinned deterministically.
    function test_quorum_exactThreshold_isInclusive() public {
        _deployGovernor(100); // quorum numerator 100 -> quorum == total supply
        _setVotes(alice, 50); // sole holder; supply == 50 == quorum

        uint256 proposalId = _propose(alice, "exact threshold");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR); // for == 50 == quorum
        _advancePastDeadline(proposalId);

        (bool quorumReached,) = _finalize(proposalId);
        assertTrue(quorumReached, "for+abstain == quorum must reach quorum");
    }

    // --- abstain counts toward quorum (plan CountingSimple #4) ---

    function test_abstainOnly_canReachQuorum() public {
        // numerator 4, supply 100 -> quorum 4; an abstain of 10 alone clears it.
        _deployGovernor(4);
        _setVotes(alice, 10);
        _setVotes(bob, 90); // non-voting supply

        uint256 proposalId = _propose(alice, "abstain quorum");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_ABSTAIN);
        _advancePastDeadline(proposalId);

        (bool quorumReached, bool voteSucceeded) = _finalize(proposalId);
        assertTrue(quorumReached, "abstain should reach quorum");
        assertFalse(voteSucceeded, "abstain alone does not succeed (for == against == 0)");
    }
}
