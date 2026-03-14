"use client";
import {
  CipherError,
  createCipherClient
} from "./chunk-BTXVJWZR.js";

// src/react/CipherProvider.tsx
import { createContext, useContext, useMemo } from "react";
import { jsx } from "react/jsx-runtime";
var CipherContext = createContext(null);
function CipherProvider(props) {
  const providedClient = props.client;
  const chain = "chain" in props ? props.chain : void 0;
  const walletClient = "walletClient" in props ? props.walletClient : void 0;
  const appId = "appId" in props ? props.appId : void 0;
  const adapter = "adapter" in props ? props.adapter : void 0;
  const value = useMemo(() => {
    if (providedClient) return providedClient;
    if (!chain || !walletClient || !appId) {
      throw new CipherError(
        "TRANSACTION_ERROR",
        "CipherProvider requires either a prebuilt client or chain + walletClient + appId"
      );
    }
    return createCipherClient({
      chain,
      walletClient,
      appId,
      adapter
    });
  }, [providedClient, chain, walletClient, appId, adapter]);
  return /* @__PURE__ */ jsx(CipherContext.Provider, { value, children: props.children });
}
function useCipherContextClient() {
  const client = useContext(CipherContext);
  if (!client) {
    throw new CipherError(
      "TRANSACTION_ERROR",
      "CipherProvider is missing. Wrap your app with <CipherProvider> or pass a client directly to the hook."
    );
  }
  return client;
}

// src/react/hooks/useCipherClient.ts
import { useContext as useContext2, useMemo as useMemo2 } from "react";
function useCipherClient(options) {
  const contextClient = useContext2(CipherContext);
  const chain = options?.chain;
  const walletClient = options?.walletClient;
  const appId = options?.appId;
  const adapter = options?.adapter;
  const localClient = useMemo2(() => {
    if (!chain || !walletClient || !appId) return null;
    return createCipherClient({ chain, walletClient, appId, adapter });
  }, [chain, walletClient, appId, adapter]);
  if (localClient) return localClient;
  if (contextClient) return contextClient;
  throw new Error(
    "Cipher client not found. Wrap your component with <CipherProvider> or pass options to useCipherClient(...)."
  );
}

// src/react/hooks/useCipherRouter.ts
import { useCallback as useCallback2, useMemo as useMemo4 } from "react";

// src/react/internal/useAsyncTask.ts
import { useCallback, useEffect, useMemo as useMemo3, useRef, useState } from "react";

// src/react/internal/asyncState.ts
function createIdleAsyncState() {
  return {
    status: "idle",
    data: null,
    error: null
  };
}

// src/react/internal/toError.ts
function toError(value) {
  if (value instanceof Error) return value;
  if (typeof value === "string") {
    return new Error(value);
  }
  return new Error("Unknown error");
}

// src/react/internal/useAsyncTask.ts
function useAsyncTask(fn) {
  const [state, setState] = useState(() => createIdleAsyncState());
  const mountedRef = useRef(true);
  const fnRef = useRef(fn);
  useEffect(() => {
    return () => {
      mountedRef.current = false;
    };
  }, []);
  useEffect(() => {
    fnRef.current = fn;
  }, [fn]);
  const run = useCallback(
    async (...args) => {
      setState((previous) => ({
        ...previous,
        status: "loading",
        error: null
      }));
      try {
        const data = await fnRef.current(...args);
        if (mountedRef.current) {
          setState({
            status: "success",
            data,
            error: null
          });
        }
        return data;
      } catch (error) {
        const normalizedError = toError(error);
        if (mountedRef.current) {
          setState({
            status: "error",
            data: null,
            error: normalizedError
          });
        }
        throw normalizedError;
      }
    },
    []
  );
  const reset = useCallback(() => {
    setState(createIdleAsyncState());
  }, []);
  return useMemo3(
    () => ({
      ...state,
      run,
      reset,
      isIdle: state.status === "idle",
      isLoading: state.status === "loading",
      isSuccess: state.status === "success",
      isError: state.status === "error"
    }),
    [state, run, reset]
  );
}

// src/react/internal/useResolvedCipherClient.ts
import { useContext as useContext3 } from "react";
function useResolvedCipherClient(client) {
  const contextClient = useContext3(CipherContext);
  if (client) return client;
  if (contextClient) return contextClient;
  throw new Error(
    "Cipher client not found. Wrap with <CipherProvider> or pass { client } to the hook."
  );
}

// src/react/hooks/useCipherRouter.ts
function useCipherRouter(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const pointersTask = useAsyncTask(() => client.routerState());
  const adapterTask = useAsyncTask((workflow) => client.getAdapter(workflow));
  const verifierTask = useAsyncTask(
    (workflow) => client.getVerifier(workflow)
  );
  const nullifierCheckTask = useAsyncTask(
    (nullifierKey) => client.isNullifierUsed(nullifierKey)
  );
  const nullifierKeyTask = useAsyncTask((params) => client.computeNullifierKey(params));
  const refreshPointers = useCallback2(() => pointersTask.run(), [pointersTask.run]);
  return useMemo4(
    () => ({
      refreshPointers,
      pointers: pointersTask.data,
      pointersStatus: pointersTask.status,
      pointersError: pointersTask.error,
      resolveAdapter: adapterTask.run,
      adapterAddress: adapterTask.data,
      adapterStatus: adapterTask.status,
      adapterError: adapterTask.error,
      resolveVerifier: verifierTask.run,
      verifierConfig: verifierTask.data,
      verifierStatus: verifierTask.status,
      verifierError: verifierTask.error,
      checkNullifierUsed: nullifierCheckTask.run,
      nullifierUsed: nullifierCheckTask.data,
      nullifierCheckStatus: nullifierCheckTask.status,
      nullifierCheckError: nullifierCheckTask.error,
      computeNullifierKey: nullifierKeyTask.run,
      computedNullifierKey: nullifierKeyTask.data,
      nullifierKeyStatus: nullifierKeyTask.status,
      nullifierKeyError: nullifierKeyTask.error
    }),
    [
      refreshPointers,
      pointersTask.data,
      pointersTask.status,
      pointersTask.error,
      adapterTask.run,
      adapterTask.data,
      adapterTask.status,
      adapterTask.error,
      verifierTask.run,
      verifierTask.data,
      verifierTask.status,
      verifierTask.error,
      nullifierCheckTask.run,
      nullifierCheckTask.data,
      nullifierCheckTask.status,
      nullifierCheckTask.error,
      nullifierKeyTask.run,
      nullifierKeyTask.data,
      nullifierKeyTask.status,
      nullifierKeyTask.error
    ]
  );
}

// src/react/hooks/useGenerateProof.ts
function useGenerateProof(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const task = useAsyncTask(
    (input) => client.generateProof(input)
  );
  return {
    ...task,
    generateProof: task.run
  };
}

// src/react/hooks/useMembership.ts
import { useCallback as useCallback3, useMemo as useMemo5, useState as useState2 } from "react";
function phaseToStatus(phase) {
  if (phase === "error") return "error";
  if (phase === "success" || phase === "prepared") return "success";
  if (phase === "preparing" || phase === "submitting") return "loading";
  return "idle";
}
function useMembership(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const [phase, setPhase] = useState2("idle");
  const [prepared, setPrepared] = useState2(null);
  const [result, setResult] = useState2(null);
  const [error, setError] = useState2(null);
  const reset = useCallback3(() => {
    setPhase("idle");
    setPrepared(null);
    setResult(null);
    setError(null);
  }, []);
  const buildProofInput = useCallback3(
    (input) => client.membership.buildProofInput(input),
    [client]
  );
  const prepare = useCallback3(
    async (input) => {
      setPhase("preparing");
      setError(null);
      try {
        const nextPrepared = await client.membership.prepare(input);
        setPrepared(nextPrepared);
        setPhase("prepared");
        return nextPrepared;
      } catch (caught) {
        const normalized = toError(caught);
        setError(normalized);
        setPhase("error");
        throw normalized;
      }
    },
    [client]
  );
  const submitPrepared = useCallback3(
    async (nextPrepared) => {
      setPhase("submitting");
      setError(null);
      setPrepared(nextPrepared);
      try {
        const tx = await client.submitAction(nextPrepared.request);
        const nextResult = {
          ...tx,
          request: nextPrepared.request,
          root: nextPrepared.root
        };
        setResult(nextResult);
        setPhase("success");
        return nextResult;
      } catch (caught) {
        const normalized = toError(caught);
        setError(normalized);
        setPhase("error");
        throw normalized;
      }
    },
    [client]
  );
  const execute = useCallback3(
    async (input) => {
      const nextPrepared = await prepare(input);
      return submitPrepared(nextPrepared);
    },
    [prepare, submitPrepared]
  );
  const computeExpectedRoot = useCallback3(
    (input) => client.membership.computeExpectedRoot(input),
    [client]
  );
  const computeExpectedNullifier = useCallback3(
    (input) => client.membership.computeExpectedNullifier(input),
    [client]
  );
  const status = phaseToStatus(phase);
  return useMemo5(
    () => ({
      buildProofInput,
      prepare,
      submitPrepared,
      execute,
      computeExpectedRoot,
      computeExpectedNullifier,
      phase,
      status,
      isLoading: status === "loading",
      isPreparing: phase === "preparing",
      isSubmitting: phase === "submitting",
      isPrepared: phase === "prepared",
      isSuccess: status === "success",
      isError: status === "error",
      error,
      prepared,
      result,
      reset
    }),
    [
      buildProofInput,
      prepare,
      submitPrepared,
      execute,
      computeExpectedRoot,
      computeExpectedNullifier,
      phase,
      status,
      error,
      prepared,
      result,
      reset
    ]
  );
}
var useConfidentialGate = useMembership;

// src/react/hooks/useMembershipState.ts
import { useCallback as useCallback4, useEffect as useEffect2, useMemo as useMemo6 } from "react";
function useMembershipState(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const contextTask = useAsyncTask(
    (contextId) => client.membership.getContextState(contextId)
  );
  const rootAllowedTask = useAsyncTask((params) => client.membership.isRootAllowed(params.contextId, params.root));
  const refreshContextState = useCallback4(
    (contextId) => {
      const target = contextId ?? options.contextId;
      if (!target) {
        throw new Error("contextId is required to load membership context state");
      }
      return contextTask.run(target);
    },
    [options.contextId, contextTask.run]
  );
  const checkRootAllowed = useCallback4(
    (params) => {
      const target = params.contextId ?? options.contextId;
      if (!target) {
        throw new Error("contextId is required to check membership root access");
      }
      return rootAllowedTask.run({ contextId: target, root: params.root });
    },
    [options.contextId, rootAllowedTask.run]
  );
  useEffect2(() => {
    if (!options.autoLoad || !options.contextId) return;
    void refreshContextState(options.contextId);
  }, [options.autoLoad, options.contextId, refreshContextState]);
  return useMemo6(
    () => ({
      refreshContextState,
      contextState: contextTask.data,
      contextStatus: contextTask.status,
      contextError: contextTask.error,
      checkRootAllowed,
      rootAllowed: rootAllowedTask.data,
      rootAllowedStatus: rootAllowedTask.status,
      rootAllowedError: rootAllowedTask.error
    }),
    [
      refreshContextState,
      contextTask.data,
      contextTask.status,
      contextTask.error,
      checkRootAllowed,
      rootAllowedTask.data,
      rootAllowedTask.status,
      rootAllowedTask.error
    ]
  );
}
var useCredentialGateState = useMembershipState;

// src/react/hooks/useSubmitCipherAction.ts
function useSubmitCipherAction(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const task = useAsyncTask(
    (request) => client.submitAction(request)
  );
  return {
    ...task,
    submitAction: task.run
  };
}

// src/react/hooks/useVoting.ts
import { useCallback as useCallback5, useMemo as useMemo7, useState as useState3 } from "react";
function phaseToStatus2(phase) {
  if (phase === "error") return "error";
  if (phase === "success" || phase === "prepared") return "success";
  if (phase === "preparing" || phase === "submitting") return "loading";
  return "idle";
}
function useVoting(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const [phase, setPhase] = useState3("idle");
  const [prepared, setPrepared] = useState3(null);
  const [result, setResult] = useState3(null);
  const [error, setError] = useState3(null);
  const reset = useCallback5(() => {
    setPhase("idle");
    setPrepared(null);
    setResult(null);
    setError(null);
  }, []);
  const buildProofInput = useCallback5((input) => client.voting.buildProofInput(input), [client]);
  const prepare = useCallback5(
    async (input) => {
      setPhase("preparing");
      setError(null);
      try {
        const nextPrepared = await client.voting.prepare(input);
        setPrepared(nextPrepared);
        setPhase("prepared");
        return nextPrepared;
      } catch (caught) {
        const normalized = toError(caught);
        setError(normalized);
        setPhase("error");
        throw normalized;
      }
    },
    [client]
  );
  const submitPrepared = useCallback5(
    async (nextPrepared) => {
      setPhase("submitting");
      setError(null);
      setPrepared(nextPrepared);
      try {
        const tx = await client.submitAction(nextPrepared.request);
        const nextResult = {
          ...tx,
          request: nextPrepared.request,
          root: nextPrepared.root
        };
        setResult(nextResult);
        setPhase("success");
        return nextResult;
      } catch (caught) {
        const normalized = toError(caught);
        setError(normalized);
        setPhase("error");
        throw normalized;
      }
    },
    [client]
  );
  const execute = useCallback5(
    async (input) => {
      const nextPrepared = await prepare(input);
      return submitPrepared(nextPrepared);
    },
    [prepare, submitPrepared]
  );
  const computeExpectedRoot = useCallback5(
    (input) => client.voting.computeExpectedRoot(input),
    [client]
  );
  const computeExpectedNullifier = useCallback5(
    (input) => client.voting.computeExpectedNullifier(input),
    [client]
  );
  const status = phaseToStatus2(phase);
  return useMemo7(
    () => ({
      buildProofInput,
      prepare,
      submitPrepared,
      execute,
      computeExpectedRoot,
      computeExpectedNullifier,
      phase,
      status,
      isLoading: status === "loading",
      isPreparing: phase === "preparing",
      isSubmitting: phase === "submitting",
      isPrepared: phase === "prepared",
      isSuccess: status === "success",
      isError: status === "error",
      error,
      prepared,
      result,
      reset
    }),
    [
      buildProofInput,
      prepare,
      submitPrepared,
      execute,
      computeExpectedRoot,
      computeExpectedNullifier,
      phase,
      status,
      error,
      prepared,
      result,
      reset
    ]
  );
}
var usePrivateVote = useVoting;

// src/react/hooks/useVotingState.ts
import { useCallback as useCallback6, useEffect as useEffect3, useMemo as useMemo8 } from "react";
function useVotingState(options = {}) {
  const client = useResolvedCipherClient(options.client);
  const proposalTask = useAsyncTask(
    (contextId) => client.voting.getProposalState(contextId)
  );
  const rootAllowedTask = useAsyncTask((params) => client.voting.isRootAllowed(params.contextId, params.root));
  const voteTask = useAsyncTask(
    (actionId) => client.voting.getVote(actionId)
  );
  const refreshProposalState = useCallback6(
    (contextId) => {
      const target = contextId ?? options.contextId;
      if (!target) {
        throw new Error("contextId is required to load voting proposal state");
      }
      return proposalTask.run(target);
    },
    [options.contextId, proposalTask.run]
  );
  const checkRootAllowed = useCallback6(
    (params) => {
      const target = params.contextId ?? options.contextId;
      if (!target) {
        throw new Error("contextId is required to check voting root access");
      }
      return rootAllowedTask.run({ contextId: target, root: params.root });
    },
    [options.contextId, rootAllowedTask.run]
  );
  const getVote = useCallback6((actionId) => voteTask.run(actionId), [voteTask.run]);
  useEffect3(() => {
    if (!options.autoLoad || !options.contextId) return;
    void refreshProposalState(options.contextId);
  }, [options.autoLoad, options.contextId, refreshProposalState]);
  return useMemo8(
    () => ({
      refreshProposalState,
      proposalState: proposalTask.data,
      proposalStatus: proposalTask.status,
      proposalError: proposalTask.error,
      checkRootAllowed,
      rootAllowed: rootAllowedTask.data,
      rootAllowedStatus: rootAllowedTask.status,
      rootAllowedError: rootAllowedTask.error,
      getVote,
      voteRecord: voteTask.data,
      voteStatus: voteTask.status,
      voteError: voteTask.error
    }),
    [
      refreshProposalState,
      proposalTask.data,
      proposalTask.status,
      proposalTask.error,
      checkRootAllowed,
      rootAllowedTask.data,
      rootAllowedTask.status,
      rootAllowedTask.error,
      getVote,
      voteTask.data,
      voteTask.status,
      voteTask.error
    ]
  );
}
export {
  CipherContext,
  CipherProvider,
  useCipherClient,
  useCipherContextClient,
  useCipherRouter,
  useConfidentialGate,
  useCredentialGateState,
  useGenerateProof,
  useMembership,
  useMembershipState,
  usePrivateVote,
  useSubmitCipherAction,
  useVoting,
  useVotingState
};
//# sourceMappingURL=react.js.map