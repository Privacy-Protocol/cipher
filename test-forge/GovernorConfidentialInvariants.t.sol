// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GovernorConfidentialHandler} from "./handler/GovernorConfidentialHandler.sol";

/// @dev Stateful invariant suite for the confidential governance stack (plan Part 3, SF1–SF6).
/// The handler owns all FHE work and ghost state; each invariant delegates to it.
contract GovernorConfidentialInvariantsTest is StdInvariant, Test {
    GovernorConfidentialHandler internal handler;

    function setUp() public {
        handler = new GovernorConfidentialHandler();
        handler.setUp();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.actCreateProposal.selector;
        selectors[1] = handler.actVote.selector;
        selectors[2] = handler.actWarp.selector;
        selectors[3] = handler.actRequestDecryption.selector;
        selectors[4] = handler.actFinalize.selector;
        selectors[5] = handler.actUpdateNumerator.selector;
        selectors[6] = handler.actSetVotes.selector;
        selectors[7] = handler.actCloseVoting.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_tallyConservation() public {
        handler.checkTallies();
    }

    function invariant_voteAccounting() public view {
        handler.checkVoteAccounting();
    }

    function invariant_finalizedResultImmutable() public view {
        handler.checkFinalizedImmutable();
    }

    function invariant_numeratorBound() public view {
        handler.checkNumeratorBound();
    }

    /// @dev Scripted drive-through of the handler's action surface, proving the guarded actions reach
    /// the vote/request/finalize path (and its inline correctness assertions) rather than no-op'ing.
    function test_scriptedLifecycle_exercisesFinalize() public {
        handler.actWarp(7300); // past proposal 0's snapshot (1 + 7200)
        handler.actVote(0, 0, 1); // actor0 FOR
        handler.actVote(1, 0, 1); // actor1 FOR
        handler.actVote(2, 0, 0); // actor2 AGAINST

        handler.checkTallies();
        handler.checkVoteAccounting();

        handler.actWarp(60000); // past the deadline
        handler.actRequestDecryption(0);
        handler.actFinalize(0); // runs SF4/I11 assertions internally

        handler.checkFinalizedImmutable();
        handler.checkTallies();
    }
}
