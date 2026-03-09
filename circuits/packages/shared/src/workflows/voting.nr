use crate::primitives::hash::hash2;
use crate::primitives::membership;
use crate::primitives::nullifier;
use crate::primitives::payload_binding;
use crate::primitives::range_policy;

// VotingCircuit (v1)
// Public: app_id, action_type, context_id, root, nullifier, payload_hash, schema_hash, option_count
// Private: identity_secret, membership_secret, nullifier_secret, path_elements, path_indices, vote_option, vote_blinding,
//          payload_salt
pub fn prove_voting(
    app_id: Field,
    action_type: Field,
    context_id: Field,
    root: Field,
    nullifier_hash: Field,
    payload_hash: Field,
    schema_hash: Field,
    option_count: u8,
    identity_secret: Field,
    membership_secret: Field,
    nullifier_secret: Field,
    path_elements: [Field; 20],
    path_indices: [bool; 20],
    vote_option: u8,
    vote_blinding: Field,
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

    range_policy::prove_vote_option(vote_option, option_count);

    // The proof binds valid vote encoding to payload_hash commitment.
    let vote_digest = hash2(vote_option as Field, vote_blinding);
    payload_binding::prove_payload_binding(
        payload_hash,
        app_id,
        action_type,
        context_id,
        schema_hash,
        vote_digest,
        payload_salt,
    );
}
