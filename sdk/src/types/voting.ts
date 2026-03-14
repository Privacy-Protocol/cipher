import type { Bytes32, CipherActionRequest, CipherTxReceipt } from "./common";
import type {
  CipherProofBundle,
  MembershipWitness,
  VotingPayloadCommitmentInput
} from "./proof";

export interface VotingInput {
  contextId: string | Bytes32;
  optionCount: number;
  voteOption: number;
  witness: MembershipWitness;
  payload: VotingPayloadCommitmentInput;
  encryption?: VotingEncryptionInput;
  deadlineSecondsFromNow?: number;
}

export interface VotingEncryptionInput {
  payload: unknown;
  inline?: boolean;
}

export interface VotingPrepared {
  request: CipherActionRequest;
  proofBundle: CipherProofBundle;
  root: Bytes32;
}

export interface VotingExecuteResult extends CipherTxReceipt {
  request: CipherActionRequest;
  root: Bytes32;
}

export interface VotingRecord {
  proposalId: Bytes32;
  root: Bytes32;
  nullifier: Bytes32;
  payloadHash: Bytes32;
  encryptedPayloadRef: Bytes32;
  encryptedPayload: `0x${string}`;
  submitter: `0x${string}`;
  submittedAt: bigint;
}

export interface VotingProposalTally {
  forVotes: bigint;
  againstVotes: bigint;
  abstainVotes: bigint;
  tallyCommitment: Bytes32;
  submitter: `0x${string}`;
  submittedAt: bigint;
  finalized: boolean;
}

export interface VotingContextLink {
  dao: `0x${string}`;
  externalReference: Bytes32;
  linked: boolean;
}
