// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {GovernorTestBase} from "./base/GovernorTestBase.sol";
import {IVotesConfidential} from "../contracts/contracts/Governance/interfaces/IVotesConfidential.sol";
import {ConfigurableGovernor} from "../contracts/contracts/mocks/ConfigurableGovernor.sol";
import {MockNonClockVotes} from "../contracts/contracts/mocks/MockNonClockVotes.sol";

/// @dev Tests for {GovernorVotesConfidential} token/clock plumbing (plan items, I19).
contract GovernorVotesClockTest is GovernorTestBase {
    function setUp() public override {
        super.setUp();
        _deployGovernor(4);
    }

    function test_token_returnsDeployedToken() public view {
        assertEq(address(governor.token()), address(token));
    }

    function testFuzz_clock_delegatesToToken(uint48 timestamp) public {
        timestamp = uint48(bound(timestamp, 1, type(uint48).max));
        vm.warp(timestamp);
        assertEq(governor.clock(), token.clock());
        assertEq(governor.clock(), timestamp);
    }

    function test_clockMode_delegatesToToken() public view {
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
        assertEq(governor.CLOCK_MODE(), token.CLOCK_MODE());
    }

    // --- ERC-6372 fallback path (token clock() / CLOCK_MODE() revert) ---

    function testFuzz_clock_fallsBackToBlockNumber(uint64 blockNumber) public {
        blockNumber = uint64(bound(blockNumber, 1, type(uint48).max));
        MockNonClockVotes nonClock = new MockNonClockVotes();
        ConfigurableGovernor g = new ConfigurableGovernor(IVotesConfidential(address(nonClock)), 4);

        vm.roll(blockNumber);
        assertEq(g.clock(), blockNumber);
    }

    function test_clockMode_fallsBackToBlockNumberDefault() public {
        MockNonClockVotes nonClock = new MockNonClockVotes();
        ConfigurableGovernor g = new ConfigurableGovernor(IVotesConfidential(address(nonClock)), 4);
        assertEq(g.CLOCK_MODE(), "mode=blocknumber&from=default");
    }
}
