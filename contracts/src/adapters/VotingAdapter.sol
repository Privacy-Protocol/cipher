// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseAdapter} from "./BaseAdapter.sol";
import {CipherTypes} from "../types/CipherTypes.sol";
import {ICipherVotingSource} from "../interfaces/ICipherVotingSource.sol";
import {ContextIdLib} from "../utils/ContextIdLib.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract VotingAdapter is BaseAdapter, ICipherVotingSource, Ownable {
    error ProposalDisabled(bytes32 contextId);
    error ProposalNotActive(
        bytes32 contextId,
        uint64 startTime,
        uint64 endTime,
        uint64 nowTs
    );
    error RootNotAllowed(bytes32 contextId, bytes32 root);
    error PayloadRequired(bytes32 contextId);
    error EncryptedPayloadRequired(bytes32 contextId);
    error VoteAlreadyStored(bytes32 actionId);
    error InvalidPublicInputsForVote();
    error OnlyTallyAuthority(address caller);
    error TallyAlreadyFinalized(bytes32 contextId);
    error TallySubmissionTooEarly(
        bytes32 contextId,
        uint64 endTime,
        uint64 nowTs
    );

    struct ProposalConfig {
        bool enabled;
        bool requirePayload;
        bool requireEncryptedPayload;
        uint64 startTime;
        uint64 endTime;
    }

    struct VoteRecord {
        bytes32 proposalId;
        bytes32 root;
        bytes32 nullifier;
        bytes32 payloadHash;
        bytes32 encryptedPayloadRef;
        bytes encryptedPayload;
        address submitter;
        uint64 submittedAt;
    }

    bytes32 public immutable actionType;
    address public tallyAuthority;

    mapping(bytes32 contextId => ProposalConfig config) public proposalConfig;
    mapping(bytes32 contextId => mapping(bytes32 root => bool allowed))
        public allowedRoots;
    mapping(bytes32 actionId => VoteRecord record) private _voteByActionId;
    mapping(bytes32 contextId => uint256 count) public voteCountByProposal;
    mapping(bytes32 contextId => ICipherVotingSource.ProposalTally tally)
        private _tallyByContextId;
    mapping(bytes32 contextId => ICipherVotingSource.ContextLink link)
        private _contextLinkById;

    event ProposalConfigured(
        bytes32 indexed contextId,
        bool enabled,
        bool requirePayload,
        bool requireEncryptedPayload,
        uint64 startTime,
        uint64 endTime
    );

    event RootConfigured(
        bytes32 indexed contextId,
        bytes32 indexed root,
        bool allowed
    );

    event VoteStored(
        bytes32 indexed actionId,
        bytes32 indexed contextId,
        bytes32 indexed root,
        bytes32 nullifier,
        bytes32 payloadHash,
        bytes32 encryptedPayloadRef,
        bytes32 encryptedPayloadDigest,
        address submitter
    );
    event TallyAuthoritySet(address indexed authority);
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

    constructor(
        address initialOwner,
        address router_,
        bytes32 appId_,
        bytes32 actionType_
    ) BaseAdapter(router_, appId_) Ownable(initialOwner) {
        actionType = actionType_;
    }

    modifier onlyTallyAuthority() {
        if (msg.sender != owner() && msg.sender != tallyAuthority) {
            revert OnlyTallyAuthority(msg.sender);
        }
        _;
    }

    function supportsActionType(
        bytes32 actionType_
    ) public view override returns (bool) {
        return actionType_ == actionType;
    }

    function configureProposal(
        bytes32 contextId,
        ProposalConfig calldata config
    ) external onlyOwner {
        proposalConfig[contextId] = config;
        emit ProposalConfigured(
            contextId,
            config.enabled,
            config.requirePayload,
            config.requireEncryptedPayload,
            config.startTime,
            config.endTime
        );
    }

    function setAllowedRoot(
        bytes32 contextId,
        bytes32 root,
        bool allowed
    ) external onlyOwner {
        allowedRoots[contextId][root] = allowed;
        emit RootConfigured(contextId, root, allowed);
    }

    function setTallyAuthority(address authority) external onlyOwner {
        tallyAuthority = authority;
        emit TallyAuthoritySet(authority);
    }

    function linkContext(
        bytes32 contextId,
        address dao,
        bytes32 externalReference
    ) external onlyOwner {
        _contextLinkById[contextId] = ICipherVotingSource.ContextLink({
            dao: dao,
            externalReference: externalReference,
            linked: dao != address(0)
        });

        emit ContextLinked(contextId, dao, externalReference);
    }

    function submitTally(
        bytes32 contextId,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        bytes32 tallyCommitment,
        bool finalize
    ) external onlyTallyAuthority {
        ProposalConfig memory config = proposalConfig[contextId];
        if (!config.enabled) revert ProposalDisabled(contextId);

        uint64 nowTs = uint64(block.timestamp);
        if (config.endTime != 0 && nowTs <= config.endTime) {
            revert TallySubmissionTooEarly(contextId, config.endTime, nowTs);
        }

        ICipherVotingSource.ProposalTally memory currentTally = _tallyByContextId[
            contextId
        ];
        if (currentTally.finalized) revert TallyAlreadyFinalized(contextId);

        _tallyByContextId[contextId] = ICipherVotingSource.ProposalTally({
            forVotes: forVotes,
            againstVotes: againstVotes,
            abstainVotes: abstainVotes,
            tallyCommitment: tallyCommitment,
            submitter: msg.sender,
            submittedAt: nowTs,
            finalized: finalize
        });

        emit TallySubmitted(
            contextId,
            forVotes,
            againstVotes,
            abstainVotes,
            tallyCommitment,
            msg.sender,
            finalize
        );
    }

    function getVote(
        bytes32 actionId
    ) public view returns (ICipherVotingSource.VoteRecordView memory) {
        VoteRecord memory record = _voteByActionId[actionId];
        return
            ICipherVotingSource.VoteRecordView({
                proposalId: record.proposalId,
                root: record.root,
                nullifier: record.nullifier,
                payloadHash: record.payloadHash,
                encryptedPayloadRef: record.encryptedPayloadRef,
                encryptedPayload: record.encryptedPayload,
                submitter: record.submitter,
                submittedAt: record.submittedAt
            });
    }

    function getProposalConfig(
        bytes32 contextId
    ) external view returns (ICipherVotingSource.ProposalConfigView memory) {
        ProposalConfig memory config = proposalConfig[contextId];
        return
            ICipherVotingSource.ProposalConfigView({
                enabled: config.enabled,
                requirePayload: config.requirePayload,
                requireEncryptedPayload: config.requireEncryptedPayload,
                startTime: config.startTime,
                endTime: config.endTime
            });
    }

    function getTally(
        bytes32 contextId
    ) external view returns (ICipherVotingSource.ProposalTally memory) {
        return _tallyByContextId[contextId];
    }

    function isTallyFinalized(bytes32 contextId) external view returns (bool) {
        return _tallyByContextId[contextId].finalized;
    }

    function getContextLink(
        bytes32 contextId
    ) external view returns (ICipherVotingSource.ContextLink memory) {
        return _contextLinkById[contextId];
    }

    function computeContextId(
        address dao,
        bytes32 externalReference
    ) external view returns (bytes32) {
        return ContextIdLib.deriveDaoContextId(dao, externalReference);
    }

    function onVerifiedAction(
        CipherTypes.VerifiedAction calldata action
    ) external override onlyRouter returns (bytes4) {
        if (!supportsActionType(action.actionType))
            revert UnsupportedActionType(action.actionType);

        ProposalConfig memory config = proposalConfig[action.contextId];
        if (!config.enabled) revert ProposalDisabled(action.contextId);

        uint64 nowTs = uint64(block.timestamp);
        if (
            (config.startTime != 0 && nowTs < config.startTime) ||
            (config.endTime != 0 && nowTs > config.endTime)
        ) {
            revert ProposalNotActive(
                action.contextId,
                config.startTime,
                config.endTime,
                nowTs
            );
        }

        if (action.publicInputs.length < 6) revert InvalidPublicInputsForVote();
        bytes32 root = action.publicInputs[5];
        if (!allowedRoots[action.contextId][root])
            revert RootNotAllowed(action.contextId, root);

        if (config.requirePayload && action.payloadHash == bytes32(0))
            revert PayloadRequired(action.contextId);

        bytes memory encryptedPayload = _decodeEncryptedPayload(
            action.adapterData
        );
        bool hasEncryptedPayload = encryptedPayload.length > 0 ||
            action.encryptedPayloadRef != bytes32(0);
        if (config.requireEncryptedPayload && !hasEncryptedPayload)
            revert EncryptedPayloadRequired(action.contextId);

        if (_voteByActionId[action.actionId].submittedAt != 0)
            revert VoteAlreadyStored(action.actionId);

        _voteByActionId[action.actionId] = VoteRecord({
            proposalId: action.contextId,
            root: root,
            nullifier: action.nullifier,
            payloadHash: action.payloadHash,
            encryptedPayloadRef: action.encryptedPayloadRef,
            encryptedPayload: encryptedPayload,
            submitter: action.sender,
            submittedAt: action.timestamp
        });

        unchecked {
            voteCountByProposal[action.contextId] += 1;
        }

        emit VoteStored(
            action.actionId,
            action.contextId,
            root,
            action.nullifier,
            action.payloadHash,
            action.encryptedPayloadRef,
            keccak256(encryptedPayload),
            action.sender
        );

        return ADAPTER_OK;
    }

    function _decodeEncryptedPayload(
        bytes memory adapterData
    ) internal pure returns (bytes memory) {
        if (adapterData.length == 0) return "";

        // Adapter data format v1: abi.encode(bytes encryptedPayload)
        return abi.decode(adapterData, (bytes));
    }
}
