// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {FHE, ebool, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract GovernorConfidential is Governor {
    bytes32 public constant ENCRYPTED_BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,externalEuint8 support,bytes supportProof,address voter,uint256 nonce)");
    bytes32 public constant ENCRYPTED_EXTENDED_BALLOT_TYPEHASH =
        keccak256(
            // solhint-disable-next-line max-line-length
            "ExtendedBallot(uint256 proposalId,externalEuint8 support,bytes supportProof,address voter,uint256 nonce,string reason,bytes params)"
        );

    error GovernorConfidential__NormalVotesNotSupported();
    error GovernorConfidential__NormalGetVotesNotSupported();
    error GovernorConfidential__ProposalStillActive(uint256 proposalId);
    error GovernorConfidential__ResultAlreadyRequested(uint256 proposalId);
    error GovernorConfidential__ResultAlreadyFinalized(uint256 proposalId);
    error GovernorConfidential__ResultDecryptionNotRequested(uint256 proposalId);
    error GovernorConfidential__ResultNotFinalized(uint256 proposalId);

    struct ProposalResult {
        bool decryptionRequested;
        bool finalized;
        bool quorumReached;
        bool voteSucceeded;
        ebool encryptedQuorumReached;
        ebool encryptedVoteSucceeded;
    }

    mapping(uint256 proposalId => ProposalResult) private _proposalResults;

    event EncryptedVoteCast(
        address indexed voter,
        uint256 proposalId,
        euint8 encryptedSupport,
        euint64 weight,
        string reason
    );

    event EncryptedVoteCastWithParams(
        address indexed voter,
        uint256 proposalId,
        euint8 encryptedSupport,
        euint64 weight,
        string reason,
        bytes params
    );

    event ProposalResultDecryptionRequested(
        uint256 indexed proposalId,
        ebool encryptedQuorumReached,
        ebool encryptedVoteSucceeded
    );

    event ProposalResultFinalized(uint256 indexed proposalId, bool quorumReached, bool voteSucceeded);

    constructor(string memory _name) Governor(_name) {}

    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        if (!_proposalResults[proposalId].finalized) {
            revert GovernorConfidential__ResultNotFinalized(proposalId);
        }

        return _proposalResults[proposalId].quorumReached;
    }

    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        if (!_proposalResults[proposalId].finalized) {
            revert GovernorConfidential__ResultNotFinalized(proposalId);
        }

        return _proposalResults[proposalId].voteSucceeded;
    }

    function _confidentialQuorum(uint256 timepoint) internal virtual returns (euint64);

    function _encryptedQuorumReached(uint256 proposalId) internal virtual returns (ebool);

    function _confidentialVoteSucceeded(uint256 proposalId) internal virtual returns (ebool);

    function quorumReached(uint256 proposalId) public view virtual returns (bool) {
        if (!_proposalResults[proposalId].finalized) {
            revert GovernorConfidential__ResultNotFinalized(proposalId);
        }

        return _proposalResults[proposalId].quorumReached;
    }

    function voteSucceeded(uint256 proposalId) public view virtual returns (bool) {
        if (!_proposalResults[proposalId].finalized) {
            revert GovernorConfidential__ResultNotFinalized(proposalId);
        }

        return _proposalResults[proposalId].voteSucceeded;
    }

    function encryptedProposalResult(
        uint256 proposalId
    ) public view virtual returns (ebool encryptedQuorumReached, ebool encryptedVoteSucceeded) {
        ProposalResult storage proposalResult = _proposalResults[proposalId];

        return (proposalResult.encryptedQuorumReached, proposalResult.encryptedVoteSucceeded);
    }

    function requestProposalResultDecryption(uint256 proposalId) public virtual {
        if (proposalSnapshot(proposalId) == 0) {
            revert GovernorNonexistentProposal(proposalId);
        }
        if (clock() <= proposalDeadline(proposalId)) {
            revert GovernorConfidential__ProposalStillActive(proposalId);
        }

        ProposalResult storage proposalResult = _proposalResults[proposalId];
        if (proposalResult.decryptionRequested) {
            revert GovernorConfidential__ResultAlreadyRequested(proposalId);
        }

        ebool encryptedQuorumReached = FHE.makePubliclyDecryptable(_encryptedQuorumReached(proposalId));
        ebool encryptedVoteSucceeded = FHE.makePubliclyDecryptable(_confidentialVoteSucceeded(proposalId));

        proposalResult.decryptionRequested = true;
        proposalResult.encryptedQuorumReached = encryptedQuorumReached;
        proposalResult.encryptedVoteSucceeded = encryptedVoteSucceeded;

        emit ProposalResultDecryptionRequested(proposalId, encryptedQuorumReached, encryptedVoteSucceeded);
    }

    function finalizeProposalResult(
        uint256 proposalId,
        bytes memory abiEncodedProposalResult,
        bytes memory decryptionProof
    ) public virtual {
        ProposalResult storage proposalResult = _proposalResults[proposalId];
        if (!proposalResult.decryptionRequested) {
            revert GovernorConfidential__ResultDecryptionNotRequested(proposalId);
        }
        if (proposalResult.finalized) {
            revert GovernorConfidential__ResultAlreadyFinalized(proposalId);
        }

        bytes32[] memory handles = new bytes32[](2);
        handles[0] = FHE.toBytes32(proposalResult.encryptedQuorumReached);
        handles[1] = FHE.toBytes32(proposalResult.encryptedVoteSucceeded);

        FHE.checkSignatures(handles, abiEncodedProposalResult, decryptionProof);

        (bool quorumReached_, bool voteSucceeded_) = abi.decode(abiEncodedProposalResult, (bool, bool));

        proposalResult.finalized = true;
        proposalResult.quorumReached = quorumReached_;
        proposalResult.voteSucceeded = voteSucceeded_;

        emit ProposalResultFinalized(proposalId, quorumReached_, voteSucceeded_);
    }

    function _getVotes(
        address, // account
        uint256, // timepoint
        bytes memory // params
    ) internal view virtual override returns (uint256) {
        revert GovernorConfidential__NormalGetVotesNotSupported();
    }

    function _getConfidentialVotes(
        address account,
        uint256 timepoint,
        bytes memory /*params*/
    ) internal view virtual returns (euint64);

    function _castVote(
        uint256, // proposalId
        address, // account
        uint8, // support
        string memory, // reason
        bytes memory // params
    ) internal virtual override returns (uint256) {
        revert GovernorConfidential__NormalVotesNotSupported();
    }

    function _castEncryptedVote(
        uint256 proposalId,
        address account,
        externalEuint8 support,
        bytes calldata supportProof,
        string memory reason
    ) internal virtual returns (euint64) {
        return _castEncryptedVote(proposalId, account, support, supportProof, reason, super._defaultParams());
    }

    function _castEncryptedVote(
        uint256 proposalId,
        address account,
        externalEuint8 support,
        bytes calldata supportProof,
        string memory reason,
        bytes memory params
    ) internal virtual returns (euint64) {
        super._validateStateBitmap(proposalId, super._encodeStateBitmap(ProposalState.Active));

        euint8 encryptedSupport = FHE.fromExternal(support, supportProof);

        euint64 totalWeight = _getConfidentialVotes(account, super.proposalSnapshot(proposalId), params);
        euint64 votedWeight = _countEncryptedVote(proposalId, account, encryptedSupport, totalWeight, params);

        if (params.length == 0) {
            emit EncryptedVoteCast(account, proposalId, encryptedSupport, votedWeight, reason);
        } else {
            emit EncryptedVoteCastWithParams(account, proposalId, encryptedSupport, votedWeight, reason, params);
        }

        super._tallyUpdated(proposalId);

        return votedWeight;
    }

    function _countVote(
        uint256, // proposalId
        address, // account
        uint8, // support
        uint256, // totalWeight
        bytes memory // params
    ) internal virtual override returns (uint256) {
        revert GovernorConfidential__NormalVotesNotSupported();
    }

    function _countEncryptedVote(
        uint256 proposalId,
        address account,
        euint8 support,
        euint64 totalWeight,
        bytes memory // params
    ) internal virtual returns (euint64);

    function castEncryptedVote(
        uint256 proposalId,
        externalEuint8 support,
        bytes calldata supportProof
    ) public virtual returns (euint64) {
        address voter = _msgSender();
        return _castEncryptedVote(proposalId, voter, support, supportProof, "");
    }

    function castEncryptedVoteWithReason(
        uint256 proposalId,
        externalEuint8 support,
        string calldata reason,
        bytes calldata supportProof
    ) public virtual returns (euint64) {
        address voter = _msgSender();
        return _castEncryptedVote(proposalId, voter, support, supportProof, reason);
    }

    function castEncryptedVoteWithReasonAndParams(
        uint256 proposalId,
        externalEuint8 support,
        string calldata reason,
        bytes memory params,
        bytes calldata supportProof
    ) public virtual returns (euint64) {
        address voter = _msgSender();
        return _castEncryptedVote(proposalId, voter, support, supportProof, reason, params);
    }

    function castEncryptedVoteBySig(
        uint256 proposalId,
        externalEuint8 support,
        address voter,
        bytes memory signature,
        bytes calldata supportProof
    ) public virtual returns (euint64) {
        if (!_validateEncryptedVoteSig(proposalId, support, voter, signature, supportProof)) {
            revert GovernorInvalidSignature(voter);
        }
        return _castEncryptedVote(proposalId, voter, support, supportProof, "");
    }

    function castEncryptedVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        externalEuint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature,
        bytes calldata supportProof
    ) public virtual returns (euint64) {
        if (!_validateEncryptedExtendedVoteSig(proposalId, support, voter, reason, params, signature, supportProof)) {
            revert GovernorInvalidSignature(voter);
        }
        return _castEncryptedVote(proposalId, voter, support, supportProof, reason, params);
    }

    /// TODO: test this and check if proof needs to be included in the hash
    function _validateEncryptedVoteSig(
        uint256 proposalId,
        externalEuint8 support,
        address voter,
        bytes memory signature,
        bytes calldata supportProof
    ) internal virtual returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                voter,
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            ENCRYPTED_BALLOT_TYPEHASH,
                            proposalId,
                            support,
                            keccak256(supportProof),
                            voter,
                            _useNonce(voter)
                        )
                    )
                ),
                signature
            );
    }

    /// TODO: test this and check if proof needs to be included in the hash
    function _validateEncryptedExtendedVoteSig(
        uint256 proposalId,
        externalEuint8 support,
        address voter,
        string memory reason,
        bytes memory params,
        bytes memory signature,
        bytes calldata supportProof
    ) internal virtual returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(
                voter,
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            ENCRYPTED_EXTENDED_BALLOT_TYPEHASH,
                            proposalId,
                            support,
                            keccak256(supportProof),
                            voter,
                            _useNonce(voter),
                            keccak256(bytes(reason)),
                            keccak256(params)
                        )
                    )
                ),
                signature
            );
    }
}
