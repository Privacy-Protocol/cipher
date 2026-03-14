"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/index.ts
var src_exports = {};
__export(src_exports, {
  BrowserCipherProofProvider: () => BrowserCipherProofProvider,
  CIPHER_ACTION_TYPES: () => CIPHER_ACTION_TYPES,
  CIPHER_DEPLOYMENTS: () => CIPHER_DEPLOYMENTS,
  CIPHER_VERIFIER_IDS: () => CIPHER_VERIFIER_IDS,
  CipherClient: () => CipherClient,
  CipherError: () => CipherError,
  NoopCipherEncryptionProvider: () => NoopCipherEncryptionProvider,
  NoopCipherPayloadStorageProvider: () => NoopCipherPayloadStorageProvider,
  ZERO_ADDRESS: () => ZERO_ADDRESS,
  ZERO_BYTES32: () => ZERO_BYTES32,
  assertProofBindings: () => assertProofBindings,
  buildActionRequestFromProof: () => buildActionRequestFromProof,
  configureCipherGlobalProviders: () => configureCipherGlobalProviders,
  createCipherClient: () => createCipherClient,
  deriveMembershipLeaf: () => deriveMembershipLeaf,
  deriveMerkleRoot: () => deriveMerkleRoot,
  deriveNullifier: () => deriveNullifier,
  derivePayloadHash: () => derivePayloadHash,
  deriveVotingPayloadDigest: () => deriveVotingPayloadDigest,
  encodeVoteAdapterData: () => encodeVoteAdapterData,
  getCipherGlobalProviders: () => getCipherGlobalProviders,
  hash2: () => hash2,
  hash3: () => hash3,
  hash6: () => hash6,
  parseCipherLogs: () => parseCipherLogs,
  resolveCipherConfig: () => resolveCipherConfig
});
module.exports = __toCommonJS(src_exports);

// src/adapters/membership.ts
var import_viem8 = require("viem");

// src/abi/router.ts
var ROUTER_ABI = [
  {
    type: "function",
    name: "submitAction",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "req",
        type: "tuple",
        components: [
          { name: "appId", type: "bytes32" },
          { name: "actionType", type: "bytes32" },
          { name: "contextId", type: "bytes32" },
          { name: "nullifier", type: "bytes32" },
          { name: "payloadHash", type: "bytes32" },
          { name: "encryptedPayloadRef", type: "bytes32" },
          { name: "verifierId", type: "bytes32" },
          { name: "deadline", type: "uint64" },
          { name: "publicInputs", type: "bytes32[]" },
          { name: "proof", type: "bytes" },
          { name: "adapterData", type: "bytes" }
        ]
      }
    ],
    outputs: [{ name: "actionId", type: "bytes32" }]
  },
  {
    type: "function",
    name: "computeActionId",
    stateMutability: "view",
    inputs: [
      {
        name: "req",
        type: "tuple",
        components: [
          { name: "appId", type: "bytes32" },
          { name: "actionType", type: "bytes32" },
          { name: "contextId", type: "bytes32" },
          { name: "nullifier", type: "bytes32" },
          { name: "payloadHash", type: "bytes32" },
          { name: "encryptedPayloadRef", type: "bytes32" },
          { name: "verifierId", type: "bytes32" },
          { name: "deadline", type: "uint64" },
          { name: "publicInputs", type: "bytes32[]" },
          { name: "proof", type: "bytes" },
          { name: "adapterData", type: "bytes" }
        ]
      },
      { name: "sender", type: "address" }
    ],
    outputs: [{ name: "actionId", type: "bytes32" }]
  },
  {
    type: "function",
    name: "computeNullifierKey",
    stateMutability: "view",
    inputs: [
      { name: "appId", type: "bytes32" },
      { name: "actionType", type: "bytes32" },
      { name: "contextId", type: "bytes32" },
      { name: "nullifier", type: "bytes32" }
    ],
    outputs: [{ name: "nullifierKey", type: "bytes32" }]
  },
  {
    type: "function",
    name: "adapterRegistry",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }]
  },
  {
    type: "function",
    name: "verifierRegistry",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }]
  },
  {
    type: "function",
    name: "nullifierStore",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }]
  },
  {
    type: "event",
    name: "ActionSubmitted",
    inputs: [
      { name: "actionId", type: "bytes32", indexed: true },
      { name: "appId", type: "bytes32", indexed: true },
      { name: "actionType", type: "bytes32", indexed: true },
      { name: "contextId", type: "bytes32", indexed: false },
      { name: "adapter", type: "address", indexed: false },
      { name: "verifierId", type: "bytes32", indexed: false },
      { name: "nullifierKey", type: "bytes32", indexed: false },
      { name: "payloadHash", type: "bytes32", indexed: false },
      { name: "encryptedPayloadRef", type: "bytes32", indexed: false },
      { name: "sender", type: "address", indexed: false }
    ]
  }
];

// src/abi/adapterRegistry.ts
var ADAPTER_REGISTRY_ABI = [
  {
    type: "function",
    name: "getAdapter",
    stateMutability: "view",
    inputs: [
      { name: "appId", type: "bytes32" },
      { name: "actionType", type: "bytes32" }
    ],
    outputs: [{ type: "address" }]
  },
  {
    type: "function",
    name: "isAdapterRegistered",
    stateMutability: "view",
    inputs: [
      { name: "appId", type: "bytes32" },
      { name: "actionType", type: "bytes32" }
    ],
    outputs: [{ type: "bool" }]
  }
];

// src/abi/verifierRegistry.ts
var VERIFIER_REGISTRY_ABI = [
  {
    type: "function",
    name: "getVerifier",
    stateMutability: "view",
    inputs: [{ name: "verifierId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "verifier", type: "address" },
          { name: "publicInputSchemaHash", type: "bytes32" },
          { name: "publicInputsCount", type: "uint16" },
          { name: "enabled", type: "bool" }
        ]
      }
    ]
  },
  {
    type: "function",
    name: "isVerifierAllowed",
    stateMutability: "view",
    inputs: [
      { name: "appId", type: "bytes32" },
      { name: "actionType", type: "bytes32" },
      { name: "verifierId", type: "bytes32" }
    ],
    outputs: [{ type: "bool" }]
  }
];

// src/abi/nullifierStore.ts
var NULLIFIER_STORE_ABI = [
  {
    type: "function",
    name: "isNullifierUsed",
    stateMutability: "view",
    inputs: [{ name: "nullifierKey", type: "bytes32" }],
    outputs: [{ type: "bool" }]
  }
];

// src/abi/membershipAdapter.ts
var MEMBERSHIP_ADAPTER_ABI = [
  {
    type: "function",
    name: "contextConfig",
    stateMutability: "view",
    inputs: [{ name: "contextId", type: "bytes32" }],
    outputs: [
      { type: "bool", name: "enabled" },
      { type: "bool", name: "requirePayload" },
      { type: "bool", name: "requireEncryptedPayloadRef" },
      { type: "uint64", name: "validAfter" },
      { type: "uint64", name: "validUntil" }
    ]
  },
  {
    type: "function",
    name: "allowedRoots",
    stateMutability: "view",
    inputs: [
      { name: "contextId", type: "bytes32" },
      { name: "root", type: "bytes32" }
    ],
    outputs: [{ type: "bool" }]
  },
  {
    type: "event",
    name: "CredentialAccessGranted",
    inputs: [
      { name: "actionId", type: "bytes32", indexed: true },
      { name: "contextId", type: "bytes32", indexed: true },
      { name: "root", type: "bytes32", indexed: true },
      { name: "nullifier", type: "bytes32", indexed: false },
      { name: "payloadHash", type: "bytes32", indexed: false },
      { name: "encryptedPayloadRef", type: "bytes32", indexed: false },
      { name: "sender", type: "address", indexed: false }
    ]
  }
];

// src/abi/votingAdapter.ts
var VOTING_ADAPTER_ABI = [
  {
    type: "function",
    name: "computeContextId",
    stateMutability: "view",
    inputs: [
      { name: "dao", type: "address" },
      { name: "externalReference", type: "bytes32" }
    ],
    outputs: [{ type: "bytes32" }]
  },
  {
    type: "function",
    name: "getContextLink",
    stateMutability: "view",
    inputs: [{ name: "contextId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "dao", type: "address" },
          { name: "externalReference", type: "bytes32" },
          { name: "linked", type: "bool" }
        ]
      }
    ]
  },
  {
    type: "function",
    name: "getVote",
    stateMutability: "view",
    inputs: [{ name: "actionId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "proposalId", type: "bytes32" },
          { name: "root", type: "bytes32" },
          { name: "nullifier", type: "bytes32" },
          { name: "payloadHash", type: "bytes32" },
          { name: "encryptedPayloadRef", type: "bytes32" },
          { name: "encryptedPayload", type: "bytes" },
          { name: "submitter", type: "address" },
          { name: "submittedAt", type: "uint64" }
        ]
      }
    ]
  },
  {
    type: "function",
    name: "getTally",
    stateMutability: "view",
    inputs: [{ name: "contextId", type: "bytes32" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "forVotes", type: "uint256" },
          { name: "againstVotes", type: "uint256" },
          { name: "abstainVotes", type: "uint256" },
          { name: "tallyCommitment", type: "bytes32" },
          { name: "submitter", type: "address" },
          { name: "submittedAt", type: "uint64" },
          { name: "finalized", type: "bool" }
        ]
      }
    ]
  },
  {
    type: "function",
    name: "isTallyFinalized",
    stateMutability: "view",
    inputs: [{ name: "contextId", type: "bytes32" }],
    outputs: [{ type: "bool" }]
  },
  {
    type: "function",
    name: "voteCountByProposal",
    stateMutability: "view",
    inputs: [{ name: "contextId", type: "bytes32" }],
    outputs: [{ type: "uint256" }]
  },
  {
    type: "function",
    name: "proposalConfig",
    stateMutability: "view",
    inputs: [{ name: "contextId", type: "bytes32" }],
    outputs: [
      { type: "bool", name: "enabled" },
      { type: "bool", name: "requirePayload" },
      { type: "bool", name: "requireEncryptedPayload" },
      { type: "uint64", name: "startTime" },
      { type: "uint64", name: "endTime" }
    ]
  },
  {
    type: "function",
    name: "allowedRoots",
    stateMutability: "view",
    inputs: [
      { type: "bytes32", name: "contextId" },
      { type: "bytes32", name: "root" }
    ],
    outputs: [{ type: "bool" }]
  },
  {
    type: "event",
    name: "VoteStored",
    inputs: [
      { name: "actionId", type: "bytes32", indexed: true },
      { name: "contextId", type: "bytes32", indexed: true },
      { name: "root", type: "bytes32", indexed: true },
      { name: "nullifier", type: "bytes32", indexed: false },
      { name: "payloadHash", type: "bytes32", indexed: false },
      { name: "encryptedPayloadRef", type: "bytes32", indexed: false },
      { name: "encryptedPayloadDigest", type: "bytes32", indexed: false },
      { name: "submitter", type: "address", indexed: false }
    ]
  }
];

// src/utils/bytes.ts
var import_viem = require("viem");

// src/errors/CipherError.ts
var CipherError = class extends Error {
  constructor(code, message, cause) {
    super(message);
    this.name = "CipherError";
    this.code = code;
    this.cause = cause;
  }
};

// src/utils/bytes.ts
function asBytes32(value) {
  if (typeof value === "bigint") {
    return (0, import_viem.pad)(`0x${value.toString(16)}`, { size: 32 });
  }
  if ((0, import_viem.isHex)(value)) {
    if (value.length !== 66) {
      throw new CipherError("INVALID_BYTES32", `Expected bytes32 hex, got length ${value.length}`);
    }
    return value;
  }
  return (0, import_viem.keccak256)((0, import_viem.stringToHex)(value));
}
function bytes32ToBigInt(value) {
  return (0, import_viem.hexToBigInt)(value);
}

// src/crypto/poseidon.ts
var import_crypto = require("@aztec/foundation/crypto");
var import_fields = require("@aztec/foundation/fields");
function toFr(value) {
  return new import_fields.Fr(value);
}
async function hash(values) {
  const out = await (0, import_crypto.poseidon2Hash)(values.map(toFr));
  return BigInt(out.toString());
}
async function hash2(a, b) {
  return hash([a, b]);
}
async function hash3(a, b, c) {
  return hash([a, b, c]);
}
async function hash6(a, b, c, d, e, f) {
  return hash([a, b, c, d, e, f]);
}

// src/crypto/commitments.ts
async function deriveMembershipLeaf(identitySecret, membershipSecret) {
  return asBytes32(await hash2(identitySecret, membershipSecret));
}
async function deriveMerkleRoot(leaf, pathElements, pathIndices) {
  let node = bytes32ToBigInt(leaf);
  for (let i = 0; i < pathElements.length; i++) {
    node = pathIndices[i] ? await hash2(pathElements[i], node) : await hash2(node, pathElements[i]);
  }
  return asBytes32(node);
}
async function deriveNullifier(nullifierSecret, appId, actionType, contextId) {
  const scope = await hash3(bytes32ToBigInt(appId), bytes32ToBigInt(actionType), bytes32ToBigInt(contextId));
  const domain = 1001n;
  const scoped = await hash2(scope, domain);
  return asBytes32(await hash2(nullifierSecret, scoped));
}
async function derivePayloadHash(params) {
  const saltTerm = await hash6(params.payloadSalt, 2001n, 0n, 0n, 0n, 0n);
  const commitment = await hash6(
    bytes32ToBigInt(params.appId),
    bytes32ToBigInt(params.actionType),
    bytes32ToBigInt(params.contextId),
    params.schemaHash,
    params.payloadDigest,
    saltTerm
  );
  return asBytes32(commitment);
}
async function deriveVotingPayloadDigest(voteOption, voteBlinding) {
  return hash2(BigInt(voteOption), voteBlinding);
}

// src/proof/browserProofProvider.ts
var BrowserCipherProofProvider = class {
  async generateProof(params) {
    const bridge = globalThis.__cipherBrowserProver;
    if (!bridge) {
      throw new CipherError(
        "PROOF_PROVIDER_ERROR",
        "No browser proof provider bridge found. Set globalThis.__cipherBrowserProver or configureCipherGlobalProviders({ proofProvider })."
      );
    }
    return bridge.generateProof(params);
  }
};

// src/proof/helpers.ts
var import_viem2 = require("viem");
function assertProofBindings(params) {
  const { bundle, appId, actionType, contextId, payloadHash, expectedLength } = params;
  if (bundle.publicInputs.length !== expectedLength) {
    throw new CipherError(
      "PROOF_OUTPUT_INVALID",
      `Expected ${expectedLength} public inputs, got ${bundle.publicInputs.length}`
    );
  }
  if (bundle.publicInputs[0] !== appId) {
    throw new CipherError("PROOF_OUTPUT_INVALID", "Proof appId mismatch");
  }
  if (bundle.publicInputs[1] !== actionType) {
    throw new CipherError("PROOF_OUTPUT_INVALID", "Proof actionType mismatch");
  }
  if (bundle.publicInputs[2] !== contextId) {
    throw new CipherError("PROOF_OUTPUT_INVALID", "Proof contextId mismatch");
  }
  if (bundle.publicInputs[4] !== payloadHash) {
    throw new CipherError("PROOF_OUTPUT_INVALID", "Proof payloadHash mismatch");
  }
}
function buildActionRequestFromProof(params) {
  const { appId, actionType, contextId, verifierId, deadline, encryptedPayloadRef, bundle, adapterData } = params;
  return {
    appId,
    actionType,
    contextId,
    nullifier: bundle.publicInputs[3],
    payloadHash: bundle.publicInputs[4],
    encryptedPayloadRef,
    verifierId,
    deadline,
    publicInputs: bundle.publicInputs,
    proof: bundle.proof,
    adapterData
  };
}
function encodeVoteAdapterData(ciphertext) {
  if (!ciphertext || ciphertext === "0x") return "0x";
  return (0, import_viem2.encodeAbiParameters)([{ type: "bytes" }], [ciphertext]);
}

// src/router/read.ts
async function readRouterPointers(params) {
  const [adapterRegistry, verifierRegistry, nullifierStore] = await Promise.all([
    params.publicClient.readContract({
      address: params.routerAddress,
      abi: ROUTER_ABI,
      functionName: "adapterRegistry"
    }),
    params.publicClient.readContract({
      address: params.routerAddress,
      abi: ROUTER_ABI,
      functionName: "verifierRegistry"
    }),
    params.publicClient.readContract({
      address: params.routerAddress,
      abi: ROUTER_ABI,
      functionName: "nullifierStore"
    })
  ]);
  return { adapterRegistry, verifierRegistry, nullifierStore };
}
async function readRouterComputedNullifierKey(params) {
  return params.publicClient.readContract({
    address: params.routerAddress,
    abi: ROUTER_ABI,
    functionName: "computeNullifierKey",
    args: [params.appId, params.actionType, params.contextId, params.nullifier]
  });
}
async function readAdapterAddress(params) {
  return params.publicClient.readContract({
    address: params.adapterRegistryAddress,
    abi: ADAPTER_REGISTRY_ABI,
    functionName: "getAdapter",
    args: [params.appId, params.actionType]
  });
}
async function isNullifierUsed(params) {
  return params.publicClient.readContract({
    address: params.nullifierStoreAddress,
    abi: NULLIFIER_STORE_ABI,
    functionName: "isNullifierUsed",
    args: [params.nullifierKey]
  });
}
async function readVerifierConfig(params) {
  const result = await params.publicClient.readContract({
    address: params.verifierRegistryAddress,
    abi: VERIFIER_REGISTRY_ABI,
    functionName: "getVerifier",
    args: [params.verifierId]
  });
  const typed = result;
  return {
    verifier: typed.verifier,
    publicInputSchemaHash: typed.publicInputSchemaHash,
    publicInputsCount: Number(typed.publicInputsCount),
    enabled: typed.enabled
  };
}

// src/router/submitAction.ts
var import_viem4 = require("viem");

// src/events/parseLogs.ts
var import_viem3 = require("viem");
function isNamedArgs(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function decodeWith(abi, log) {
  try {
    const decoded = (0, import_viem3.decodeEventLog)({ abi, data: log.data, topics: log.topics });
    if (!decoded.eventName || !isNamedArgs(decoded.args)) {
      return null;
    }
    return { eventName: decoded.eventName, args: decoded.args };
  } catch {
    return null;
  }
}
function parseCipherLogs(logs) {
  const parsed = [];
  for (const log of logs) {
    const router = decodeWith(ROUTER_ABI, log);
    if (router?.eventName === "ActionSubmitted") {
      parsed.push({
        type: "router.actionSubmitted",
        actionId: router.args.actionId,
        appId: router.args.appId,
        actionType: router.args.actionType,
        contextId: router.args.contextId,
        adapter: router.args.adapter,
        verifierId: router.args.verifierId,
        nullifierKey: router.args.nullifierKey,
        payloadHash: router.args.payloadHash,
        encryptedPayloadRef: router.args.encryptedPayloadRef,
        sender: router.args.sender,
        txHash: log.transactionHash ?? "0x"
      });
      continue;
    }
    const voting = decodeWith(VOTING_ADAPTER_ABI, log);
    if (voting?.eventName === "VoteStored") {
      parsed.push({
        type: "voting.voteStored",
        actionId: voting.args.actionId,
        contextId: voting.args.contextId,
        root: voting.args.root,
        nullifier: voting.args.nullifier,
        payloadHash: voting.args.payloadHash,
        encryptedPayloadRef: voting.args.encryptedPayloadRef,
        encryptedPayloadDigest: voting.args.encryptedPayloadDigest,
        submitter: voting.args.submitter,
        txHash: log.transactionHash ?? "0x"
      });
      continue;
    }
    const membership = decodeWith(MEMBERSHIP_ADAPTER_ABI, log);
    if (membership?.eventName === "CredentialAccessGranted") {
      parsed.push({
        type: "membership.accessGranted",
        actionId: membership.args.actionId,
        contextId: membership.args.contextId,
        root: membership.args.root,
        nullifier: membership.args.nullifier,
        payloadHash: membership.args.payloadHash,
        encryptedPayloadRef: membership.args.encryptedPayloadRef,
        sender: membership.args.sender,
        txHash: log.transactionHash ?? "0x"
      });
    }
  }
  return parsed;
}

// src/router/submitAction.ts
async function submitCipherAction(params) {
  const { routerAddress, walletClient, publicClient, request } = params;
  const account = walletClient.account;
  if (!account) {
    throw new CipherError("TRANSACTION_ERROR", "walletClient.account is required to submit actions");
  }
  try {
    const actionId = await publicClient.readContract({
      address: routerAddress,
      abi: ROUTER_ABI,
      functionName: "computeActionId",
      args: [request, account.address]
    });
    const txHash = await walletClient.writeContract({
      account,
      chain: walletClient.chain,
      address: routerAddress,
      abi: ROUTER_ABI,
      functionName: "submitAction",
      args: [request]
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    const logs = parseCipherLogs(receipt.logs);
    return {
      txHash,
      actionId,
      logs,
      receipt
    };
  } catch (error) {
    const msg = error instanceof import_viem4.BaseError ? error.shortMessage : "Failed to submit Cipher action";
    throw new CipherError("TRANSACTION_ERROR", msg, error);
  }
}

// src/config/constants.ts
var import_viem5 = require("viem");
var CIPHER_ACTION_TYPES = {
  membership: (0, import_viem5.keccak256)((0, import_viem5.stringToHex)("CIPHER_ACTION:CREDENTIAL_GATE:v1")),
  voting: (0, import_viem5.keccak256)((0, import_viem5.stringToHex)("CIPHER_ACTION:PRIVATE_VOTE:v1"))
};
var CIPHER_VERIFIER_IDS = {
  membership: (0, import_viem5.keccak256)((0, import_viem5.stringToHex)("CIPHER_VERIFIER:CREDENTIAL_GATE_HONK:v1")),
  voting: (0, import_viem5.keccak256)((0, import_viem5.stringToHex)("CIPHER_VERIFIER:VOTING_HONK:v1"))
};
var ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
var ZERO_BYTES32 = "0x0000000000000000000000000000000000000000000000000000000000000000";

// src/config/deployments.ts
var CIPHER_DEPLOYMENTS = {
  11155111: {
    routerAddress: "0xF74f1Cd485079ffe1F23A21cbC1872307431ABd6",
    adapterRegistryAddress: "0xC958131B94014aB57602F285e757a8722115180c",
    verifierRegistryAddress: "0xD8950adB2A51CBc23Ed852E2b8e65C452C2e0e00",
    nullifierStoreAddress: "0xa88207901032D58f6DCe2715b4Bf8920f365f74E",
    adapters: {
      membership: "0x92d490D3020A266981BBDcaD66D0c18D21EF9810",
      voting: "0x015620e5c9cC67d8546b240ddFE05c0362994253"
    },
    actionTypes: CIPHER_ACTION_TYPES,
    verifierIds: CIPHER_VERIFIER_IDS,
    publicInputsCount: { membership: 9, voting: 8 }
  }
};

// src/encryption/noopProviders.ts
var import_viem6 = require("viem");
var NoopCipherEncryptionProvider = class {
  async encrypt(params) {
    const json = JSON.stringify({ workflow: params.workflow, payload: params.payload });
    const bytes = new TextEncoder().encode(json);
    return { ciphertext: (0, import_viem6.toHex)(bytes) };
  }
};
var NoopCipherPayloadStorageProvider = class {
  async put(params) {
    const ref = (0, import_viem6.keccak256)(params.encrypted.ciphertext);
    return { encryptedPayloadRef: ref, uri: void 0 };
  }
};

// src/config/providers.ts
var globalProviders = {
  proofProvider: new BrowserCipherProofProvider(),
  encryptionProvider: new NoopCipherEncryptionProvider(),
  payloadStorageProvider: new NoopCipherPayloadStorageProvider()
};
function configureCipherGlobalProviders(input) {
  globalProviders = {
    proofProvider: input.proofProvider ?? globalProviders.proofProvider,
    encryptionProvider: input.encryptionProvider ?? globalProviders.encryptionProvider,
    payloadStorageProvider: input.payloadStorageProvider ?? globalProviders.payloadStorageProvider
  };
}
function getCipherGlobalProviders() {
  return globalProviders;
}

// src/config/resolveConfig.ts
var import_viem7 = require("viem");
function asBytes32AppId(value) {
  if ((0, import_viem7.isHex)(value)) {
    if (value.length !== 66) {
      throw new CipherError("INVALID_APP_ID", "Hex appId must be bytes32 (66 chars)");
    }
    return value;
  }
  return (0, import_viem7.keccak256)((0, import_viem7.stringToHex)(`CIPHER_APP:${value}`));
}
function assertConfiguredAddresses(config) {
  const addresses = [
    config.routerAddress,
    config.adapterRegistryAddress,
    config.verifierRegistryAddress,
    config.nullifierStoreAddress,
    config.adapters.membership,
    config.adapters.voting
  ];
  if (addresses.some((a) => a.toLowerCase() === ZERO_ADDRESS)) {
    throw new CipherError(
      "UNCONFIGURED_DEPLOYMENT",
      `Cipher SDK deployment for chain ${config.chain.id} is not fully configured yet`
    );
  }
}
function resolveCipherConfig(options) {
  const deployment = CIPHER_DEPLOYMENTS[options.chain.id];
  if (!deployment) {
    throw new CipherError("UNSUPPORTED_CHAIN", `Unsupported chain id: ${options.chain.id}`);
  }
  const resolved = {
    chain: options.chain,
    appId: asBytes32AppId(options.appId),
    routerAddress: deployment.routerAddress,
    adapterRegistryAddress: deployment.adapterRegistryAddress,
    verifierRegistryAddress: deployment.verifierRegistryAddress,
    nullifierStoreAddress: deployment.nullifierStoreAddress,
    adapters: deployment.adapters,
    actionTypes: deployment.actionTypes,
    verifierIds: deployment.verifierIds,
    publicInputsCount: deployment.publicInputsCount
  };
  assertConfiguredAddresses(resolved);
  const publicClient = (0, import_viem7.createPublicClient)({
    chain: options.chain,
    transport: (0, import_viem7.http)()
  });
  return { resolved, publicClient };
}

// src/adapters/membership.ts
var MembershipModule = class {
  constructor(ctx) {
    this.ctx = ctx;
  }
  async buildProofInput(input) {
    const contextId = asBytes32(input.contextId);
    let payloadHash = ZERO_BYTES32;
    if (input.payload) {
      payloadHash = await derivePayloadHash({
        appId: this.ctx.config.appId,
        actionType: this.ctx.config.actionTypes.membership,
        contextId,
        schemaHash: input.payload.schemaHash,
        payloadDigest: input.payload.payloadDigest,
        payloadSalt: input.payload.payloadSalt
      });
    }
    const proofInput = {
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.membership,
      contextId,
      payloadHash,
      threshold: input.rangePolicy?.threshold ?? 0,
      enforceThreshold: input.rangePolicy?.enforce ?? false,
      witness: input.witness
    };
    return { contextId, payloadHash, proofInput };
  }
  async prepare(input) {
    const { contextId, payloadHash, proofInput } = await this.buildProofInput(input);
    const proofBundle = await this.ctx.providers.proofProvider.generateProof({
      workflow: "membership",
      input: proofInput
    });
    assertProofBindings({
      bundle: proofBundle,
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.membership,
      contextId,
      payloadHash,
      expectedLength: this.ctx.config.publicInputsCount.membership
    });
    let encryptedPayloadRef = ZERO_BYTES32;
    if (input.encryption) {
      try {
        const encrypted = await this.ctx.providers.encryptionProvider.encrypt({
          workflow: "membership",
          contextId,
          payload: input.encryption.payload
        });
        const stored = await this.ctx.providers.payloadStorageProvider.put({
          workflow: "membership",
          contextId,
          encrypted
        });
        encryptedPayloadRef = stored.encryptedPayloadRef;
      } catch (error) {
        throw new CipherError("ENCRYPTION_PROVIDER_ERROR", "Failed to encrypt/store membership payload", error);
      }
    }
    const deadlineSeconds = input.deadlineSecondsFromNow ?? 1200;
    const deadline = BigInt(Math.floor(Date.now() / 1e3) + deadlineSeconds);
    const request = buildActionRequestFromProof({
      appId: this.ctx.config.appId,
      actionType: this.ctx.config.actionTypes.membership,
      contextId,
      verifierId: this.ctx.config.verifierIds.membership,
      deadline,
      encryptedPayloadRef,
      bundle: proofBundle,
      adapterData: "0x"
    });
    return {
      request,
      proofBundle,
      root: proofBundle.publicInputs[5]
    };
  }
  async execute(input) {
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
  async computeExpectedRoot(input) {
    const leaf = await deriveMembershipLeaf(input.identitySecret, input.membershipSecret);
    return deriveMerkleRoot(leaf, input.pathElements, input.pathIndices);
  }
  async computeExpectedNullifier(input) {
    return deriveNullifier(
      input.nullifierSecret,
      this.ctx.config.appId,
      this.ctx.config.actionTypes.membership,
      asBytes32(input.contextId)
    );
  }
  async getContextState(contextId) {
    const id = asBytes32(contextId);
    try {
      const result = await this.ctx.publicClient.readContract({
        address: this.ctx.config.adapters.membership,
        abi: MEMBERSHIP_ADAPTER_ABI,
        functionName: "contextConfig",
        args: [id]
      });
      const typed = result;
      return {
        enabled: typed.enabled,
        requirePayload: typed.requirePayload,
        requireEncryptedPayloadRef: typed.requireEncryptedPayloadRef,
        validAfter: typed.validAfter,
        validUntil: typed.validUntil
      };
    } catch (error) {
      const msg = error instanceof import_viem8.BaseError ? error.shortMessage : "Failed to read membership context";
      throw new CipherError("TRANSACTION_ERROR", msg, error);
    }
  }
  async isRootAllowed(contextId, root) {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.membership,
      abi: MEMBERSHIP_ADAPTER_ABI,
      functionName: "allowedRoots",
      args: [asBytes32(contextId), asBytes32(root)]
    });
  }
};

// src/adapters/voting.ts
var import_viem9 = require("viem");
var VotingModule = class {
  constructor(ctx) {
    this.ctx = ctx;
  }
  async buildProofInput(input) {
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
    const proofInput = {
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
  async prepare(input) {
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
    let encryptedPayloadRef = ZERO_BYTES32;
    let adapterData = "0x";
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
        adapterData = input.encryption.inline ? encodeVoteAdapterData(encrypted.ciphertext) : "0x";
      } catch (error) {
        throw new CipherError("ENCRYPTION_PROVIDER_ERROR", "Failed to encrypt/store vote payload", error);
      }
    }
    const deadlineSeconds = input.deadlineSecondsFromNow ?? 1200;
    const deadline = BigInt(Math.floor(Date.now() / 1e3) + deadlineSeconds);
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
  async execute(input) {
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
  async computeExpectedRoot(input) {
    const leaf = await deriveMembershipLeaf(input.identitySecret, input.membershipSecret);
    return deriveMerkleRoot(leaf, input.pathElements, input.pathIndices);
  }
  async computeExpectedNullifier(input) {
    return deriveNullifier(
      input.nullifierSecret,
      this.ctx.config.appId,
      this.ctx.config.actionTypes.voting,
      asBytes32(input.contextId)
    );
  }
  async getVote(actionId) {
    const result = await this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "getVote",
      args: [asBytes32(actionId)]
    });
    const typed = result;
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
  async getTally(contextId) {
    const result = await this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "getTally",
      args: [asBytes32(contextId)]
    });
    const typed = result;
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
  async isTallyFinalized(contextId) {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "isTallyFinalized",
      args: [asBytes32(contextId)]
    });
  }
  async getContextLink(contextId) {
    const result = await this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "getContextLink",
      args: [asBytes32(contextId)]
    });
    const typed = result;
    return {
      dao: typed.dao,
      externalReference: typed.externalReference,
      linked: typed.linked
    };
  }
  async computeContextId(dao, externalReference) {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "computeContextId",
      args: [dao, asBytes32(externalReference)]
    });
  }
  async getProposalState(contextId) {
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
      const typed = config;
      return {
        enabled: typed.enabled,
        requirePayload: typed.requirePayload,
        requireEncryptedPayload: typed.requireEncryptedPayload,
        startTime: typed.startTime,
        endTime: typed.endTime,
        voteCount
      };
    } catch (error) {
      const msg = error instanceof import_viem9.BaseError ? error.shortMessage : "Failed to read voting state";
      throw new CipherError("TRANSACTION_ERROR", msg, error);
    }
  }
  async isRootAllowed(contextId, root) {
    return this.ctx.publicClient.readContract({
      address: this.ctx.config.adapters.voting,
      abi: VOTING_ADAPTER_ABI,
      functionName: "allowedRoots",
      args: [asBytes32(contextId), asBytes32(root)]
    });
  }
};

// src/client/CipherClient.ts
var CipherClient = class {
  constructor(params) {
    this.config = params.config;
    this.walletClient = params.walletClient;
    this.publicClient = params.publicClient;
    this.providers = params.providers;
    this.defaultAdapter = params.defaultAdapter;
    const ctx = {
      config: params.config,
      walletClient: params.walletClient,
      publicClient: params.publicClient,
      providers: params.providers
    };
    this.membership = new MembershipModule(ctx);
    this.voting = new VotingModule(ctx);
  }
  // ergonomic one-shot alias for voting flow
  async vote(input) {
    return this.voting.execute(input);
  }
  // ergonomic one-shot alias for membership flow
  async join(input) {
    return this.membership.execute(input);
  }
  async execute(input) {
    if (!this.defaultAdapter) {
      throw new CipherError(
        "TRANSACTION_ERROR",
        "No default adapter configured. Use cipher.join(...) or cipher.vote(...), or pass adapter in createCipherClient."
      );
    }
    if (this.defaultAdapter === "membership") {
      return this.membership.execute(input);
    }
    return this.voting.execute(input);
  }
  async generateProof(params) {
    return this.providers.proofProvider.generateProof(params);
  }
  async submitAction(request) {
    return submitCipherAction({
      routerAddress: this.config.routerAddress,
      walletClient: this.walletClient,
      publicClient: this.publicClient,
      request
    });
  }
  async computeNullifierKey(params) {
    return readRouterComputedNullifierKey({
      publicClient: this.publicClient,
      routerAddress: this.config.routerAddress,
      appId: this.config.appId,
      actionType: params.actionType,
      contextId: params.contextId,
      nullifier: params.nullifier
    });
  }
  async isNullifierUsed(nullifierKey) {
    return isNullifierUsed({
      publicClient: this.publicClient,
      nullifierStoreAddress: this.config.nullifierStoreAddress,
      nullifierKey
    });
  }
  async routerState() {
    return readRouterPointers({
      publicClient: this.publicClient,
      routerAddress: this.config.routerAddress
    });
  }
  async getAdapter(workflow) {
    return readAdapterAddress({
      publicClient: this.publicClient,
      adapterRegistryAddress: this.config.adapterRegistryAddress,
      appId: this.config.appId,
      actionType: this.config.actionTypes[workflow]
    });
  }
  async getVerifier(workflow) {
    return readVerifierConfig({
      publicClient: this.publicClient,
      verifierRegistryAddress: this.config.verifierRegistryAddress,
      verifierId: this.config.verifierIds[workflow]
    });
  }
  parseReceiptLogs(receipt) {
    return parseCipherLogs(receipt.logs);
  }
};

// src/client/createCipherClient.ts
function createCipherClient(options) {
  const { resolved, publicClient } = resolveCipherConfig(options);
  return new CipherClient({
    config: resolved,
    walletClient: options.walletClient,
    publicClient,
    providers: getCipherGlobalProviders(),
    defaultAdapter: options.adapter
  });
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  BrowserCipherProofProvider,
  CIPHER_ACTION_TYPES,
  CIPHER_DEPLOYMENTS,
  CIPHER_VERIFIER_IDS,
  CipherClient,
  CipherError,
  NoopCipherEncryptionProvider,
  NoopCipherPayloadStorageProvider,
  ZERO_ADDRESS,
  ZERO_BYTES32,
  assertProofBindings,
  buildActionRequestFromProof,
  configureCipherGlobalProviders,
  createCipherClient,
  deriveMembershipLeaf,
  deriveMerkleRoot,
  deriveNullifier,
  derivePayloadHash,
  deriveVotingPayloadDigest,
  encodeVoteAdapterData,
  getCipherGlobalProviders,
  hash2,
  hash3,
  hash6,
  parseCipherLogs,
  resolveCipherConfig
});
//# sourceMappingURL=index.cjs.map