use dep::cipher_primitives::primitives::hash::hash2;
use dep::cipher_primitives::primitives::membership;
use dep::cipher_primitives::primitives::nullifier;
use dep::cipher_primitives::primitives::payload_binding;
use dep::cipher_primitives::workflows::voting;

// Voting entry circuit.
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
    option_count: pub u8,
    identity_secret: Field,
    membership_secret: Field,
    nullifier_secret: Field,
    path_elements: [Field; 20],
    path_indices: [bool; 20],
    vote_option: u8,
    vote_blinding: Field,
    payload_salt: Field,
) {
    voting::prove_voting(
        app_id,
        action_type,
        context_id,
        root,
        nullifier_hash,
        payload_hash,
        schema_hash,
        option_count,
        identity_secret,
        membership_secret,
        nullifier_secret,
        path_elements,
        path_indices,
        vote_option,
        vote_blinding,
        payload_salt,
    );
}

#[test]
fn test_voting_flow() {
    let app_id = 11;
    let action_type = 22;
    let context_id = 33;

    let identity_secret = 1234;
    let membership_secret = 5678;
    let nullifier_secret = 9012;

    let path_elements: [Field; 20] = [0; 20];
    let path_indices: [bool; 20] = [false; 20];

    let leaf = membership::member_leaf(identity_secret, membership_secret);
    let root = membership::compute_merkle_root(leaf, path_elements, path_indices);
    let nullifier_hash = nullifier::derive_nullifier(
        nullifier_secret,
        nullifier::nullifier_scope(app_id, action_type, context_id),
    );

    let option_count = 3;
    let vote_option = 1;
    let vote_blinding = 777;
    let payload_salt = 888;
    let schema_hash = 444;
    let payload_hash = payload_binding::derive_payload_hash(
        app_id,
        action_type,
        context_id,
        schema_hash,
        hash2(vote_option as Field, vote_blinding),
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
        option_count,
        identity_secret,
        membership_secret,
        nullifier_secret,
        path_elements,
        path_indices,
        vote_option,
        vote_blinding,
        payload_salt,
    );
}
