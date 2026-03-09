use dep::cipher_primitives::primitives::membership;
use dep::cipher_primitives::primitives::nullifier;
use dep::cipher_primitives::primitives::payload_binding;
use dep::cipher_primitives::workflows::credential_gate;

// Credential gate entry circuit.
// Public input order is aligned with Router binding:
// [app_id, action_type, context_id, nullifier_hash, payload_hash, root]
fn main(
    app_id: pub Field,
    action_type: pub Field,
    context_id: pub Field,
    nullifier_hash: pub Field,
    payload_hash: pub Field,
    root: pub Field,
    schema_hash: pub Field,
    threshold: pub u32,
    enforce_threshold: pub bool,
    identity_secret: Field,
    membership_secret: Field,
    nullifier_secret: Field,
    path_elements: [Field; 20],
    path_indices: [bool; 20],
    attribute_value: u32,
    payload_digest: Field,
    payload_salt: Field,
) {
    credential_gate::prove_credential_gate(
        app_id,
        action_type,
        context_id,
        root,
        nullifier_hash,
        payload_hash,
        schema_hash,
        threshold,
        enforce_threshold,
        identity_secret,
        membership_secret,
        nullifier_secret,
        path_elements,
        path_indices,
        attribute_value,
        payload_digest,
        payload_salt,
    );
}

#[test]
fn test_credential_gate_with_optional_payload() {
    let app_id = 111;
    let action_type = 222;
    let context_id = 333;

    let identity_secret = 10;
    let membership_secret = 20;
    let nullifier_secret = 30;

    let path_elements: [Field; 20] = [0; 20];
    let path_indices: [bool; 20] = [false; 20];

    let leaf = membership::member_leaf(identity_secret, membership_secret);
    let root = membership::compute_merkle_root(leaf, path_elements, path_indices);
    let nullifier_hash = nullifier::derive_nullifier(
        nullifier_secret,
        nullifier::nullifier_scope(app_id, action_type, context_id),
    );

    main(
        app_id,
        action_type,
        context_id,
        nullifier_hash,
        0,
        root,
        0,
        0,
        false,
        identity_secret,
        membership_secret,
        nullifier_secret,
        path_elements,
        path_indices,
        999,
        0,
        0,
    );
}

#[test]
fn test_credential_gate_with_payload_binding() {
    let app_id = 211;
    let action_type = 312;
    let context_id = 413;

    let identity_secret = 44;
    let membership_secret = 55;
    let nullifier_secret = 66;

    let path_elements: [Field; 20] = [0; 20];
    let path_indices: [bool; 20] = [false; 20];

    let leaf = membership::member_leaf(identity_secret, membership_secret);
    let root = membership::compute_merkle_root(leaf, path_elements, path_indices);
    let nullifier_hash = nullifier::derive_nullifier(
        nullifier_secret,
        nullifier::nullifier_scope(app_id, action_type, context_id),
    );

    let schema_hash = 900;
    let payload_digest = 123456;
    let payload_salt = 654321;
    let payload_hash = payload_binding::derive_payload_hash(
        app_id,
        action_type,
        context_id,
        schema_hash,
        payload_digest,
        payload_salt,
    );

    main(
        app_id,
        action_type,
        context_id,
        nullifier_hash,
        payload_hash,
        root,
        schema_hash,
        10,
        true,
        identity_secret,
        membership_secret,
        nullifier_secret,
        path_elements,
        path_indices,
        11,
        payload_digest,
        payload_salt,
    );
}
