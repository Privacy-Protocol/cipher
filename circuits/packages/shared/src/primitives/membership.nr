use crate::primitives::hash::hash2;

pub fn member_leaf(identity_secret: Field, membership_secret: Field) -> Field {
    hash2(identity_secret, membership_secret)
}

pub fn compute_merkle_root(
    mut leaf: Field,
    path_elements: [Field; 20],
    path_indices: [bool; 20],
) -> Field {
    for i in 0..20 {
        if path_indices[i] {
            leaf = hash2(path_elements[i], leaf);
        } else {
            leaf = hash2(leaf, path_elements[i]);
        }
    }

    leaf
}

pub fn prove_membership(
    root: Field,
    leaf: Field,
    path_elements: [Field; 20],
    path_indices: [bool; 20],
) {
    assert(compute_merkle_root(leaf, path_elements, path_indices) == root);
}
