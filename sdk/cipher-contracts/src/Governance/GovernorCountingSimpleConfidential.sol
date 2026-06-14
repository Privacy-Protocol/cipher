// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {GovernorConfidential} from "./GovernorConfidential.sol";
import {FHE, euint64, ebool, euint8, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract GovernorCountingSimpleConfidential is GovernorConfidential {
    using SafeCast for *;

    enum VoteType {
        Against,
        For,
        Abstain
    }

    struct ProposalVote {
        euint64 againstVotes;
        euint64 forVotes;
        euint64 abstainVotes;
        mapping(address voter => bool) hasVoted;
    }

    mapping(uint256 proposalId => ProposalVote) private _proposalVotes;

    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    function proposalVotes(
        uint256 proposalId
    ) public view virtual returns (euint64 againstVotes, euint64 forVotes, euint64 abstainVotes) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
    }

    function _encryptedQuorumReached(uint256 proposalId) internal virtual override returns (ebool) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        return
            FHE.le(
                _confidentialQuorum(proposalSnapshot(proposalId)),
                FHE.add(proposalVote.abstainVotes, proposalVote.forVotes)
            );
    }

    function _confidentialVoteSucceeded(uint256 proposalId) internal virtual override returns (ebool) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        return FHE.gt(proposalVote.forVotes, proposalVote.againstVotes);
    }

    function _countEncryptedVote(
        uint256 proposalId,
        address account,
        euint8 encryptedSupport,
        euint64 totalWeight,
        bytes memory // params
    ) internal virtual override returns (euint64) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];

        if (!FHE.isInitialized(proposalVote.againstVotes)) {
            proposalVote.againstVotes = FHE.asEuint64(0);
            proposalVote.forVotes = FHE.asEuint64(0);
            proposalVote.abstainVotes = FHE.asEuint64(0);
            FHE.allowThis(proposalVote.againstVotes);
            FHE.allowThis(proposalVote.forVotes);
            FHE.allowThis(proposalVote.abstainVotes);
        }

        if (proposalVote.hasVoted[account]) {
            //TODO ensure this is tested
            revert GovernorAlreadyCastVote(account);
        }
        proposalVote.hasVoted[account] = true;

        // TODO: find a way to check the support type is one of the supported types or throw an error

        ebool isSupportAgainst = FHE.eq(encryptedSupport, FHE.asEuint8(uint8(VoteType.Against)));
        ebool isSupportFor = FHE.eq(encryptedSupport, FHE.asEuint8(uint8(VoteType.For)));
        ebool isSupportAbstain = FHE.eq(encryptedSupport, FHE.asEuint8(uint8(VoteType.Abstain)));

        euint64 againstIncrement = FHE.select(isSupportAgainst, totalWeight, FHE.asEuint64(0));
        euint64 abstainIncrement = FHE.select(isSupportAbstain, totalWeight, FHE.asEuint64(0));
        euint64 forIncrement = FHE.select(isSupportFor, totalWeight, FHE.asEuint64(0));

        proposalVote.againstVotes = FHE.add(proposalVote.againstVotes, againstIncrement);
        proposalVote.abstainVotes = FHE.add(proposalVote.abstainVotes, abstainIncrement);
        proposalVote.forVotes = FHE.add(proposalVote.forVotes, forIncrement);
        FHE.allowThis(proposalVote.againstVotes);
        FHE.allowThis(proposalVote.abstainVotes);
        FHE.allowThis(proposalVote.forVotes);

        return totalWeight;
    }
}
