// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {GovernorTestBase} from "./base/GovernorTestBase.sol";
import {IVotesConfidential} from "../contracts/contracts/Governance/interfaces/IVotesConfidential.sol";
import {MockConfidentialVotes} from "./mocks/MockConfidentialVotes.sol";
import {ConfigurableGovernor} from "../contracts/contracts/mocks/ConfigurableGovernor.sol";
import {GovernorVotesQuorumFractionConfidential} from
    "../contracts/contracts/Governance/GovernorVotesQuorumFractionConfidential.sol";

/// @dev Stateless fuzz tests for {GovernorVotesQuorumFractionConfidential} (plan items S1–S5, I14–I18).
contract GovernorQuorumFractionTest is GovernorTestBase {
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);

    address internal holder = address(0x101DE2);

    function setUp() public override {
        super.setUp();
        _deployGovernor(4);
    }

    // --- S1: constructor numerator bound (I14) ---

    function testFuzz_constructor_rejectsNumeratorAboveDenominator(uint256 numerator) public {
        numerator = bound(numerator, 101, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(GovernorVotesQuorumFractionConfidential.GovernorInvalidQuorumFraction.selector, numerator, 100)
        );
        new ConfigurableGovernor(IVotesConfidential(address(token)), numerator);
    }

    function testFuzz_constructor_acceptsValidNumerator(uint256 numerator) public {
        numerator = bound(numerator, 0, 100);
        ConfigurableGovernor g = new ConfigurableGovernor(IVotesConfidential(address(token)), numerator);
        assertEq(g.quorumNumerator(), numerator);
    }

    // --- S2/S3: confidentialQuorum math and the euint128 -> euint64 narrowing (I15) ---

    function testFuzz_confidentialQuorum_matchesFormula(uint64 supply, uint256 numerator) public {
        numerator = bound(numerator, 0, 100);

        MockConfidentialVotes t = new MockConfidentialVotes();
        ConfigurableGovernor g = new ConfigurableGovernor(IVotesConfidential(address(t)), numerator);
        t.setGovernor(address(g));

        // Establish a total supply at the current clock, then advance so the lookup is a past one.
        t.setVotes(holder, supply);
        uint256 timepoint = block.timestamp;
        vm.warp(block.timestamp + 1);

        uint64 q = decrypt(g.confidentialQuorum(timepoint));

        // The product supply*numerator fits in 128 bits and, since numerator <= 100, the quotient is
        // <= supply <= type(uint64).max, so the narrowing to euint64 must never truncate.
        uint256 expected = (uint256(supply) * numerator) / 100;
        assertEq(uint256(q), expected, "quorum != floor(supply*num/100)");
        assertLe(uint256(q), uint256(supply), "quorum exceeds supply");
    }

    function test_confidentialQuorum_zeroSupplyIsZero() public {
        // No checkpoints at all -> getPastTotalSupply returns an uninitialized handle (cleartext 0).
        uint64 q = decrypt(governor.confidentialQuorum(block.timestamp));
        assertEq(uint256(q), 0);
    }

    // --- S4: quorum(timepoint) always reverts ---

    function testFuzz_quorum_alwaysReverts(uint256 timepoint) public {
        vm.expectRevert(GovernorVotesQuorumFractionConfidential.GovernorConfidentialQuorumIsEncrypted.selector);
        governor.quorum(timepoint);
    }

    // --- S5: denominator constant ---

    function test_quorumDenominator_is100() public view {
        assertEq(governor.quorumDenominator(), 100);
    }

    // --- updateQuorumNumerator governance gate (I18) ---

    function testFuzz_updateQuorumNumerator_nonGovernanceReverts(address caller, uint256 numerator) public {
        vm.assume(caller != address(governor));
        numerator = bound(numerator, 0, 100);
        vm.expectRevert(); // GovernorOnlyExecutor(caller)
        vm.prank(caller);
        governor.updateQuorumNumerator(numerator);
    }

    function testFuzz_updateQuorumNumerator_viaGovernance(uint256 numerator) public {
        numerator = bound(numerator, 0, 100);
        uint256 old = governor.quorumNumerator();

        vm.expectEmit(true, true, true, true, address(governor));
        emit QuorumNumeratorUpdated(old, numerator);

        vm.prank(address(governor));
        governor.updateQuorumNumerator(numerator);

        assertEq(governor.quorumNumerator(), numerator);
    }

    function testFuzz_updateQuorumNumerator_rejectsAboveDenominator(uint256 numerator) public {
        numerator = bound(numerator, 101, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(GovernorVotesQuorumFractionConfidential.GovernorInvalidQuorumFraction.selector, numerator, 100)
        );
        vm.prank(address(governor));
        governor.updateQuorumNumerator(numerator);
    }

    // --- Historical numerator lookup (I16/I17) ---

    function testFuzz_quorumNumerator_historicalLookup(uint256 first, uint256 second) public {
        first = bound(first, 0, 100);
        second = bound(second, 0, 100);

        // Deploy a governor whose initial numerator is `first` (checkpoint at deploy time t0).
        vm.warp(block.timestamp + 10);
        ConfigurableGovernor g = new ConfigurableGovernor(IVotesConfidential(address(token)), first);
        uint256 t0 = block.timestamp;

        // Update to `second` at a strictly later time t1.
        vm.warp(block.timestamp + 100);
        uint256 t1 = block.timestamp;
        vm.prank(address(g));
        g.updateQuorumNumerator(second);

        // After the latest update -> latest value (optimistic path).
        assertEq(g.quorumNumerator(t1), second, "at/after update");
        assertEq(g.quorumNumerator(t1 + 50), second, "after update");
        // Before the latest update -> historical value (binary-search path).
        assertEq(g.quorumNumerator(t0), first, "at first checkpoint");
        assertEq(g.quorumNumerator(t1 - 1), first, "just before update");
    }
}
