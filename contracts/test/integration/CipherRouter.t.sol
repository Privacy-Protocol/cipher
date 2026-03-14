// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {CipherTypes} from "../../src/types/CipherTypes.sol";
import {CipherRouter} from "../../src/core/CipherRouter.sol";
import {AdapterRegistry} from "../../src/core/AdapterRegistry.sol";
import {VerifierRegistry} from "../../src/core/VerifierRegistry.sol";
import {NullifierStore} from "../../src/core/NullifierStore.sol";
import {CredentialGateAdapter} from "../../src/adapters/CredentialGateAdapter.sol";
import {VotingAdapter} from "../../src/adapters/VotingAdapter.sol";
import {ICipherVotingSource} from "../../src/interfaces/ICipherVotingSource.sol";
import {HonkVerifier as CredentialGateHonkVerifier} from "../../src/verifiers/CredentialGateVerifier.sol";
import {HonkVerifier as VotingHonkVerifier} from "../../src/verifiers/VotingVerifier.sol";

contract CipherRouterTest is Test {
    event ActionSubmitted(
        bytes32 indexed actionId,
        bytes32 indexed appId,
        bytes32 indexed actionType,
        bytes32 contextId,
        address adapter,
        bytes32 verifierId,
        bytes32 nullifierKey,
        bytes32 payloadHash,
        bytes32 encryptedPayloadRef,
        address sender
    );
    event ContextLinked(
        bytes32 indexed contextId,
        address indexed dao,
        bytes32 indexed externalReference
    );
    event TallySubmitted(
        bytes32 indexed contextId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        bytes32 tallyCommitment,
        address submitter,
        bool finalized
    );

    struct ProofBundle {
        bytes proof;
        bytes32[] publicInputs;
    }

    bytes32 internal constant APP_ID = bytes32(uint256(1001));
    bytes32 internal constant OTHER_APP_ID = bytes32(uint256(1002));

    bytes32 internal constant ACTION_CREDENTIAL_GATE = bytes32(uint256(2001));
    bytes32 internal constant ACTION_PRIVATE_VOTE = bytes32(uint256(2002));
    bytes32 internal constant ACTION_UNKNOWN = bytes32(uint256(2999));

    bytes32 internal constant CREDENTIAL_VERIFIER_ID =
        keccak256("CIPHER_VERIFIER:CREDENTIAL_GATE_HONK:v1");
    bytes32 internal constant VOTING_VERIFIER_ID =
        keccak256("CIPHER_VERIFIER:VOTING_HONK:v1");

    bytes32 internal constant GATE_CONTEXT = bytes32(uint256(3001));
    bytes32 internal constant PROPOSAL_CONTEXT = bytes32(uint256(3002));
    bytes32 internal constant EXTERNAL_PROPOSAL_REF = bytes32(uint256(42));
    bytes32 internal constant TALLY_COMMITMENT = bytes32(uint256(0xABCDEF));

    bytes32 internal constant ROOT_B = bytes32(uint256(0xB0B));
    address internal constant DAO = address(0xDA0);
    address internal constant TALLY_AUTHORITY = address(0xBEEF);
    address internal constant UNAUTHORIZED = address(0xCAFE);

    AdapterRegistry internal adapterRegistry;
    VerifierRegistry internal verifierRegistry;
    NullifierStore internal nullifierStore;
    CipherRouter internal router;

    CredentialGateAdapter internal credentialAdapter;
    VotingAdapter internal votingAdapter;

    CredentialGateHonkVerifier internal credentialVerifier;
    VotingHonkVerifier internal votingVerifier;

    function setUp() public {
        adapterRegistry = new AdapterRegistry(address(this));
        verifierRegistry = new VerifierRegistry(address(this));
        nullifierStore = new NullifierStore(address(this));

        router = new CipherRouter(
            address(this),
            address(adapterRegistry),
            address(verifierRegistry),
            address(nullifierStore)
        );
        nullifierStore.setConsumer(address(router), true);

        credentialAdapter = new CredentialGateAdapter(
            address(this),
            address(router),
            APP_ID,
            ACTION_CREDENTIAL_GATE
        );
        votingAdapter = new VotingAdapter(
            address(this),
            address(router),
            APP_ID,
            ACTION_PRIVATE_VOTE
        );

        adapterRegistry.setAdapter(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            address(credentialAdapter)
        );
        adapterRegistry.setAdapter(
            APP_ID,
            ACTION_PRIVATE_VOTE,
            address(votingAdapter)
        );

        credentialVerifier = new CredentialGateHonkVerifier();
        votingVerifier = new VotingHonkVerifier();

        verifierRegistry.setVerifier(
            CREDENTIAL_VERIFIER_ID,
            address(credentialVerifier),
            router.computeSchemaHash(9),
            9,
            true
        );
        verifierRegistry.setVerifier(
            VOTING_VERIFIER_ID,
            address(votingVerifier),
            router.computeSchemaHash(8),
            8,
            true
        );

        verifierRegistry.setVerifierAllowedForAction(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            CREDENTIAL_VERIFIER_ID,
            true
        );
        verifierRegistry.setVerifierAllowedForAction(
            APP_ID,
            ACTION_PRIVATE_VOTE,
            VOTING_VERIFIER_ID,
            true
        );

        router.setAppEnabled(APP_ID, true);
    }

    function testCredentialGate_SuccessfulRoutingAndEvent() public {
        ProofBundle memory bundle = _generateCredentialProof(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT
        );
        bytes32 root = bundle.publicInputs[5];

        credentialAdapter.configureContext(
            GATE_CONTEXT,
            CredentialGateAdapter.GateContextConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayloadRef: false,
                validAfter: 0,
                validUntil: 0
            })
        );
        credentialAdapter.setAllowedRoot(GATE_CONTEXT, root, true);

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_CREDENTIAL_GATE,
            contextId: GATE_CONTEXT,
            verifierId: CREDENTIAL_VERIFIER_ID,
            bundle: bundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: ""
        });

        bytes32 expectedActionId = router.computeActionId(req, address(this));
        bytes32 expectedNullifierKey = router.computeNullifierKey(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT,
            req.nullifier
        );

        vm.expectEmit(address(router));
        emit ActionSubmitted(
            expectedActionId,
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT,
            address(credentialAdapter),
            CREDENTIAL_VERIFIER_ID,
            expectedNullifierKey,
            req.payloadHash,
            bytes32(0),
            address(this)
        );

        bytes32 actionId = router.submitAction(req);

        assertEq(actionId, expectedActionId);
        assertTrue(nullifierStore.isNullifierUsed(expectedNullifierKey));
    }

    function testReplayPrevention_RevertsOnSecondUse() public {
        ProofBundle memory bundle = _generateCredentialProof(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT
        );
        bytes32 root = bundle.publicInputs[5];

        credentialAdapter.configureContext(
            GATE_CONTEXT,
            CredentialGateAdapter.GateContextConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayloadRef: false,
                validAfter: 0,
                validUntil: 0
            })
        );
        credentialAdapter.setAllowedRoot(GATE_CONTEXT, root, true);

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_CREDENTIAL_GATE,
            contextId: GATE_CONTEXT,
            verifierId: CREDENTIAL_VERIFIER_ID,
            bundle: bundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: ""
        });

        router.submitAction(req);

        bytes32 nullifierKey = router.computeNullifierKey(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT,
            req.nullifier
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                NullifierStore.NullifierAlreadyUsed.selector,
                nullifierKey
            )
        );
        router.submitAction(req);
    }

    function testInvalidAdapter_RevertsWhenActionIsNotRegistered() public {
        CipherTypes.ActionRequest memory req = _buildDummyRequest({
            appId: APP_ID,
            actionType: ACTION_UNKNOWN,
            contextId: GATE_CONTEXT
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CipherRouter.AdapterNotRegistered.selector,
                APP_ID,
                ACTION_UNKNOWN
            )
        );
        router.submitAction(req);
    }

    function testWrongAppId_RevertsWhenAppNotEnabled() public {
        CipherTypes.ActionRequest memory req = _buildDummyRequest({
            appId: OTHER_APP_ID,
            actionType: ACTION_CREDENTIAL_GATE,
            contextId: GATE_CONTEXT
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CipherRouter.AppNotEnabled.selector,
                OTHER_APP_ID
            )
        );
        router.submitAction(req);
    }

    function testWrongActionBinding_RevertsWhenPublicInputMismatches() public {
        ProofBundle memory bundle = _generateCredentialProof(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT
        );
        bytes32 root = bundle.publicInputs[5];

        credentialAdapter.configureContext(
            GATE_CONTEXT,
            CredentialGateAdapter.GateContextConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayloadRef: false,
                validAfter: 0,
                validUntil: 0
            })
        );
        credentialAdapter.setAllowedRoot(GATE_CONTEXT, root, true);

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_CREDENTIAL_GATE,
            contextId: GATE_CONTEXT,
            verifierId: CREDENTIAL_VERIFIER_ID,
            bundle: bundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: ""
        });

        req.publicInputs[1] = ACTION_PRIVATE_VOTE;

        vm.expectRevert(
            abi.encodeWithSelector(
                CipherRouter.PublicInputBindingMismatch.selector,
                uint256(1),
                ACTION_CREDENTIAL_GATE,
                ACTION_PRIVATE_VOTE
            )
        );
        router.submitAction(req);
    }

    function testCredentialAdapterValidation_RevertsForUnknownRoot() public {
        ProofBundle memory bundle = _generateCredentialProof(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT
        );
        bytes32 proofRoot = bundle.publicInputs[5];

        credentialAdapter.configureContext(
            GATE_CONTEXT,
            CredentialGateAdapter.GateContextConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayloadRef: false,
                validAfter: 0,
                validUntil: 0
            })
        );
        credentialAdapter.setAllowedRoot(GATE_CONTEXT, ROOT_B, true);
        assertTrue(proofRoot != ROOT_B);

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_CREDENTIAL_GATE,
            contextId: GATE_CONTEXT,
            verifierId: CREDENTIAL_VERIFIER_ID,
            bundle: bundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CredentialGateAdapter.RootNotAllowed.selector,
                GATE_CONTEXT,
                proofRoot
            )
        );
        router.submitAction(req);
    }

    function testVoting_StoresCommitmentAndInlineEncryptedPayload() public {
        ProofBundle memory bundle = _generateVotingProof(
            APP_ID,
            ACTION_PRIVATE_VOTE,
            PROPOSAL_CONTEXT,
            3,
            1
        );
        bytes32 root = bundle.publicInputs[5];

        votingAdapter.configureProposal(
            PROPOSAL_CONTEXT,
            VotingAdapter.ProposalConfig({
                enabled: true,
                requirePayload: true,
                requireEncryptedPayload: true,
                startTime: uint64(block.timestamp - 1),
                endTime: uint64(block.timestamp + 1 days)
            })
        );
        votingAdapter.setAllowedRoot(PROPOSAL_CONTEXT, root, true);

        bytes memory inlineEncryptedVote = hex"112233445566";

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_PRIVATE_VOTE,
            contextId: PROPOSAL_CONTEXT,
            verifierId: VOTING_VERIFIER_ID,
            bundle: bundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: abi.encode(inlineEncryptedVote)
        });

        bytes32 actionId = router.submitAction(req);

        ICipherVotingSource.VoteRecordView memory voteRecord = votingAdapter
            .getVote(actionId);
        assertEq(voteRecord.proposalId, PROPOSAL_CONTEXT);
        assertEq(voteRecord.root, root);
        assertEq(voteRecord.nullifier, req.nullifier);
        assertEq(voteRecord.payloadHash, req.payloadHash);
        assertEq(voteRecord.encryptedPayloadRef, bytes32(0));
        assertEq(voteRecord.encryptedPayload, inlineEncryptedVote);
        assertEq(voteRecord.submitter, address(this));
        assertEq(votingAdapter.voteCountByProposal(PROPOSAL_CONTEXT), 1);
    }

    function testVoting_CanLinkDaoContextAndDeriveContextId() public {
        bytes32 derivedContextId = votingAdapter.computeContextId(
            DAO,
            EXTERNAL_PROPOSAL_REF
        );

        vm.expectEmit(address(votingAdapter));
        emit ContextLinked(derivedContextId, DAO, EXTERNAL_PROPOSAL_REF);

        votingAdapter.linkContext(derivedContextId, DAO, EXTERNAL_PROPOSAL_REF);

        ICipherVotingSource.ContextLink memory link = votingAdapter
            .getContextLink(derivedContextId);
        assertEq(link.dao, DAO);
        assertEq(link.externalReference, EXTERNAL_PROPOSAL_REF);
        assertTrue(link.linked);
    }

    function testVoting_TallyAuthorityCanSubmitFinalizedTally() public {
        vm.warp(2 days);

        votingAdapter.configureProposal(
            PROPOSAL_CONTEXT,
            VotingAdapter.ProposalConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayload: false,
                startTime: uint64(block.timestamp - 2 days),
                endTime: uint64(block.timestamp - 1 days)
            })
        );
        votingAdapter.setTallyAuthority(TALLY_AUTHORITY);

        vm.prank(TALLY_AUTHORITY);
        vm.expectEmit(address(votingAdapter));
        emit TallySubmitted(
            PROPOSAL_CONTEXT,
            7,
            2,
            1,
            TALLY_COMMITMENT,
            TALLY_AUTHORITY,
            true
        );
        votingAdapter.submitTally(
            PROPOSAL_CONTEXT,
            7,
            2,
            1,
            TALLY_COMMITMENT,
            true
        );

        ICipherVotingSource.ProposalTally memory tally = votingAdapter
            .getTally(PROPOSAL_CONTEXT);
        assertEq(tally.forVotes, 7);
        assertEq(tally.againstVotes, 2);
        assertEq(tally.abstainVotes, 1);
        assertEq(tally.tallyCommitment, TALLY_COMMITMENT);
        assertEq(tally.submitter, TALLY_AUTHORITY);
        assertTrue(tally.finalized);
        assertTrue(votingAdapter.isTallyFinalized(PROPOSAL_CONTEXT));
    }

    function testVoting_TallyRejectsUnauthorizedOrPrematureSubmission() public {
        votingAdapter.configureProposal(
            PROPOSAL_CONTEXT,
            VotingAdapter.ProposalConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayload: false,
                startTime: uint64(block.timestamp - 1),
                endTime: uint64(block.timestamp + 1 days)
            })
        );
        votingAdapter.setTallyAuthority(TALLY_AUTHORITY);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingAdapter.OnlyTallyAuthority.selector,
                UNAUTHORIZED
            )
        );
        votingAdapter.submitTally(PROPOSAL_CONTEXT, 1, 0, 0, bytes32(0), true);

        vm.prank(TALLY_AUTHORITY);
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingAdapter.TallySubmissionTooEarly.selector,
                PROPOSAL_CONTEXT,
                uint64(block.timestamp + 1 days),
                uint64(block.timestamp)
            )
        );
        votingAdapter.submitTally(PROPOSAL_CONTEXT, 1, 0, 0, bytes32(0), true);
    }

    function testVoting_FinalizedTallyCannotBeOverwritten() public {
        vm.warp(2 days);

        votingAdapter.configureProposal(
            PROPOSAL_CONTEXT,
            VotingAdapter.ProposalConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayload: false,
                startTime: uint64(block.timestamp - 2 days),
                endTime: uint64(block.timestamp - 1 days)
            })
        );

        votingAdapter.submitTally(
            PROPOSAL_CONTEXT,
            3,
            1,
            0,
            TALLY_COMMITMENT,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                VotingAdapter.TallyAlreadyFinalized.selector,
                PROPOSAL_CONTEXT
            )
        );
        votingAdapter.submitTally(
            PROPOSAL_CONTEXT,
            4,
            1,
            0,
            bytes32(uint256(0x123)),
            false
        );
    }

    function testVoting_FailsWhenProposalValidationFails() public {
        ProofBundle memory bundle = _generateVotingProof(
            APP_ID,
            ACTION_PRIVATE_VOTE,
            PROPOSAL_CONTEXT,
            3,
            1
        );
        bytes32 root = bundle.publicInputs[5];

        votingAdapter.configureProposal(
            PROPOSAL_CONTEXT,
            VotingAdapter.ProposalConfig({
                enabled: true,
                requirePayload: true,
                requireEncryptedPayload: false,
                startTime: uint64(block.timestamp + 1 days),
                endTime: uint64(block.timestamp + 2 days)
            })
        );
        votingAdapter.setAllowedRoot(PROPOSAL_CONTEXT, root, true);

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_PRIVATE_VOTE,
            contextId: PROPOSAL_CONTEXT,
            verifierId: VOTING_VERIFIER_ID,
            bundle: bundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                VotingAdapter.ProposalNotActive.selector,
                PROPOSAL_CONTEXT,
                uint64(block.timestamp + 1 days),
                uint64(block.timestamp + 2 days),
                uint64(block.timestamp)
            )
        );
        router.submitAction(req);
    }

    function testInvalidProof_RevertsWhenProofIsTampered() public {
        ProofBundle memory bundle = _generateCredentialProof(
            APP_ID,
            ACTION_CREDENTIAL_GATE,
            GATE_CONTEXT
        );
        bytes32 root = bundle.publicInputs[5];

        credentialAdapter.configureContext(
            GATE_CONTEXT,
            CredentialGateAdapter.GateContextConfig({
                enabled: true,
                requirePayload: false,
                requireEncryptedPayloadRef: false,
                validAfter: 0,
                validUntil: 0
            })
        );
        credentialAdapter.setAllowedRoot(GATE_CONTEXT, root, true);

        bytes memory tamperedProof = bytes.concat(bundle.proof);
        tamperedProof[0] = bytes1(uint8(tamperedProof[0]) ^ uint8(0x01));

        ProofBundle memory badBundle = ProofBundle({
            proof: tamperedProof,
            publicInputs: bundle.publicInputs
        });

        CipherTypes.ActionRequest memory req = _buildRequestFromProof({
            appId: APP_ID,
            actionType: ACTION_CREDENTIAL_GATE,
            contextId: GATE_CONTEXT,
            verifierId: CREDENTIAL_VERIFIER_ID,
            bundle: badBundle,
            encryptedPayloadRef: bytes32(0),
            adapterData: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CipherRouter.InvalidProof.selector,
                CREDENTIAL_VERIFIER_ID
            )
        );
        router.submitAction(req);
    }

    function _buildRequestFromProof(
        bytes32 appId,
        bytes32 actionType,
        bytes32 contextId,
        bytes32 verifierId,
        ProofBundle memory bundle,
        bytes32 encryptedPayloadRef,
        bytes memory adapterData
    ) internal view returns (CipherTypes.ActionRequest memory req) {
        require(bundle.publicInputs.length >= 6, "public inputs too short");

        req = CipherTypes.ActionRequest({
            appId: appId,
            actionType: actionType,
            contextId: contextId,
            nullifier: bundle.publicInputs[3],
            payloadHash: bundle.publicInputs[4],
            encryptedPayloadRef: encryptedPayloadRef,
            verifierId: verifierId,
            deadline: uint64(block.timestamp + 1 days),
            publicInputs: bundle.publicInputs,
            proof: bundle.proof,
            adapterData: adapterData
        });
    }

    function _buildDummyRequest(
        bytes32 appId,
        bytes32 actionType,
        bytes32 contextId
    ) internal view returns (CipherTypes.ActionRequest memory req) {
        bytes32[] memory publicInputs = new bytes32[](6);
        publicInputs[0] = appId;
        publicInputs[1] = actionType;
        publicInputs[2] = contextId;
        publicInputs[3] = bytes32(uint256(9999));
        publicInputs[4] = bytes32(0);
        publicInputs[5] = bytes32(uint256(7777));

        req = CipherTypes.ActionRequest({
            appId: appId,
            actionType: actionType,
            contextId: contextId,
            nullifier: publicInputs[3],
            payloadHash: publicInputs[4],
            encryptedPayloadRef: bytes32(0),
            verifierId: CREDENTIAL_VERIFIER_ID,
            deadline: uint64(block.timestamp + 1 days),
            publicInputs: publicInputs,
            proof: hex"01",
            adapterData: ""
        });
    }

    function _generateCredentialProof(
        bytes32 appId,
        bytes32 actionType,
        bytes32 contextId
    ) internal returns (ProofBundle memory bundle) {
        string[] memory inputs = new string[](6);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateCredentialGateProof.ts";
        inputs[3] = vm.toString(appId);
        inputs[4] = vm.toString(actionType);
        inputs[5] = vm.toString(contextId);

        bytes memory result = vm.ffi(inputs);
        (bundle.proof, bundle.publicInputs) = abi.decode(
            result,
            (bytes, bytes32[])
        );
    }

    function _generateVotingProof(
        bytes32 appId,
        bytes32 actionType,
        bytes32 contextId,
        uint8 optionCount,
        uint8 voteOption
    ) internal returns (ProofBundle memory bundle) {
        string[] memory inputs = new string[](8);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateVotingProof.ts";
        inputs[3] = vm.toString(appId);
        inputs[4] = vm.toString(actionType);
        inputs[5] = vm.toString(contextId);
        inputs[6] = vm.toString(optionCount);
        inputs[7] = vm.toString(voteOption);

        bytes memory result = vm.ffi(inputs);
        (bundle.proof, bundle.publicInputs) = abi.decode(
            result,
            (bytes, bytes32[])
        );
    }
}
