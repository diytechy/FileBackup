//! Prints, per file, what the compression probe would see: the length, the
//! planned window offsets, each window's Brotli ratio and the three
//! combinations with their verdicts at SR-081's 0.90 (LLR-162). Read-only;
//! uses the engine's own plan and measuring functions.
use filebackup::{engine, format};
use std::{
    fs::File,
    io::{Read, Seek, SeekFrom},
};

fn main() -> anyhow::Result<()> {
    for path in std::env::args().skip(1) {
        let mut file = File::open(&path)?;
        let length = file.metadata()?.len();
        let plan = format::probe_plan(length);
        println!("{path}\tlength={length}");
        if plan.is_empty() {
            println!("  not measured (at or under 256 KiB)");
            continue;
        }
        let mut windows = Vec::new();
        for &(start, len) in &plan {
            let mut buffer = vec![0u8; len];
            file.seek(SeekFrom::Start(start))?;
            file.read_exact(&mut buffer)?;
            windows.push(buffer);
        }
        let refs: Vec<&[u8]> = windows.iter().map(Vec::as_slice).collect();
        let (ratios, combos) = engine::probe_summary(&refs)?;
        println!(
            "  offsets={}",
            plan.iter()
                .map(|p| p.0.to_string())
                .collect::<Vec<_>>()
                .join(",")
        );
        println!(
            "  ratios={}",
            ratios
                .iter()
                .map(|r| format!("{r:.4}"))
                .collect::<Vec<_>>()
                .join(",")
        );
        for (name, value, compress) in combos {
            println!(
                "  {name}={value:.4} {}",
                if compress { "compress" } else { "raw" }
            );
        }
    }
    Ok(())
}
