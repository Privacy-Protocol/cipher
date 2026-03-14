import { Address, Hex, Chain, PublicClient, WalletClient, Transport, Account, Log } from 'viem';

interface RouterActionSubmittedLog {
    type: "router.actionSubmitted";
    actionId: Bytes32;
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    adapter: Address;
    verifierId: Bytes32;
    nullifierKey: Bytes32;
    payloadHash: Bytes32;
    encryptedPayloadRef: Bytes32;
    sender: Address;
    txHash: Hex;
}
interface VotingStoredLog {
    type: "voting.voteStored";
    actionId: Bytes32;
    contextId: Bytes32;
    root: Bytes32;
    nullifier: Bytes32;
    payloadHash: Bytes32;
    encryptedPayloadRef: Bytes32;
    encryptedPayloadDigest: Bytes32;
    submitter: Address;
    txHash: Hex;
}
interface MembershipGrantedLog {
    type: "membership.accessGranted";
    actionId: Bytes32;
    contextId: Bytes32;
    root: Bytes32;
    nullifier: Bytes32;
    payloadHash: Bytes32;
    encryptedPayloadRef: Bytes32;
    sender: Address;
    txHash: Hex;
}
type ParsedCipherLog = RouterActionSubmittedLog | VotingStoredLog | MembershipGrantedLog;

interface EncryptedPayloadArtifact {
    ciphertext: Hex;
    metadata?: Record<string, unknown>;
}
interface CipherEncryptionProvider {
    encrypt(params: {
        workflow: CipherWorkflow;
        contextId: Bytes32;
        payload: unknown;
    }): Promise<EncryptedPayloadArtifact>;
}
interface CipherPayloadStorageProvider {
    put(params: {
        workflow: CipherWorkflow;
        contextId: Bytes32;
        encrypted: EncryptedPayloadArtifact;
    }): Promise<{
        encryptedPayloadRef: Bytes32;
        uri?: string;
    }>;
}

type CipherWorkflow = "membership" | "voting";
type Bytes32 = Hex;
interface CipherClientOptions {
    chain: Chain;
    walletClient: WalletClient<Transport, Chain, Account>;
    appId: string | Bytes32;
    adapter?: CipherWorkflow;
}
interface CipherResolvedConfig {
    chain: Chain;
    appId: Bytes32;
    routerAddress: Address;
    adapterRegistryAddress: Address;
    verifierRegistryAddress: Address;
    nullifierStoreAddress: Address;
    adapters: {
        membership: Address;
        voting: Address;
    };
    actionTypes: {
        membership: Bytes32;
        voting: Bytes32;
    };
    verifierIds: {
        membership: Bytes32;
        voting: Bytes32;
    };
    publicInputsCount: {
        membership: number;
        voting: number;
    };
}
interface CipherProviders {
    proofProvider: CipherProofProvider;
    encryptionProvider: CipherEncryptionProvider;
    payloadStorageProvider: CipherPayloadStorageProvider;
}
interface CipherTxReceipt {
    txHash: Hex;
    actionId?: Bytes32;
    logs: ParsedCipherLog[];
    receipt: Awaited<ReturnType<PublicClient["waitForTransactionReceipt"]>>;
}
interface CipherActionRequest {
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    nullifier: Bytes32;
    payloadHash: Bytes32;
    encryptedPayloadRef: Bytes32;
    verifierId: Bytes32;
    deadline: bigint;
    publicInputs: Bytes32[];
    proof: Hex;
    adapterData: Hex;
}

interface CipherProofBundle {
    proof: Hex;
    publicInputs: Bytes32[];
}
interface MembershipProofInput {
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    payloadHash: Bytes32;
    threshold?: number;
    enforceThreshold?: boolean;
    witness: MembershipWitness;
}
interface VotingProofInput {
    appId: Bytes32;
    actionType: Bytes32;
    contextId: Bytes32;
    optionCount: number;
    voteOption: number;
    witness: MembershipWitness;
    payloadHashOverride?: Bytes32;
    payload: VotingPayloadCommitmentInput;
}
interface MembershipWitness {
    identitySecret: bigint;
    membershipSecret: bigint;
    nullifierSecret: bigint;
    pathElements: bigint[];
    pathIndices: boolean[];
}
interface VotingPayloadCommitmentInput {
    schemaHash: bigint;
    voteBlinding: bigint;
    payloadSalt: bigint;
}
interface CipherProofProvider {
    generateProof(params: {
        workflow: CipherWorkflow;
        input: MembershipProofInput | VotingProofInput;
    }): Promise<CipherProofBundle>;
}

interface MembershipInput {
    contextId: string | Bytes32;
    witness: MembershipWitness;
    rangePolicy?: {
        threshold: number;
        enforce: boolean;
    };
    payload?: MembershipPayloadCommitmentInput;
    encryption?: MembershipEncryptionInput;
    deadlineSecondsFromNow?: number;
}
interface MembershipPayloadCommitmentInput {
    schemaHash: bigint;
    payloadDigest: bigint;
    payloadSalt: bigint;
}
interface MembershipEncryptionInput {
    payload: unknown;
    inline?: boolean;
}
interface MembershipPrepared {
    request: CipherActionRequest;
    proofBundle: CipherProofBundle;
    root: Bytes32;
}
interface MembershipExecuteResult extends CipherTxReceipt {
    request: CipherActionRequest;
    root: Bytes32;
}

interface CipherClientContext {
    walletClient: WalletClient<Transport, Chain, Account>;
    publicClient: PublicClient;
    config: CipherResolvedConfig;
    providers: CipherProviders;
}

declare class MembershipModule {
    private readonly ctx;
    constructor(ctx: CipherClientContext);
    buildProofInput(input: MembershipInput): Promise<{
        contextId: `0x${string}`;
        payloadHash: `0x${string}`;
        proofInput: MembershipProofInput;
    }>;
    prepare(input: MembershipInput): Promise<MembershipPrepared>;
    execute(input: MembershipInput): Promise<MembershipExecuteResult>;
    computeExpectedRoot(input: {
        identitySecret: bigint;
        membershipSecret: bigint;
        pathElements: bigint[];
        pathIndices: boolean[];
    }): Promise<`0x${string}`>;
    computeExpectedNullifier(input: {
        nullifierSecret: bigint;
        contextId: string | `0x${string}`;
    }): Promise<`0x${string}`>;
    getContextState(contextId: string | `0x${string}`): Promise<{
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayloadRef: boolean;
        validAfter: bigint;
        validUntil: bigint;
    }>;
    isRootAllowed(contextId: string | `0x${string}`, root: string | `0x${string}`): Promise<boolean>;
}

interface VotingInput {
    contextId: string | Bytes32;
    optionCount: number;
    voteOption: number;
    witness: MembershipWitness;
    payload: VotingPayloadCommitmentInput;
    encryption?: VotingEncryptionInput;
    deadlineSecondsFromNow?: number;
}
interface VotingEncryptionInput {
    payload: unknown;
    inline?: boolean;
}
interface VotingPrepared {
    request: CipherActionRequest;
    proofBundle: CipherProofBundle;
    root: Bytes32;
}
interface VotingExecuteResult extends CipherTxReceipt {
    request: CipherActionRequest;
    root: Bytes32;
}
interface VotingRecord {
    proposalId: Bytes32;
    root: Bytes32;
    nullifier: Bytes32;
    payloadHash: Bytes32;
    encryptedPayloadRef: Bytes32;
    encryptedPayload: `0x${string}`;
    submitter: `0x${string}`;
    submittedAt: bigint;
}
interface VotingProposalTally {
    forVotes: bigint;
    againstVotes: bigint;
    abstainVotes: bigint;
    tallyCommitment: Bytes32;
    submitter: `0x${string}`;
    submittedAt: bigint;
    finalized: boolean;
}
interface VotingContextLink {
    dao: `0x${string}`;
    externalReference: Bytes32;
    linked: boolean;
}

declare class VotingModule {
    private readonly ctx;
    constructor(ctx: CipherClientContext);
    buildProofInput(input: VotingInput): Promise<{
        contextId: `0x${string}`;
        payloadHash: `0x${string}`;
        proofInput: VotingProofInput;
    }>;
    prepare(input: VotingInput): Promise<VotingPrepared>;
    execute(input: VotingInput): Promise<VotingExecuteResult>;
    computeExpectedRoot(input: {
        identitySecret: bigint;
        membershipSecret: bigint;
        pathElements: bigint[];
        pathIndices: boolean[];
    }): Promise<`0x${string}`>;
    computeExpectedNullifier(input: {
        nullifierSecret: bigint;
        contextId: string | `0x${string}`;
    }): Promise<`0x${string}`>;
    getVote(actionId: string | `0x${string}`): Promise<VotingRecord>;
    getTally(contextId: string | `0x${string}`): Promise<VotingProposalTally>;
    isTallyFinalized(contextId: string | `0x${string}`): Promise<boolean>;
    getContextLink(contextId: string | `0x${string}`): Promise<VotingContextLink>;
    computeContextId(dao: `0x${string}`, externalReference: string | `0x${string}`): Promise<`0x${string}`>;
    getProposalState(contextId: string | `0x${string}`): Promise<{
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayload: boolean;
        startTime: bigint;
        endTime: bigint;
        voteCount: bigint;
    }>;
    isRootAllowed(contextId: string | `0x${string}`, root: string | `0x${string}`): Promise<boolean>;
}

declare function parseCipherLogs(logs: Log[]): ParsedCipherLog[];

declare class CipherClient {
    readonly config: CipherResolvedConfig;
    readonly walletClient: WalletClient<Transport, Chain, Account>;
    readonly publicClient: PublicClient;
    readonly providers: CipherProviders;
    readonly defaultAdapter?: CipherWorkflow;
    readonly membership: MembershipModule;
    readonly voting: VotingModule;
    constructor(params: {
        config: CipherResolvedConfig;
        walletClient: WalletClient<Transport, Chain, Account>;
        publicClient: PublicClient;
        providers: CipherProviders;
        defaultAdapter?: CipherWorkflow;
    });
    vote(input: VotingInput): Promise<VotingExecuteResult>;
    join(input: MembershipInput): Promise<MembershipExecuteResult>;
    execute(input: MembershipInput | VotingInput): Promise<MembershipExecuteResult>;
    generateProof(params: {
        workflow: CipherWorkflow;
        input: MembershipProofInput | VotingProofInput;
    }): Promise<CipherProofBundle>;
    submitAction(request: CipherActionRequest): Promise<CipherTxReceipt>;
    computeNullifierKey(params: {
        actionType: `0x${string}`;
        contextId: `0x${string}`;
        nullifier: `0x${string}`;
    }): Promise<`0x${string}`>;
    isNullifierUsed(nullifierKey: `0x${string}`): Promise<boolean>;
    routerState(): Promise<{
        adapterRegistry: `0x${string}`;
        verifierRegistry: `0x${string}`;
        nullifierStore: `0x${string}`;
    }>;
    getAdapter(workflow: CipherWorkflow): Promise<`0x${string}`>;
    getVerifier(workflow: CipherWorkflow): Promise<{
        verifier: `0x${string}`;
        publicInputSchemaHash: Bytes32;
        publicInputsCount: number;
        enabled: boolean;
    }>;
    parseReceiptLogs(receipt: {
        logs: Parameters<typeof parseCipherLogs>[0];
    }): ParsedCipherLog[];
}

export { type VotingStoredLog as A, type Bytes32 as B, type CipherClientOptions as C, parseCipherLogs as D, type EncryptedPayloadArtifact as E, type MembershipEncryptionInput as M, type ParsedCipherLog as P, type RouterActionSubmittedLog as R, type VotingContextLink as V, CipherClient as a, type CipherResolvedConfig as b, type CipherProofProvider as c, type CipherEncryptionProvider as d, type CipherPayloadStorageProvider as e, type CipherProviders as f, type CipherProofBundle as g, type CipherActionRequest as h, type CipherClientContext as i, type CipherTxReceipt as j, type CipherWorkflow as k, type MembershipExecuteResult as l, type MembershipGrantedLog as m, type MembershipInput as n, type MembershipPayloadCommitmentInput as o, type MembershipPrepared as p, type MembershipProofInput as q, type MembershipWitness as r, type VotingEncryptionInput as s, type VotingExecuteResult as t, type VotingInput as u, type VotingPayloadCommitmentInput as v, type VotingPrepared as w, type VotingProofInput as x, type VotingProposalTally as y, type VotingRecord as z };
