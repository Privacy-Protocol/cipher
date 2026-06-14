// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {GovernorVotesConfidential} from "./GovernorVotesConfidential.sol";
import {FHE, euint64, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

abstract contract GovernorVotesQuorumFractionConfidential is GovernorVotesConfidential {
    using Checkpoints for Checkpoints.Trace208;

    Checkpoints.Trace208 private _quorumNumeratorHistory;

    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);

    error GovernorInvalidQuorumFraction(uint256 quorumNumerator, uint256 quorumDenominator);
    error GovernorConfidentialQuorumIsEncrypted();

    constructor(uint256 quorumNumeratorValue) {
        _updateQuorumNumerator(quorumNumeratorValue);
    }

    function quorumNumerator() public view virtual returns (uint256) {
        return _quorumNumeratorHistory.latest();
    }

    function quorumNumerator(uint256 timepoint) public view virtual returns (uint256) {
        return _optimisticUpperLookupRecent(_quorumNumeratorHistory, timepoint);
    }

    function quorumDenominator() public view virtual returns (uint256) {
        return 100;
    }

    function quorum(uint256) public view virtual override returns (uint256) {
        revert GovernorConfidentialQuorumIsEncrypted();
    }

    function confidentialQuorum(uint256 timepoint) public virtual returns (euint64) {
        return _confidentialQuorum(timepoint);
    }

    function updateQuorumNumerator(uint256 newQuorumNumerator) public virtual onlyGovernance {
        _updateQuorumNumerator(newQuorumNumerator);
    }

    function _confidentialQuorum(uint256 timepoint) internal virtual override returns (euint64) {
        euint128 supply = FHE.asEuint128(token().getPastTotalSupply(timepoint));
        euint128 numeratorProduct = FHE.mul(supply, SafeCast.toUint128(quorumNumerator(timepoint)));

        return FHE.asEuint64(FHE.div(numeratorProduct, SafeCast.toUint128(quorumDenominator())));
    }

    function _updateQuorumNumerator(uint256 newQuorumNumerator) internal virtual {
        uint256 denominator = quorumDenominator();
        if (newQuorumNumerator > denominator) {
            revert GovernorInvalidQuorumFraction(newQuorumNumerator, denominator);
        }

        uint256 oldQuorumNumerator = quorumNumerator();
        _quorumNumeratorHistory.push(clock(), SafeCast.toUint208(newQuorumNumerator));

        emit QuorumNumeratorUpdated(oldQuorumNumerator, newQuorumNumerator);
    }

    function _optimisticUpperLookupRecent(
        Checkpoints.Trace208 storage ckpts,
        uint256 timepoint
    ) internal view returns (uint256) {
        (, uint48 key, uint208 value) = ckpts.latestCheckpoint();
        return key <= timepoint ? value : ckpts.upperLookupRecent(SafeCast.toUint48(timepoint));
    }
}
