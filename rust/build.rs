use std::{env, fs, path::PathBuf};
fn main() {
    println!("cargo:rerun-if-env-changed=FILEBACKUP_HASH_DLL");
    let dll=env::var_os("FILEBACKUP_HASH_DLL").map(PathBuf::from).or_else(|| {
        env::var_os("LOCALAPPDATA").map(|p|PathBuf::from(p).join("PackageManagement/NuGet/Packages/System.IO.Hashing.8.0.0/lib/netstandard2.0/System.IO.Hashing.dll"))
    });
    let destination = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("System.IO.Hashing.dll");
    match dll.filter(|p| p.is_file()) {
        Some(path) => {
            println!("cargo:rerun-if-changed={}", path.display());
            fs::copy(path, destination).expect("copy carried hash library");
        }
        None => {
            fs::write(destination, []).unwrap();
            println!(
                "cargo:warning=No FILEBACKUP_HASH_DLL: native backup/kit publication will refuse; pure checks remain available."
            );
        }
    }
}
