import { C as CipherClientOptions, a as CipherClient, b as CipherResolvedConfig, c as CipherProofProvider, d as CipherEncryptionProvider, e as CipherPayloadStorageProvider, f as CipherProviders, B as Bytes32, g as CipherProofBundle, h as CipherActionRequest, E as EncryptedPayloadArtifact } from './CipherClient-ufRcU6DL.cjs';
export { i as CipherClientContext, j as CipherTxReceipt, k as CipherWorkflow, M as MembershipEncryptionInput, l as MembershipExecuteResult, m as MembershipGrantedLog, n as MembershipInput, o as MembershipPayloadCommitmentInput, p as MembershipPrepared, q as MembershipProofInput, r as MembershipWitness, P as ParsedCipherLog, R as RouterActionSubmittedLog, V as VotingContextLink, s as VotingEncryptionInput, t as VotingExecuteResult, u as VotingInput, v as VotingPayloadCommitmentInput, w as VotingPrepared, x as VotingProofInput, y as VotingProposalTally, z as VotingRecord, A as VotingStoredLog, D as parseCipherLogs } from './CipherClient-ufRcU6DL.cjs';
import { Address, Hex, PublicClient } from 'viem';

declare function createCipherClient(options: CipherClientOptions): CipherClient;

declare const CIPHER_ACTION_TYPES: {
    readonly membership: `0x${string}`;
    readonly voting: `0x${string}`;
};
declare const CIPHER_VERIFIER_IDS: {
    readonly membership: `0x${string}`;
    readonly voting: `0x${string}`;
};
declare const ZERO_ADDRESS: Address;
declare const ZERO_BYTES32: `0x${string}`;

interface CipherDeploymentRecord {
    routerAddress: Address;
    adapterRegistryAddress: Address;
    verifierRegistryAddress: Address;
    nullifierStoreAddress: Address;
    adapters: {
        membership: Address;
        voting: Address;
    };
    actionTypes: {
        membership: Hex;
        voting: Hex;
    };
    verifierIds: {
        membership: Hex;
        voting: Hex;
    };
    publicInputsCount: {
        membership: number;
        voting: number;
    };
}
declare const CIPHER_DEPLOYMENTS: Record<number, CipherDeploymentRecord>;
type CipherDeploymentResolved = Omit<CipherResolvedConfig, "chain" | "appId">;

declare function configureCipherGlobalProviders(input: {
    proofProvider?: CipherProofProvider;
    encryptionProvider?: CipherEncryptionProvider;
    payloadStorageProvider?: CipherPayloadStorageProvider;
}): void;
declare function getCipherGlobalProviders(): CipherProviders;

declare function resolveCipherConfig(options: CipherClientOptions): {
    resolved: CipherResolvedConfig;
    publicClient: PublicClient;
};

declare function deriveMembershipLeaf(identitySecret: bigint, membershipSecret: bigint): Promise<Bytes32>;
declare function deriveMerkleRoot(leaf: Bytes32, pathElements: bigint[], pathIndices: boolean[]): Promise<Bytes32>;
declare function deriveNullifier(nullifierSecret: bigint, appId: Bytes32, actionType: Bytes32, contextId: Bytes32): Promise<Bytes32>;
declare function derivePayloadHash(params: {
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    schemaHash: bigint;
    payloadDigest: bigint;
    payloadSalt: bigint;
}): Promise<Bytes32>;
declare function deriveVotingPayloadDigest(voteOption: number, voteBlinding: bigint): Promise<bigint>;

declare function hash2(a: bigint, b: bigint): Promise<bigint>;
declare function hash3(a: bigint, b: bigint, c: bigint): Promise<bigint>;
declare function hash6(a: bigint, b: bigint, c: bigint, d: bigint, e: bigint, f: bigint): Promise<bigint>;

interface BrowserCipherProverBridge {
    generateProof(params: Parameters<CipherProofProvider["generateProof"]>[0]): Promise<CipherProofBundle>;
}
declare class BrowserCipherProofProvider implements CipherProofProvider {
    generateProof(params: Parameters<CipherProofProvider["generateProof"]>[0]): Promise<CipherProofBundle>;
}

declare function assertProofBindings(params: {
    bundle: CipherProofBundle;
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    payloadHash: Bytes32;
    expectedLength: number;
}): void;
declare function buildActionRequestFromProof(params: {
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    verifierId: Bytes32;
    deadline: bigint;
    encryptedPayloadRef: Bytes32;
    bundle: CipherProofBundle;
    adapterData: `0x${string}`;
}): CipherActionRequest;
declare function encodeVoteAdapterData(ciphertext?: `0x${string}`): `0x${string}`;

declare class NoopCipherEncryptionProvider implements CipherEncryptionProvider {
    encrypt(params: {
        workflow: "membership" | "voting";
        contextId: `0x${string}`;
        payload: unknown;
    }): Promise<EncryptedPayloadArtifact>;
}
declare class NoopCipherPayloadStorageProvider implements CipherPayloadStorageProvider {
    put(params: {
        workflow: "membership" | "voting";
        contextId: `0x${string}`;
        encrypted: EncryptedPayloadArtifact;
    }): Promise<{
        encryptedPayloadRef: `0x${string}`;
        uri?: string;
    }>;
}

type CipherErrorCode = "UNSUPPORTED_CHAIN" | "UNCONFIGURED_DEPLOYMENT" | "INVALID_APP_ID" | "INVALID_BYTES32" | "PROOF_PROVIDER_ERROR" | "ENCRYPTION_PROVIDER_ERROR" | "PAYLOAD_STORAGE_ERROR" | "PROOF_OUTPUT_INVALID" | "TRANSACTION_ERROR" | "ROUTER_REVERT";
declare class CipherError extends Error {
    readonly code: CipherErrorCode;
    readonly cause?: unknown;
    constructor(code: CipherErrorCode, message: string, cause?: unknown);
}

export { BrowserCipherProofProvider, type BrowserCipherProverBridge, Bytes32, CIPHER_ACTION_TYPES, CIPHER_DEPLOYMENTS, CIPHER_VERIFIER_IDS, CipherActionRequest, CipherClient, CipherClientOptions, type CipherDeploymentRecord, type CipherDeploymentResolved, CipherEncryptionProvider, CipherError, type CipherErrorCode, CipherPayloadStorageProvider, CipherProofBundle, CipherProofProvider, CipherProviders, CipherResolvedConfig, EncryptedPayloadArtifact, NoopCipherEncryptionProvider, NoopCipherPayloadStorageProvider, ZERO_ADDRESS, ZERO_BYTES32, assertProofBindings, buildActionRequestFromProof, configureCipherGlobalProviders, createCipherClient, deriveMembershipLeaf, deriveMerkleRoot, deriveNullifier, derivePayloadHash, deriveVotingPayloadDigest, encodeVoteAdapterData, getCipherGlobalProviders, hash2, hash3, hash6, resolveCipherConfig };
