import { BaseError } from "viem";
import { VOTING_ADAPTER_ABI } from "../abi";
import {
  deriveMembershipLeaf,
  deriveMerkleRoot,
  deriveNullifier,
  derivePayloadHash,
  deriveVotingPayloadDigest
} from "../crypto";
import { ZERO_BYTES32 } from "../config";
import { CipherError } from "../errors";
import { assertProofBindings, buildActionRequestFromProof, encodeVoteAdapterData } from "../proof";
import { submitCipherAction } from "../router";
import type {
  VotingContextLink,
  VotingExecuteResult,
  VotingInput,
  VotingPrepared,
  VotingProposalTally,
  VotingRecord
} from "../types/voting";
import { asBytes32 } from "../utils/bytes";
import type { CipherClientContext } from "../client/types";

export class VotingModule {
  constructor(private readonly ctx: CipherClientContext) {}

  async buildProofInput(input: VotingInput): Promise<{
    contextId: `0x${string}`;
    payloadHash: `0x${string}`;
    proofInput: import("../types/proof").VotingProofInput;
  }> {
    const contextId = asBytes32(input.contextId);
    const voteDigest = await deriveVotingPayloadDigest(input.voteOption, input.payload.voteBlinding);
    const payloadHash = await derivePayloadHash({
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.voting,
      contextId,
      schemaHash: input.payload.schemaHash,
      payloadDigest: voteDigest,
      payloadSalt: input.payload.payloadSalt
    });

    const proofInput: import("../types/proof").VotingProofInput = {
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.voting,
      contextId,
      optionCount: input.optionCount,
      voteOption: input.voteOption,
      witness: input.witness,
      payload: input.payload,
      payloadHashOverride: payloadHash
    };

    return { contextId, payloadHash, proofInput };
  }

  async prepare(input: VotingInput): Promise<VotingPrepared> {
    const { contextId, payloadHash, proofInput } = await this.buildProofInput(input);
    const proofBundle = await this.ctx.providers.proofProvider.generateProof({
      workflow: "voting",
      input: proofInput
    });

    assertProofBindings({
      bundle: proofBundle,
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.voting,
      contextId,
      payloadHash,
      expectedLength: this.ctx.config.publicInputsCount.voting
    });

    let encryptedPayloadRef: `0x${string}` = ZERO_BYTES32;
    let adapterData: `0x${string}` = "0x";

    if (input.encryption) {
      try {
        const encrypted = await this.ctx.providers.encryptionProvider.encrypt({
          workflow: "voting",
          contextId,
          payload: input.encryption.payload
        });
        const stored = await this.ctx.providers.payloadStorageProvider.put({
          workflow: "voting",
          contextId,
          encrypted
        });

        encryptedPayloadRef = stored.encryptedPayloadRef;
        adapterData = input.encryption.inline
          ? encodeVoteAdapterData(encrypted.ciphertext)
          : "0x";
      } catch (error) {
        throw new CipherError("ENCRYPTION_PROVIDER_ERROR", "Failed to encrypt/store vote payload", error);
      }
    }

    const deadlineSeconds = input.deadlineSecondsFromNow ?? 1200;
    const deadline = BigInt(Math.floor(Date.now() / 1000) + deadlineSeconds);

    const request = buildActionRequestFromProof({
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.voting,
      contextId,
      verifierId: this.ctx.config.verifierIds.voting,
      deadline,
      encryptedPayloadRef,
      bundle: proofBundle,
      adapterData
    });

    return {
      request,
      proofBundle,
      root: proofBundle.publicInputs[5]
    };
  }

  async execute(input: VotingInput): Promise<VotingExecuteResult> {
    const prepared = await this.prepare(input);
    const tx = await submitCipherAction({
      routerAddress: this.ctx.config.routerAddress,
      walletClient: this.ctx.walletClient,
      publicClient: this.ctx.publicClient,
      request: prepared.request
    });

    return {
      ...tx,
      request: prepared.request,
      root: prepared.root
    };
  }

  async computeExpectedRoot(input: {
    identitySecret: bigint;
    membershipSecret: bigint;
    pathElements: bigint[];
    pathIndices: boolean[];
  }): Promise<`0x${string}`> {
    const leaf = await deriveMembershipLeaf(input.identitySecret, input.membershipSecret);
    return deriveMerkleRoot(leaf, input.pathElements, input.pathIndices);
  }

  async computeExpectedNullifier(input: {
    nullifierSecret: bigint;
    contextId: string | `0x${string}`;
  }): Promise<`0x${string}`> {
    return deriveNullifier(
      input.nullifierSecret,
      this.ctx.config.appId,
      this.ctx.config.actionTypes.voting,
      asBytes32(input.contextId)
    );
  }

  async getVote(actionId: string | `0x${string}`): Promise<VotingRecord> {
    const result = await this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "getVote",
      args: [asBytes32(actionId)]
    });
    const typed = result as unknown as VotingRecord;

    return {
      proposalId: typed.proposalId,
      root: typed.root,
      nullifier: typed.nullifier,
      payloadHash: typed.payloadHash,
      encryptedPayloadRef: typed.encryptedPayloadRef,
      encryptedPayload: typed.encryptedPayload,
      submitter: typed.submitter,
      submittedAt: typed.submittedAt
    };
  }

  async getTally(contextId: string | `0x${string}`): Promise<VotingProposalTally> {
    const result = await this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "getTally",
      args: [asBytes32(contextId)]
    });
    const typed = result as unknown as VotingProposalTally;

    return {
      forVotes: typed.forVotes,
      againstVotes: typed.againstVotes,
      abstainVotes: typed.abstainVotes,
      tallyCommitment: typed.tallyCommitment,
      submitter: typed.submitter,
      submittedAt: typed.submittedAt,
      finalized: typed.finalized
    };
  }

  async isTallyFinalized(contextId: string | `0x${string}`): Promise<boolean> {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "isTallyFinalized",
      args: [asBytes32(contextId)]
    });
  }

  async getContextLink(contextId: string | `0x${string}`): Promise<VotingContextLink> {
    const result = await this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "getContextLink",
      args: [asBytes32(contextId)]
    });
    const typed = result as unknown as VotingContextLink;

    return {
      dao: typed.dao,
      externalReference: typed.externalReference,
      linked: typed.linked
    };
  }

  async computeContextId(dao: `0x${string}`, externalReference: string | `0x${string}`): Promise<`0x${string}`> {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "computeContextId",
      args: [dao, asBytes32(externalReference)]
    });
  }

  async getProposalState(contextId: string | `0x${string}`): Promise<{
    enabled: boolean;
    requirePayload: boolean;
    requireEncryptedPayload: boolean;
    startTime: bigint;
    endTime: bigint;
    voteCount: bigint;
  }> {
    const id = asBytes32(contextId);
    try {
      const [config, voteCount] = await Promise.all([
        this.ctx.publicClient.readContract({
          address: this.ctx.config.adapters.voting,
          abi: VOTING_ADAPTER_ABI,
          functionName: "proposalConfig",
          args: [id]
        }),
        this.ctx.publicClient.readContract({
          address: this.ctx.config.adapters.voting,
          abi: VOTING_ADAPTER_ABI,
          functionName: "voteCountByProposal",
          args: [id]
        })
      ]);
      const typed = config as unknown as {
        enabled: boolean;
        requirePayload: boolean;
        requireEncryptedPayload: boolean;
        startTime: bigint;
        endTime: bigint;
      };

      return {
        enabled: typed.enabled,
        requirePayload: typed.requirePayload,
        requireEncryptedPayload: typed.requireEncryptedPayload,
        startTime: typed.startTime,
        endTime: typed.endTime,
        voteCount
      };
    } catch (error) {
      const msg = error instanceof BaseError ? error.shortMessage : "Failed to read voting state";
      throw new CipherError("TRANSACTION_ERROR", msg, error);
    }
  }

  async isRootAllowed(contextId: string | `0x${string}`, root: string | `0x${string}`): Promise<boolean> {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "allowedRoots",
      args: [asBytes32(contextId), asBytes32(root)]
    });
  }
}
