// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IVotesConfidential} from "../../contracts/contracts/Governance/interfaces/IVotesConfidential.sol";

/// @dev Test-only confidential votes token. Lets a test drive each account's voting power and the
/// total supply directly, with timestamp-keyed checkpoints so `getPastVotes`/`getPastTotalSupply`
/// honour snapshot semantics. Every handle it produces is ACL-allowed to the configured governor so
/// the governor can run FHE ops on it. It is a stand-in for the real ERC7984Votes token; the
/// governor is the contract under test.
contract MockConfidentialVotes is IVotesConfidential, ZamaEthereumConfig {
    struct Checkpoint {
        uint48 key;
        euint64 value;
        uint64 cleartext;
    }

    mapping(address account => Checkpoint[]) private _voteCheckpoints;
    Checkpoint[] private _supplyCheckpoints;

    // Cleartext mirrors so the mock can mint trivial ciphertexts and tests can compute expectations.
    mapping(address account => uint64) private _weight;
    uint64 private _supply;

    address private _governor;

    /// @notice Registers the governor that must be granted ACL access to every produced handle.
    function setGovernor(address governor) external {
        _governor = governor;
    }

    /// @notice Sets `account`'s voting power to `amount` at the current clock, adjusting total supply
    /// by the delta. Pushes a checkpoint for both the account and the supply.
    function setVotes(address account, uint64 amount) external {
        uint64 old = _weight[account];
        _weight[account] = amount;
        _supply = _supply - old + amount;

        _push(_voteCheckpoints[account], amount);
        _push(_supplyCheckpoints, _supply);
    }

    function _push(Checkpoint[] storage ckpts, uint64 cleartext) private {
        euint64 handle = FHE.asEuint64(cleartext);
        FHE.allowThis(handle);
        if (_governor != address(0)) {
            FHE.allow(handle, _governor);
        }

        uint48 now48 = uint48(block.timestamp);
        uint256 n = ckpts.length;
        if (n > 0 && ckpts[n - 1].key == now48) {
            ckpts[n - 1].value = handle;
            ckpts[n - 1].cleartext = cleartext;
        } else {
            ckpts.push(Checkpoint({key: now48, value: handle, cleartext: cleartext}));
        }
    }

    function _lookup(Checkpoint[] storage ckpts, uint256 timepoint) private view returns (euint64) {
        uint256 n = ckpts.length;
        for (uint256 i = n; i > 0; i--) {
            if (ckpts[i - 1].key <= timepoint) {
                return ckpts[i - 1].value;
            }
        }
        return euint64.wrap(bytes32(0));
    }

    function _lookupCleartext(Checkpoint[] storage ckpts, uint256 timepoint) private view returns (uint64) {
        uint256 n = ckpts.length;
        for (uint256 i = n; i > 0; i--) {
            if (ckpts[i - 1].key <= timepoint) {
                return ckpts[i - 1].cleartext;
            }
        }
        return 0;
    }

    // --- Cleartext mirrors (test oracle for the invariant ghosts) ---

    function pastVotesCleartext(address account, uint256 timepoint) external view returns (uint64) {
        return _lookupCleartext(_voteCheckpoints[account], timepoint);
    }

    function pastSupplyCleartext(uint256 timepoint) external view returns (uint64) {
        return _lookupCleartext(_supplyCheckpoints, timepoint);
    }

    // --- IVotesConfidential ---

    function getVotes(address account) external view override returns (euint64) {
        Checkpoint[] storage ckpts = _voteCheckpoints[account];
        uint256 n = ckpts.length;
        return n == 0 ? euint64.wrap(bytes32(0)) : ckpts[n - 1].value;
    }

    function getPastVotes(address account, uint256 timepoint) external view override returns (euint64) {
        return _lookup(_voteCheckpoints[account], timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view override returns (euint64) {
        return _lookup(_supplyCheckpoints, timepoint);
    }

    function confidentialTotalSupply() external view override returns (euint64) {
        uint256 n = _supplyCheckpoints.length;
        return n == 0 ? euint64.wrap(bytes32(0)) : _supplyCheckpoints[n - 1].value;
    }

    // --- ERC-6372 clock (timestamp mode, matching the production MyToken) ---

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // --- Unused delegation surface (voting power is driven directly via setVotes) ---

    function delegates(address) external pure override returns (address) {
        return address(0);
    }

    function delegate(address) external override {}

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external override {}

    function nonces(address) external pure override returns (uint256) {
        return 0;
    }
}
