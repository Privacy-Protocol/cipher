use crate::primitives::membership;
use crate::primitives::nullifier;
use crate::primitives::payload_binding;
use crate::primitives::range_policy;

// CredentialGateCircuit (v1)
// Public: app_id, action_type, context_id, root, nullifier, payload_hash, schema_hash, threshold, enforce_threshold
// Private: identity_secret, membership_secret, nullifier_secret, path_elements, path_indices, attribute_value,
//          payload_digest, payload_salt
pub fn prove_credential_gate(
    app_id: Field,
    action_type: Field,
    context_id: Field,
    root: Field,
    nullifier_hash: Field,
    payload_hash: Field,
    schema_hash: Field,
    threshold: u32,
    enforce_threshold: bool,
    identity_secret: Field,
    membership_secret: Field,
    nullifier_secret: Field,
    path_elements: [Field; 20],
    path_indices: [bool; 20],
    attribute_value: u32,
    payload_digest: Field,
    payload_salt: Field,
) {
    let leaf = membership::member_leaf(identity_secret, membership_secret);
    membership::prove_membership(root, leaf, path_elements, path_indices);

    nullifier::prove_nullifier(
        nullifier_hash,
        nullifier_secret,
        app_id,
        action_type,
        context_id,
    );

    if enforce_threshold {
        range_policy::prove_threshold(attribute_value, threshold);
    }

    // Payload commitment is optional for credential-gated flow.
    if payload_hash == 0 {
        assert(schema_hash == 0);
        assert(payload_digest == 0);
        assert(payload_salt == 0);
    } else {
        payload_binding::prove_payload_binding(
            payload_hash,
            app_id,
            action_type,
            context_id,
            schema_hash,
            payload_digest,
            payload_salt,
        );
    }
}
