// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ICipherVotingSource {
    struct ProposalConfigView {
        bool enabled;
        bool requirePayload;
        bool requireEncryptedPayload;
        uint64 startTime;
        uint64 endTime;
    }

    struct VoteRecordView {
        bytes32 proposalId;
        bytes32 root;
        bytes32 nullifier;
        bytes32 payloadHash;
        bytes32 encryptedPayloadRef;
        bytes encryptedPayload;
        address submitter;
        uint64 submittedAt;
    }

    struct ProposalTally {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bytes32 tallyCommitment;
        address submitter;
        uint64 submittedAt;
        bool finalized;
    }

    struct ContextLink {
        address dao;
        bytes32 externalReference;
        bool linked;
    }

    function getProposalConfig(
        bytes32 contextId
    ) external view returns (ProposalConfigView memory);

    function voteCountByProposal(
        bytes32 contextId
    ) external view returns (uint256);

    function getVote(
        bytes32 actionId
    ) external view returns (VoteRecordView memory);

    function getTally(
        bytes32 contextId
    ) external view returns (ProposalTally memory);

    function isTallyFinalized(bytes32 contextId) external view returns (bool);

    function getContextLink(
        bytes32 contextId
    ) external view returns (ContextLink memory);

    function computeContextId(
        address dao,
        bytes32 externalReference
    ) external view returns (bytes32);
}
