// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library ContextIdLib {
    bytes32 internal constant DAO_CONTEXT_DOMAIN =
        keccak256("CIPHER_DAO_CONTEXT_V1");

    function deriveDaoContextId(
        address dao,
        bytes32 externalReference
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DAO_CONTEXT_DOMAIN,
                    block.chainid,
                    dao,
                    externalReference
                )
            );
    }
}
