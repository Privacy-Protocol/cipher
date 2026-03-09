use crate::primitives::hash::hash6;

fn payload_domain() -> Field {
    2001
}

pub fn derive_payload_hash(
    app_id: Field,
    action_type: Field,
    context_id: Field,
    schema_hash: Field,
    payload_digest: Field,
    payload_salt: Field,
) -> Field {
    hash6(
        app_id,
        action_type,
        context_id,
        schema_hash,
        payload_digest,
        hash6(payload_salt, payload_domain(), 0, 0, 0, 0),
    )
}

pub fn prove_payload_binding(
    payload_hash: Field,
    app_id: Field,
    action_type: Field,
    context_id: Field,
    schema_hash: Field,
    payload_digest: Field,
    payload_salt: Field,
) {
    let expected = derive_payload_hash(
        app_id,
        action_type,
        context_id,
        schema_hash,
        payload_digest,
        payload_salt,
    );
    assert(expected == payload_hash);
}
