import { UltraHonkBackend } from "@aztec/bb.js";
import { Noir } from "@noir-lang/noir_js";
import { ethers } from "ethers";
import fs from "node:fs";
import path from "node:path";

import {
  buildMembershipTree,
  computeNullifier,
  parseBigInt,
  toBytes32,
  type BigNumberishLike,
} from "./proofUtils";

const DEFAULT_CIRCUIT_PATH = path.resolve(__dirname, "../../circuits/target/circuits.json");

type VoteCircuitInput = {
  proposal_id: string;
  membership_root: string;
  ballot_size: number;
  nullifier_hash: string;
  identity_secret: string;
  vote: number;
  leaf_index: number;
  sibling_path: string[];
};

export type VoteSubmissionProofRequest = {
  proposalId: BigNumberishLike;
  ballotSize: number;
  vote: number;
  memberIdentitySecrets: BigNumberishLike[];
  voterIndex: number;
  circuitPath?: string;
};

export type VoteSubmissionProofPayload = {
  proof: string;
  publicInputs: string[];
  proposalId: string;
  ballotSize: number;
  vote: number;
  voterIndex: number;
  identitySecret: string;
  membershipRoot: string;
  nullifierHash: string;
  leafIndex: number;
  siblingPath: string[];
  circuitInput: VoteCircuitInput;
};

type CircuitArtifact = {
  bytecode: string;
};

const circuitArtifactCache = new Map<string, CircuitArtifact>();

function assertValidRequest({ ballotSize, vote, memberIdentitySecrets, voterIndex }: VoteSubmissionProofRequest): void {
  if (!Number.isInteger(ballotSize) || ballotSize <= 0 || ballotSize > 255) {
    throw new Error(`ballotSize must be a positive uint8-compatible integer, received ${ballotSize}`);
  }

  if (!Number.isInteger(vote) || vote < 0) {
    throw new Error(`vote must be a non-negative integer, received ${vote}`);
  }

  if (!Number.isInteger(voterIndex) || voterIndex < 0 || voterIndex >= memberIdentitySecrets.length) {
    throw new Error(`voterIndex ${voterIndex} is outside the memberIdentitySecrets array`);
  }
}

function loadCircuitArtifact(circuitPath: string): CircuitArtifact {
  const normalizedCircuitPath = path.resolve(circuitPath);
  const cachedCircuit = circuitArtifactCache.get(normalizedCircuitPath);
  if (cachedCircuit) {
    return cachedCircuit;
  }

  const circuit = JSON.parse(fs.readFileSync(normalizedCircuitPath, "utf8")) as CircuitArtifact;
  circuitArtifactCache.set(normalizedCircuitPath, circuit);
  return circuit;
}

export async function generateVoteSubmissionProof(
  request: VoteSubmissionProofRequest,
): Promise<VoteSubmissionProofPayload> {
  assertValidRequest(request);

  const proposalId = parseBigInt(request.proposalId);
  const circuitPath = request.circuitPath ?? DEFAULT_CIRCUIT_PATH;
  const circuit = loadCircuitArtifact(circuitPath);
  const membershipTree = await buildMembershipTree(request.memberIdentitySecrets);
  const membershipProof = membershipTree.proofs[request.voterIndex];
  const nullifierHash = await computeNullifier(proposalId, membershipProof.identitySecret);

  const circuitInput: VoteCircuitInput = {
    proposal_id: proposalId.toString(),
    membership_root: membershipTree.membershipRoot.toString(),
    ballot_size: request.ballotSize,
    nullifier_hash: nullifierHash.toString(),
    identity_secret: membershipProof.identitySecret.toString(),
    vote: request.vote,
    leaf_index: membershipProof.leafIndex,
    sibling_path: membershipProof.siblingPath.map((sibling) => sibling.toString()),
  };

  const noir = new Noir(circuit);
  const honk = new UltraHonkBackend(circuit.bytecode, { threads: 1 });
  const { witness } = await noir.execute(circuitInput);

  const originalConsoleLog = console.log;
  let proof: Uint8Array;
  let publicInputs: string[];

  try {
    console.log = (..._args: unknown[]) => undefined;
    ({ proof, publicInputs } = await honk.generateProof(witness, { keccakZK: true }));
  } finally {
    console.log = originalConsoleLog;
  }

  return {
    proof: ethers.hexlify(proof),
    publicInputs: publicInputs.map((value) => ethers.zeroPadValue(value, 32)),
    proposalId: proposalId.toString(),
    ballotSize: request.ballotSize,
    vote: request.vote,
    voterIndex: request.voterIndex,
    identitySecret: membershipProof.identitySecret.toString(),
    membershipRoot: toBytes32(membershipTree.membershipRoot),
    nullifierHash: toBytes32(nullifierHash),
    leafIndex: membershipProof.leafIndex,
    siblingPath: membershipProof.siblingPath.map((sibling) => toBytes32(sibling)),
    circuitInput,
  };
}

async function main(): Promise<void> {
  const encodedRequest = process.argv[2];
  if (!encodedRequest) {
    throw new Error("Expected a base64-encoded VoteSubmissionProofRequest as the first argument");
  }

  const request = JSON.parse(Buffer.from(encodedRequest, "base64").toString("utf8")) as VoteSubmissionProofRequest;
  const payload = await generateVoteSubmissionProof(request);
  process.stdout.write(JSON.stringify(payload));
}

if (require.main === module) {
  void main().catch((error: unknown) => {
    console.error("generateVoteSubmissionProof failed", error);
    process.exit(1);
  });
}
