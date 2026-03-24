use poseidon::poseidon2::Poseidon2;

global TREE_HEIGHT: u32 = 32;

fn compute_membership_leaf(identity_secret: Field) -> Field {
    Poseidon2::hash([identity_secret], 1)
}

fn compute_nullifier(proposal_id: Field, identity_secret: Field) -> Field {
    poseidon2_pair(proposal_id, identity_secret)
}

fn poseidon2_pair(left: Field, right: Field) -> Field {
    Poseidon2::hash([left, right], 2)
}

fn compute_membership_root(
    leaf: Field,
    leaf_index: u32,
    sibling_path: [Field; TREE_HEIGHT],
) -> Field {
    let mut current_hash = leaf;
    let mut current_index = leaf_index;

    for level in 0..TREE_HEIGHT {
        let sibling = sibling_path[level];
        let is_right_child = current_index & 1 == 1;

        if is_right_child {
            current_hash = poseidon2_pair(sibling, current_hash);
        } else {
            current_hash = poseidon2_pair(current_hash, sibling);
        }

        current_index = current_index / 2;
    }

    current_hash
}

fn assert_valid_vote(vote: u8, ballot_size: u8) {
    assert(ballot_size > 0, "ballot size must be non-zero");
    assert(vote < ballot_size, "vote is outside the ballot range");
}

fn main(
    proposal_id: pub Field,
    membership_root: pub Field,
    ballot_size: pub u8,
    nullifier_hash: pub Field,
    identity_secret: Field,
    vote: u8,
    leaf_index: u32,
    sibling_path: [Field; TREE_HEIGHT],
) {
    let membership_leaf = compute_membership_leaf(identity_secret);
    let expected_nullifier = compute_nullifier(proposal_id, identity_secret);
    let computed_root = compute_membership_root(membership_leaf, leaf_index, sibling_path);

    assert_valid_vote(vote, ballot_size);
    assert(nullifier_hash == expected_nullifier, "nullifier does not match the witness");
    assert(computed_root == membership_root, "membership check failed");
}

fn build_test_root(identity_secret: Field, leaf_index: u32) -> Field {
    let leaf = compute_membership_leaf(identity_secret);
    let sibling_path = [0; TREE_HEIGHT];
    compute_membership_root(leaf, leaf_index, sibling_path)
}

#[test]
fn test_main_accepts_valid_member_vote() {
    let proposal_id = 11;
    let identity_secret = 67890;
    let vote: u8 = 2;
    let ballot_size: u8 = 3;
    let leaf_index: u32 = 0;
    let sibling_path = [0; TREE_HEIGHT];
    let membership_root = build_test_root(identity_secret, leaf_index);
    let nullifier_hash = compute_nullifier(proposal_id, identity_secret);

    main(
        proposal_id,
        membership_root,
        ballot_size,
        nullifier_hash,
        identity_secret,
        vote,
        leaf_index,
        sibling_path,
    );
}

#[test(should_fail_with = "vote is outside the ballot range")]
fn test_main_rejects_out_of_range_vote() {
    let proposal_id = 11;
    let identity_secret = 67890;
    let vote: u8 = 3;
    let ballot_size: u8 = 3;
    let leaf_index: u32 = 0;
    let sibling_path = [0; TREE_HEIGHT];
    let membership_root = build_test_root(identity_secret, leaf_index);
    let nullifier_hash = compute_nullifier(proposal_id, identity_secret);

    main(
        proposal_id,
        membership_root,
        ballot_size,
        nullifier_hash,
        identity_secret,
        vote,
        leaf_index,
        sibling_path,
    );
}

#[test(should_fail_with = "nullifier does not match the witness")]
fn test_main_rejects_wrong_nullifier() {
    let proposal_id = 11;
    let identity_secret = 67890;
    let vote: u8 = 1;
    let ballot_size: u8 = 3;
    let leaf_index: u32 = 0;
    let sibling_path = [0; TREE_HEIGHT];
    let membership_root = build_test_root(identity_secret, leaf_index);
    let nullifier_hash = compute_nullifier(proposal_id + 1, identity_secret);

    main(
        proposal_id,
        membership_root,
        ballot_size,
        nullifier_hash,
        identity_secret,
        vote,
        leaf_index,
        sibling_path,
    );
}

#[test(should_fail_with = "membership check failed")]
fn test_main_rejects_wrong_membership_root() {
    let proposal_id = 11;
    let identity_secret = 67890;
    let vote: u8 = 1;
    let ballot_size: u8 = 3;
    let leaf_index: u32 = 0;
    let sibling_path = [0; TREE_HEIGHT];
    let membership_root = build_test_root(identity_secret + 1, leaf_index);
    let nullifier_hash = compute_nullifier(proposal_id, identity_secret);

    main(
        proposal_id,
        membership_root,
        ballot_size,
        nullifier_hash,
        identity_secret,
        vote,
        leaf_index,
        sibling_path,
    );
}
