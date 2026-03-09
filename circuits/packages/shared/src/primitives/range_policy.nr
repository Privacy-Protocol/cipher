pub fn prove_threshold(value: u32, threshold: u32) {
    assert(value >= threshold);
}

pub fn prove_vote_option(vote_option: u8, option_count: u8) {
    assert(option_count > 0);
    assert(vote_option < option_count);
}
