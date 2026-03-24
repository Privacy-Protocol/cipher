import { poseidon2Hash } from "@aztec/foundation/crypto";
import { Fr } from "@aztec/foundation/fields";
import { ethers } from "ethers";

export const TREE_HEIGHT = 32;

export type BigNumberishLike = bigint | number | string;

export type MembershipProof = {
  identitySecret: bigint;
  leafHash: bigint;
  leafIndex: number;
  siblingPath: bigint[];
  membershipRoot: bigint;
};

export type MembershipTree = {
  identitySecrets: bigint[];
  leafHashes: bigint[];
  membershipRoot: bigint;
  proofs: MembershipProof[];
};

function toFr(value: bigint): Fr {
  return new Fr(value);
}

export function parseBigInt(value: BigNumberishLike): bigint {
  if (typeof value === "bigint") {
    return value;
  }

  if (typeof value === "number") {
    if (!Number.isInteger(value) || value < 0) {
      throw new Error(`Expected a non-negative integer, received ${value}`);
    }

    return BigInt(value);
  }

  const trimmedValue = value.trim();
  return trimmedValue.startsWith("0x") ? BigInt(trimmedValue) : BigInt(trimmedValue);
}

export async function poseidonHash(values: BigNumberishLike[]): Promise<bigint> {
  const hash = await poseidon2Hash(values.map((value) => toFr(parseBigInt(value))));
  return BigInt(hash.toString());
}

export async function poseidonPair(left: BigNumberishLike, right: BigNumberishLike): Promise<bigint> {
  return poseidonHash([left, right]);
}

export async function computeMembershipLeaf(identitySecret: BigNumberishLike): Promise<bigint> {
  return poseidonHash([identitySecret]);
}

export async function computeNullifier(
  proposalId: BigNumberishLike,
  identitySecret: BigNumberishLike,
): Promise<bigint> {
  return poseidonPair(proposalId, identitySecret);
}

export function toBytes32(value: BigNumberishLike): string {
  return ethers.zeroPadValue(ethers.toBeHex(parseBigInt(value)), 32);
}

export async function buildMembershipTree(identitySecretsInput: BigNumberishLike[]): Promise<MembershipTree> {
  const identitySecrets = identitySecretsInput.map(parseBigInt);
  if (identitySecrets.length === 0) {
    throw new Error("At least one identity secret is required to build a membership tree");
  }

  const leafHashes = await Promise.all(identitySecrets.map((identitySecret) => computeMembershipLeaf(identitySecret)));
  const levels: Array<Map<number, bigint>> = [];

  levels[0] = new Map<number, bigint>();
  leafHashes.forEach((leafHash, index) => {
    levels[0].set(index, leafHash);
  });

  for (let level = 0; level < TREE_HEIGHT; level++) {
    const currentLevel = levels[level];
    const nextLevel = new Map<number, bigint>();
    const parentIndexes = new Set<number>();

    for (const nodeIndex of currentLevel.keys()) {
      parentIndexes.add(nodeIndex >> 1);
    }

    for (const parentIndex of [...parentIndexes].sort((left, right) => left - right)) {
      const leftNode = currentLevel.get(parentIndex * 2) ?? 0n;
      const rightNode = currentLevel.get(parentIndex * 2 + 1) ?? 0n;
      nextLevel.set(parentIndex, await poseidonPair(leftNode, rightNode));
    }

    levels[level + 1] = nextLevel;
  }

  const membershipRoot = levels[TREE_HEIGHT].get(0) ?? 0n;
  const proofs = identitySecrets.map((identitySecret, index) => {
    let currentIndex = index;
    const siblingPath: bigint[] = [];

    for (let level = 0; level < TREE_HEIGHT; level++) {
      siblingPath.push(levels[level].get(currentIndex ^ 1) ?? 0n);
      currentIndex >>= 1;
    }

    return {
      identitySecret,
      leafHash: leafHashes[index],
      leafIndex: index,
      siblingPath,
      membershipRoot,
    };
  });

  return {
    identitySecrets,
    leafHashes,
    membershipRoot,
    proofs,
  };
}
