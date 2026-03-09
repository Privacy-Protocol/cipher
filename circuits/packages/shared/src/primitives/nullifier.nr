use crate::primitives::hash::{hash2, hash3};

fn nullifier_domain() -> Field {
    1001
}

pub fn nullifier_scope(app_id: Field, action_type: Field, context_id: Field) -> Field {
    hash3(app_id, action_type, context_id)
}

pub fn derive_nullifier(nullifier_secret: Field, scope: Field) -> Field {
    hash2(nullifier_secret, hash2(scope, nullifier_domain()))
}

pub fn prove_nullifier(
    nullifier: Field,
    nullifier_secret: Field,
    app_id: Field,
    action_type: Field,
    context_id: Field,
) {
    let scope = nullifier_scope(app_id, action_type, context_id);
    let expected = derive_nullifier(nullifier_secret, scope);
    assert(expected == nullifier);
}
