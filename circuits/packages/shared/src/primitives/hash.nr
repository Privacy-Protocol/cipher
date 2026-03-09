use dep::poseidon::poseidon2::Poseidon2::hash;

pub fn hash2(a: Field, b: Field) -> Field {
    hash([a, b], 2)
}

pub fn hash3(a: Field, b: Field, c: Field) -> Field {
    hash([a, b, c], 3)
}

pub fn hash6(a: Field, b: Field, c: Field, d: Field, e: Field, f: Field) -> Field {
    hash([a, b, c, d, e, f], 6)
}
