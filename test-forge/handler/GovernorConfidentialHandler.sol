// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {GovernorTestBase} from "../base/GovernorTestBase.sol";
import {externalEuint8} from "@fhevm/solidity/lib/FHE.sol";

/// @dev Invariant-testing handler for the confidential governance stack. Owns all FHE work
/// (encryption, log processing, decryption) and cleartext ghost state, so the invariant contract can
/// delegate every assertion here. Foundry fuzzes the `act*` functions across a fixed actor set; the
/// `check*` functions are the invariant oracle. See contracts/test/GovernorEdgeCases.md (Part 3).
contract GovernorConfidentialHandler is GovernorTestBase {
    uint256 internal constant NUM_ACTORS = 3;
    uint256 internal constant MAX_PROPOSALS = 5;
    // Keep summed weight well within uint64 so the mock's cleartext supply mirror never overflows.
    uint64 internal constant MAX_WEIGHT = type(uint64).max / 16;

    address[NUM_ACTORS] internal actors;

    struct PInfo {
        uint256 id;
        uint256 snapshot;
        uint256 deadline;
        bool requested;
        bool finalized;
        bool resultQuorum;
        bool resultSucceeded;
        uint64 forSum;
        uint64 againstSum;
        uint64 abstainSum;
        uint64 countedWeight;
        uint256 votedCount;
        mapping(address voter => bool) voted;
    }

    uint256 public proposalCount;
    mapping(uint256 index => PInfo) internal proposals;

    function setUp() public override {
        super.setUp();
        _deployGovernor(4); // 4% quorum

        actors[0] = address(0xA1);
        actors[1] = address(0xA2);
        actors[2] = address(0xA3);
        for (uint256 i; i < NUM_ACTORS; i++) {
            _setVotes(actors[i], uint64(100 + i * 50));
        }

        _createProposal(); // seed one proposal so voting can start immediately
    }

    // --- Fuzz actions ---

    function actCreateProposal(uint256) public {
        if (proposalCount >= MAX_PROPOSALS) return;
        _createProposal();
    }

    function actVote(uint256 actorSeed, uint256 propSeed, uint8 supportSeed) public {
        if (proposalCount == 0) return;
        PInfo storage p = proposals[propSeed % proposalCount];

        // Active window: snapshot < now <= deadline. Avoid calling state(), which reverts past deadline.
        if (block.timestamp <= p.snapshot || block.timestamp > p.deadline) return;

        address actor = actors[actorSeed % NUM_ACTORS];
        uint8 support = supportSeed % 4; // 0,1,2 valid; 3 = spoiled ballot

        if (p.voted[actor]) {
            // I4: a second vote by the same account must revert.
            (externalEuint8 h, bytes memory pf) = encryptUint8(support, actor, address(governor));
            vm.prank(actor);
            try governor.castEncryptedVote(p.id, h, pf) {
                revert("double vote unexpectedly succeeded");
            } catch {}
            return;
        }

        // Weight counted by the governor is the snapshot-time voting power (I5).
        uint64 counted = token.pastVotesCleartext(actor, p.snapshot);

        _castVote(actor, p.id, support);

        p.voted[actor] = true;
        p.votedCount++;
        if (support == VOTE_AGAINST) {
            p.againstSum += counted;
            p.countedWeight += counted;
        } else if (support == VOTE_FOR) {
            p.forSum += counted;
            p.countedWeight += counted;
        } else if (support == VOTE_ABSTAIN) {
            p.abstainSum += counted;
            p.countedWeight += counted;
        }
        // support == 3: weight dropped (I1) — counters untouched, but the voter is recorded above.
    }

    function actWarp(uint256 secondsSeed) public {
        // Cap the step below the active-window width so sequences dwell inside voting windows
        // (and cast votes) rather than skipping straight past the deadline.
        vm.warp(block.timestamp + bound(secondsSeed, 1, VOTING_DELAY));
    }

    /// @notice Jumps time to just past a chosen proposal's deadline, so the request/finalize path is
    /// reachable within a fuzz sequence (capped warps alone rarely accumulate enough to cross it).
    function actCloseVoting(uint256 propSeed) public {
        if (proposalCount == 0) return;
        PInfo storage p = proposals[propSeed % proposalCount];
        if (block.timestamp <= p.deadline) {
            vm.warp(p.deadline + 1);
        }
    }

    function actRequestDecryption(uint256 propSeed) public {
        if (proposalCount == 0) return;
        PInfo storage p = proposals[propSeed % proposalCount];
        if (p.requested) return;
        if (block.timestamp <= p.deadline) return; // not yet votable-closed
        governor.requestProposalResultDecryption(p.id);
        p.requested = true;
    }

    function actFinalize(uint256 propSeed) public {
        if (proposalCount == 0) return;
        PInfo storage p = proposals[propSeed % proposalCount];
        if (!p.requested || p.finalized) return;

        (bool q, bool s) = _completeFinalization(p.id);
        p.finalized = true;
        p.resultQuorum = q;
        p.resultSucceeded = s;

        // SF4 / I11: result must match a recomputation from snapshot-time data.
        assertEq(s, p.forSum > p.againstSum, "voteSucceeded != (for > against)");

        uint64 supplyAtSnapshot = token.pastSupplyCleartext(p.snapshot);
        uint256 numerator = governor.quorumNumerator(p.snapshot);
        uint256 expectedQuorum = (uint256(supplyAtSnapshot) * numerator) / 100;
        bool expectedReached = uint256(p.forSum) + uint256(p.abstainSum) >= expectedQuorum;
        assertEq(q, expectedReached, "quorumReached != (for+abstain >= quorum)");
    }

    function actUpdateNumerator(uint256 numSeed) public {
        vm.prank(address(governor));
        governor.updateQuorumNumerator(bound(numSeed, 0, 100));
    }

    function actSetVotes(uint256 actorSeed, uint256 amountSeed) public {
        _setVotes(actors[actorSeed % NUM_ACTORS], uint64(bound(amountSeed, 0, MAX_WEIGHT)));
    }

    // --- Invariant oracle (called from the invariant contract) ---

    /// @notice SF1/SF3: decrypted tallies equal the ghost sums of in-range weight.
    function checkTallies() external {
        for (uint256 i; i < proposalCount; i++) {
            PInfo storage p = proposals[i];
            (uint64 against, uint64 forV, uint64 abstain) = _decryptVotes(p.id);
            assertEq(forV, p.forSum, "for tally drift");
            assertEq(against, p.againstSum, "against tally drift");
            assertEq(abstain, p.abstainSum, "abstain tally drift");
            assertEq(uint256(forV) + against + abstain, p.countedWeight, "weight conservation");
        }
    }

    /// @notice SF2: on-chain hasVoted matches the ghost vote record exactly.
    function checkVoteAccounting() external view {
        for (uint256 i; i < proposalCount; i++) {
            PInfo storage p = proposals[i];
            uint256 onChainCount;
            for (uint256 j; j < NUM_ACTORS; j++) {
                bool onChain = governor.hasVoted(p.id, actors[j]);
                assertEq(onChain, p.voted[actors[j]], "hasVoted drift");
                if (onChain) onChainCount++;
            }
            assertEq(onChainCount, p.votedCount, "vote count drift");
        }
    }

    /// @notice SF5/I10: a finalized result never changes once set.
    function checkFinalizedImmutable() external view {
        for (uint256 i; i < proposalCount; i++) {
            PInfo storage p = proposals[i];
            if (!p.finalized) continue;
            assertEq(governor.quorumReached(p.id), p.resultQuorum, "quorumReached mutated");
            assertEq(governor.voteSucceeded(p.id), p.resultSucceeded, "voteSucceeded mutated");
        }
    }

    /// @notice SF6/I14: the quorum numerator never exceeds the denominator.
    function checkNumeratorBound() external view {
        assertLe(governor.quorumNumerator(), governor.quorumDenominator(), "numerator > denominator");
    }

    // --- internals ---

    function _createProposal() internal {
        address proposer = actors[proposalCount % NUM_ACTORS];
        string memory description = string(abi.encodePacked("proposal-", vm.toString(proposalCount)));
        uint256 id = _propose(proposer, description);

        PInfo storage p = proposals[proposalCount];
        p.id = id;
        p.snapshot = governor.proposalSnapshot(id);
        p.deadline = governor.proposalDeadline(id);
        proposalCount++;
    }
}
