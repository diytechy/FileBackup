//! Generate carried Unicode path-comparison data from the exact locked libraries.
use caseless::Caseless;
use unicode_normalization::{UnicodeNormalization, char::canonical_combining_class};
fn main() {
    println!(
        "# FileBackup path key v1: character<TAB>NFD full-fold NFD<TAB>canonical combining class"
    );
    for code in 0..=0x10ffff {
        if let Some(c) = char::from_u32(code) {
            let text = c.to_string();
            let key: String = text.nfd().default_case_fold().nfd().collect();
            let class = canonical_combining_class(c);
            if key != text || class != 0 {
                println!("{text}\t{key}\t{class}");
            }
        }
    }
}
