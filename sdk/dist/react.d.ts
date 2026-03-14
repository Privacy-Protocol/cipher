import * as react_jsx_runtime from 'react/jsx-runtime';
import * as react from 'react';
import { ReactNode } from 'react';
import { a as CipherClient, C as CipherClientOptions, k as CipherWorkflow, B as Bytes32, q as MembershipProofInput, x as VotingProofInput, g as CipherProofBundle, n as MembershipInput, p as MembershipPrepared, l as MembershipExecuteResult, h as CipherActionRequest, j as CipherTxReceipt, u as VotingInput, w as VotingPrepared, t as VotingExecuteResult, z as VotingRecord } from './CipherClient-ufRcU6DL.js';
import 'viem';

type AsyncStatus = "idle" | "loading" | "success" | "error";
interface AsyncOperationState<TData> {
    status: AsyncStatus;
    data: TData | null;
    error: Error | null;
}
interface AsyncOperationResult<TArgs extends unknown[], TData> extends AsyncOperationState<TData> {
    run: (...args: TArgs) => Promise<TData>;
    reset: () => void;
    isIdle: boolean;
    isLoading: boolean;
    isSuccess: boolean;
    isError: boolean;
}
type WorkflowPhase = "idle" | "preparing" | "prepared" | "submitting" | "success" | "error";
interface UseCipherHookOptions {
    client?: CipherClient;
}
type CipherProviderProps = {
    children: ReactNode;
    client: CipherClient;
} | ({
    children: ReactNode;
    client?: undefined;
} & CipherClientOptions);

declare const CipherContext: react.Context<CipherClient | null>;
declare function CipherProvider(props: CipherProviderProps): react_jsx_runtime.JSX.Element;
declare function useCipherContextClient(): CipherClient;

declare function useCipherClient(options?: CipherClientOptions): CipherClient;

declare function useCipherRouter(options?: UseCipherHookOptions): {
    refreshPointers: () => Promise<{
        adapterRegistry: `0x${string}`;
        verifierRegistry: `0x${string}`;
        nullifierStore: `0x${string}`;
    }>;
    pointers: {
        adapterRegistry: `0x${string}`;
        verifierRegistry: `0x${string}`;
        nullifierStore: `0x${string}`;
    } | null;
    pointersStatus: AsyncStatus;
    pointersError: Error | null;
    resolveAdapter: (args_0: CipherWorkflow) => Promise<`0x${string}`>;
    adapterAddress: `0x${string}` | null;
    adapterStatus: AsyncStatus;
    adapterError: Error | null;
    resolveVerifier: (args_0: CipherWorkflow) => Promise<{
        verifier: `0x${string}`;
        publicInputSchemaHash: Bytes32;
        publicInputsCount: number;
        enabled: boolean;
    }>;
    verifierConfig: {
        verifier: `0x${string}`;
        publicInputSchemaHash: Bytes32;
        publicInputsCount: number;
        enabled: boolean;
    } | null;
    verifierStatus: AsyncStatus;
    verifierError: Error | null;
    checkNullifierUsed: (args_0: `0x${string}`) => Promise<boolean>;
    nullifierUsed: boolean | null;
    nullifierCheckStatus: AsyncStatus;
    nullifierCheckError: Error | null;
    computeNullifierKey: (args_0: {
        actionType: Bytes32;
        contextId: Bytes32;
        nullifier: Bytes32;
    }) => Promise<`0x${string}`>;
    computedNullifierKey: `0x${string}` | null;
    nullifierKeyStatus: AsyncStatus;
    nullifierKeyError: Error | null;
};

declare function useGenerateProof(options?: UseCipherHookOptions): {
    generateProof: (args_0: {
        workflow: CipherWorkflow;
        input: MembershipProofInput | VotingProofInput;
    }) => Promise<CipherProofBundle>;
    run: (args_0: {
        workflow: CipherWorkflow;
        input: MembershipProofInput | VotingProofInput;
    }) => Promise<CipherProofBundle>;
    reset: () => void;
    isIdle: boolean;
    isLoading: boolean;
    isSuccess: boolean;
    isError: boolean;
    status: AsyncStatus;
    data: CipherProofBundle | null;
    error: Error | null;
};

declare function useMembership(options?: UseCipherHookOptions): {
    buildProofInput: (input: MembershipInput) => Promise<{
        contextId: `0x${string}`;
        payloadHash: `0x${string}`;
        proofInput: MembershipProofInput;
    }>;
    prepare: (input: MembershipInput) => Promise<MembershipPrepared>;
    submitPrepared: (nextPrepared: MembershipPrepared) => Promise<MembershipExecuteResult>;
    execute: (input: MembershipInput) => Promise<MembershipExecuteResult>;
    computeExpectedRoot: (input: {
        identitySecret: bigint;
        membershipSecret: bigint;
        pathElements: bigint[];
        pathIndices: boolean[];
    }) => Promise<`0x${string}`>;
    computeExpectedNullifier: (input: {
        nullifierSecret: bigint;
        contextId: string | Bytes32;
    }) => Promise<`0x${string}`>;
    phase: WorkflowPhase;
    status: AsyncStatus;
    isLoading: boolean;
    isPreparing: boolean;
    isSubmitting: boolean;
    isPrepared: boolean;
    isSuccess: boolean;
    isError: boolean;
    error: Error | null;
    prepared: MembershipPrepared | null;
    result: MembershipExecuteResult | null;
    reset: () => void;
};
declare const useConfidentialGate: typeof useMembership;

interface UseMembershipStateOptions extends UseCipherHookOptions {
    contextId?: string | Bytes32;
    autoLoad?: boolean;
}
declare function useMembershipState(options?: UseMembershipStateOptions): {
    refreshContextState: (contextId?: string | Bytes32) => Promise<{
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayloadRef: boolean;
        validAfter: bigint;
        validUntil: bigint;
    }>;
    contextState: {
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayloadRef: boolean;
        validAfter: bigint;
        validUntil: bigint;
    } | null;
    contextStatus: AsyncStatus;
    contextError: Error | null;
    checkRootAllowed: (params: {
        contextId?: string | Bytes32;
        root: string | Bytes32;
    }) => Promise<boolean>;
    rootAllowed: boolean | null;
    rootAllowedStatus: AsyncStatus;
    rootAllowedError: Error | null;
};
declare const useCredentialGateState: typeof useMembershipState;

declare function useSubmitCipherAction(options?: UseCipherHookOptions): {
    submitAction: (args_0: CipherActionRequest) => Promise<CipherTxReceipt>;
    run: (args_0: CipherActionRequest) => Promise<CipherTxReceipt>;
    reset: () => void;
    isIdle: boolean;
    isLoading: boolean;
    isSuccess: boolean;
    isError: boolean;
    status: AsyncStatus;
    data: CipherTxReceipt | null;
    error: Error | null;
};

declare function useVoting(options?: UseCipherHookOptions): {
    buildProofInput: (input: VotingInput) => Promise<{
        contextId: `0x${string}`;
        payloadHash: `0x${string}`;
        proofInput: VotingProofInput;
    }>;
    prepare: (input: VotingInput) => Promise<VotingPrepared>;
    submitPrepared: (nextPrepared: VotingPrepared) => Promise<VotingExecuteResult>;
    execute: (input: VotingInput) => Promise<VotingExecuteResult>;
    computeExpectedRoot: (input: {
        identitySecret: bigint;
        membershipSecret: bigint;
        pathElements: bigint[];
        pathIndices: boolean[];
    }) => Promise<`0x${string}`>;
    computeExpectedNullifier: (input: {
        nullifierSecret: bigint;
        contextId: string | Bytes32;
    }) => Promise<`0x${string}`>;
    phase: WorkflowPhase;
    status: AsyncStatus;
    isLoading: boolean;
    isPreparing: boolean;
    isSubmitting: boolean;
    isPrepared: boolean;
    isSuccess: boolean;
    isError: boolean;
    error: Error | null;
    prepared: VotingPrepared | null;
    result: VotingExecuteResult | null;
    reset: () => void;
};
declare const usePrivateVote: typeof useVoting;

interface UseVotingStateOptions extends UseCipherHookOptions {
    contextId?: string | Bytes32;
    autoLoad?: boolean;
}
declare function useVotingState(options?: UseVotingStateOptions): {
    refreshProposalState: (contextId?: string | Bytes32) => Promise<{
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayload: boolean;
        startTime: bigint;
        endTime: bigint;
        voteCount: bigint;
    }>;
    proposalState: {
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayload: boolean;
        startTime: bigint;
        endTime: bigint;
        voteCount: bigint;
    } | null;
    proposalStatus: AsyncStatus;
    proposalError: Error | null;
    checkRootAllowed: (params: {
        contextId?: string | Bytes32;
        root: string | Bytes32;
    }) => Promise<boolean>;
    rootAllowed: boolean | null;
    rootAllowedStatus: AsyncStatus;
    rootAllowedError: Error | null;
    getVote: (actionId: string | Bytes32) => Promise<VotingRecord>;
    voteRecord: VotingRecord | null;
    voteStatus: AsyncStatus;
    voteError: Error | null;
};

export { type AsyncOperationResult, type AsyncOperationState, type AsyncStatus, CipherContext, CipherProvider, type CipherProviderProps, type UseCipherHookOptions, type UseMembershipStateOptions, type UseVotingStateOptions, type WorkflowPhase, useCipherClient, useCipherContextClient, useCipherRouter, useConfidentialGate, useCredentialGateState, useGenerateProof, useMembership, useMembershipState, usePrivateVote, useSubmitCipherAction, useVoting, useVotingState };
