// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {GovernorTestBase} from "./base/GovernorTestBase.sol";
import {FHE, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @dev Stateless fuzz tests for {GovernorConfidential} core entry points (plan items S10–S13, I7–I13).
contract GovernorConfidentialCoreTest is GovernorTestBase {
    // Mirrors of the events under test (only `voter` is indexed).
    event EncryptedVoteCast(address indexed voter, uint256 proposalId, euint8 encryptedSupport, euint64 weight, string reason);
    event EncryptedVoteCastWithParams(
        address indexed voter, uint256 proposalId, euint8 encryptedSupport, euint64 weight, string reason, bytes params
    );

    uint256 internal constant ALICE_PK = 0xA11CE;
    uint256 internal constant MALLORY_PK = 0xBAD;
    address internal alice = vm.addr(ALICE_PK);
    address internal mallory = vm.addr(MALLORY_PK);

    function setUp() public override {
        super.setUp();
        _deployGovernor(4);
        _setVotes(alice, 100);
    }

    // --- S10: every cleartext entry point reverts (I12) ---

    function testFuzz_getVotes_reverts(address account, uint256 timepoint) public {
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__NormalGetVotesNotSupported()"));
        governor.getVotes(account, timepoint);
    }

    function testFuzz_castVote_reverts(uint256 proposalId, uint8 support) public {
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__NormalVotesNotSupported()"));
        governor.castVote(proposalId, support);
    }

    function testFuzz_castVoteWithReason_reverts(uint256 proposalId, uint8 support, string calldata reason) public {
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__NormalVotesNotSupported()"));
        governor.castVoteWithReason(proposalId, support, reason);
    }

    function testFuzz_castVoteWithReasonAndParams_reverts(uint256 proposalId, uint8 support, bytes calldata params)
        public
    {
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__NormalVotesNotSupported()"));
        governor.castVoteWithReasonAndParams(proposalId, support, "", params);
    }

    function testFuzz_castVoteBySig_validSigStillReverts(uint256 proposalId, uint8 support) public {
        // A *valid* cleartext signature passes the sig check, then hits the cleartext-rejection revert.
        bytes memory sig = _signCleartextBallot(ALICE_PK, proposalId, support, alice);
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__NormalVotesNotSupported()"));
        governor.castVoteBySig(proposalId, support, alice, sig);
    }

    function testFuzz_castVoteWithReasonAndParamsBySig_validSigStillReverts(uint256 proposalId, uint8 support) public {
        bytes memory sig = _signCleartextExtendedBallot(ALICE_PK, proposalId, support, alice, "", "");
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__NormalVotesNotSupported()"));
        governor.castVoteWithReasonAndParamsBySig(proposalId, support, alice, "", "", sig);
    }

    // --- S11: encrypted signature voting (I13) ---

    function test_castEncryptedVoteBySig_validSignature() public {
        uint256 proposalId = _propose(alice, "sig vote");
        _activate(proposalId);

        // The FHE input proof binds to the submitter (msg.sender) — here the test contract — while the
        // EIP-712 ballot signature authorizes the vote on alice's behalf.
        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, address(governor));
        bytes memory sig = _signEncryptedBallot(ALICE_PK, proposalId, handle, proof, alice);

        uint256 nonceBefore = governor.nonces(alice);
        governor.castEncryptedVoteBySig(proposalId, handle, alice, sig, proof);

        assertTrue(governor.hasVoted(proposalId, alice));
        assertEq(governor.nonces(alice), nonceBefore + 1, "nonce consumed exactly once");
    }

    function test_castEncryptedVoteBySig_wrongSignerReverts() public {
        uint256 proposalId = _propose(alice, "sig vote bad");
        _activate(proposalId);

        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, alice, address(governor));
        // Signed by mallory but claims to be alice.
        bytes memory sig = _signEncryptedBallot(MALLORY_PK, proposalId, handle, proof, alice);

        vm.expectRevert(abi.encodeWithSignature("GovernorInvalidSignature(address)", alice));
        governor.castEncryptedVoteBySig(proposalId, handle, alice, sig, proof);
    }

    function test_castEncryptedVoteBySig_replayReverts() public {
        uint256 proposalId = _propose(alice, "sig vote replay");
        _activate(proposalId);

        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, address(governor));
        bytes memory sig = _signEncryptedBallot(ALICE_PK, proposalId, handle, proof, alice);
        governor.castEncryptedVoteBySig(proposalId, handle, alice, sig, proof);

        // Nonce advanced -> same signature no longer recovers a valid signer.
        vm.expectRevert(abi.encodeWithSignature("GovernorInvalidSignature(address)", alice));
        governor.castEncryptedVoteBySig(proposalId, handle, alice, sig, proof);
    }

    function test_castEncryptedVoteWithReasonAndParamsBySig_valid() public {
        uint256 proposalId = _propose(alice, "ext sig vote");
        _activate(proposalId);

        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, address(governor));
        bytes memory params = hex"abcd";
        bytes memory sig = _signEncryptedExtendedBallot(ALICE_PK, proposalId, handle, proof, alice, "reason", params);

        governor.castEncryptedVoteWithReasonAndParamsBySig(proposalId, handle, alice, "reason", params, sig, proof);
        assertTrue(governor.hasVoted(proposalId, alice));
    }

    // --- S12: params.length selects which event is emitted ---

    function test_emptyParams_emitsEncryptedVoteCast() public {
        uint256 proposalId = _propose(alice, "empty params");
        _activate(proposalId);

        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, alice, address(governor));
        vm.expectEmit(true, false, false, false, address(governor));
        emit EncryptedVoteCast(alice, proposalId, euint8.wrap(bytes32(0)), euint64.wrap(bytes32(0)), "");

        vm.prank(alice);
        governor.castEncryptedVoteWithReasonAndParams(proposalId, handle, "r", "", proof);
    }

    function test_nonEmptyParams_emitsEncryptedVoteCastWithParams() public {
        uint256 proposalId = _propose(alice, "non-empty params");
        _activate(proposalId);

        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, alice, address(governor));
        vm.expectEmit(true, false, false, false, address(governor));
        emit EncryptedVoteCastWithParams(alice, proposalId, euint8.wrap(bytes32(0)), euint64.wrap(bytes32(0)), "", hex"01");

        vm.prank(alice);
        governor.castEncryptedVoteWithReasonAndParams(proposalId, handle, "r", hex"01", proof);
    }

    // --- S13: lifecycle guards on unknown proposals (I7–I10) ---

    function testFuzz_unknownProposal_guards(uint256 proposalId) public {
        vm.expectRevert(abi.encodeWithSignature("GovernorNonexistentProposal(uint256)", proposalId));
        governor.requestProposalResultDecryption(proposalId);

        vm.expectRevert(
            abi.encodeWithSignature("GovernorConfidential__ResultDecryptionNotRequested(uint256)", proposalId)
        );
        governor.finalizeProposalResult(proposalId, "", "");

        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__ResultNotFinalized(uint256)", proposalId));
        governor.quorumReached(proposalId);

        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__ResultNotFinalized(uint256)", proposalId));
        governor.voteSucceeded(proposalId);
    }

    // --- Result lifecycle sequencing (I8, I9, I10) ---

    function test_requestBeforeDeadline_reverts() public {
        uint256 proposalId = _propose(alice, "still active");
        _activate(proposalId);
        vm.expectRevert(
            abi.encodeWithSignature("GovernorConfidential__ProposalStillActive(uint256)", proposalId)
        );
        governor.requestProposalResultDecryption(proposalId);
    }

    function test_requestTwice_reverts() public {
        uint256 proposalId = _propose(alice, "request twice");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR);
        _advancePastDeadline(proposalId);

        governor.requestProposalResultDecryption(proposalId);
        vm.expectRevert(
            abi.encodeWithSignature("GovernorConfidential__ResultAlreadyRequested(uint256)", proposalId)
        );
        governor.requestProposalResultDecryption(proposalId);
    }

    function test_finalizeTwice_reverts() public {
        uint256 proposalId = _propose(alice, "finalize twice");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR);
        _advancePastDeadline(proposalId);
        _finalize(proposalId);

        // A second finalize with any payload reverts as already finalized.
        vm.expectRevert(
            abi.encodeWithSignature("GovernorConfidential__ResultAlreadyFinalized(uint256)", proposalId)
        );
        governor.finalizeProposalResult(proposalId, abi.encode(true, true), "");
    }

    function test_viewsRevertBeforeFinalization() public {
        uint256 proposalId = _propose(alice, "not finalized");
        _activate(proposalId);
        _castVote(alice, proposalId, VOTE_FOR);
        _advancePastDeadline(proposalId);
        governor.requestProposalResultDecryption(proposalId);

        // Requested but not finalized: result views and state() still revert.
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__ResultNotFinalized(uint256)", proposalId));
        governor.quorumReached(proposalId);
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__ResultNotFinalized(uint256)", proposalId));
        governor.voteSucceeded(proposalId);
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__ResultNotFinalized(uint256)", proposalId));
        governor.state(proposalId);
    }

    // --- State-machine enforcement on encrypted voting (plan 21/22) ---

    function test_voteWhilePending_reverts() public {
        uint256 proposalId = _propose(alice, "pending vote");
        // Not activated: still Pending.
        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, alice, address(governor));
        // current state = Pending (0); expected bitmap = 1 << uint8(Active) = 2.
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector, proposalId, uint256(0), bytes32(uint256(2))
            )
        );
        vm.prank(alice);
        governor.castEncryptedVote(proposalId, handle, proof);
    }

    function test_voteAfterDeadline_revertsResultNotFinalized() public {
        uint256 proposalId = _propose(alice, "late vote");
        _activate(proposalId);
        _advancePastDeadline(proposalId);

        // Past the deadline, _validateStateBitmap -> state() -> _quorumReached() reverts first.
        (externalEuint8 handle, bytes memory proof) = encryptUint8(VOTE_FOR, alice, address(governor));
        vm.expectRevert(abi.encodeWithSignature("GovernorConfidential__ResultNotFinalized(uint256)", proposalId));
        vm.prank(alice);
        governor.castEncryptedVote(proposalId, handle, proof);
    }
}
