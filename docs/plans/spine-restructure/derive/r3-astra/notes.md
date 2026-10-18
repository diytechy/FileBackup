# Exposure notes

Opening context included a substantial, truncated copy of the repository AGENTS.md, including architecture, generated function maps, and invariants. This was exposure before reading the brief.

The brief contains an apparent blindness exception: its general prohibition on other derive directories conflicts with its specifically authorized r2-merged/merge-notes.md section. Only that named section will be read, as an explicit input exception. No other deriver output will be read.

The shell tool failed before executing the initial read. File access uses the Node runtime instead. Tool discovery exposed tool descriptions only, not additional repository material.

## Exposure record

I worked alone and did not inspect another round-3 deriver’s output. The only other derive location accessed was the explicitly named r2-merged/merge-notes.md input. The file was buffered by the file-reading tool to extract “Moved to the design tier”; only that authorized section was displayed for design use. This is the specific-input exception to the brief’s broader derive-directory prohibition, not general permission to inspect that directory.

Reviewed inputs were the derivation brief; the supplied opening AGENTS.md material; README selections; stakeholder-needs.toml, system-requirements.toml, external.toml, assumptions.toml and hats.toml; the legacy interfaces.csv and low-level-requirements.csv; strip/final/llr.json, sr.json and sn.json; harvest/tc.json; the authorized merge-notes section; and gap-map Appendix C. Code exposure comprised Modules/FileBackup.Common.psm1, Modules/FileBackup.Engine.psm1, FileBackup.ps1, Reconstruct.ps1, bash/reconstruct.sh, container/entrypoint.sh, container/FileBackup.schema.json and CredSetEx.ps1. Directory inventories were used to identify the permitted code inputs. No test source or implementation outside the allowed code list was opened.

The ai-template pointer-rules.md was read in full. The spine-questions.md file was buffered for section extraction; sections 0 and 3 were the requested design guidance. An initial broad excerpt also exposed surrounding question sections. An Appendix-C extraction from spine-restructure-gap-map.md accidentally continued into Appendix D’s test-tier summary. That was additional exposure outside the requested appendix; it was not used as a design answer or a source of new test obligations. No competing design output was opened.

Tool discovery exposed tool names/descriptions. Environment checks exposed Python executable locations, Python version/import availability and PATH; attempts to locate newer Python versions failed. One user-program directory listing was denied before returning entries. No package was installed or downloaded. The initial shell-helper failure occurred before the requested command executed; subsequent file operations used the Node runtime. No product tests, build, generators or repository mutation commands ran.

## Output and validation

Authored only components.toml, interfaces.toml, low-level-requirements.toml, mapping.md, design-gaps.md and this notes.md inside the designated output directory. The directory also contains run.log, which I did not create, read, alter or remove. No intentional write was made outside this directory. Python validation used -B to disable bytecode writes.

All three carriers parse with the installed Python 3.8 tomli parser. **The expressly requested Python standard-library tomllib validation remains outstanding:** the available interpreter lacks it; the configured newer Python paths and the project virtual environment point to absent interpreters. I did not substitute a module alias and claim a standard-library validation. A Python 3.11+ environment can perform the remaining check without bytecode writes using `python -B -c "import pathlib,tomllib; [tomllib.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('.').glob('*.toml')]"` from this output directory.

The executed structural checks passed: all referenced SR, LLR parent, component parent, interface, external endpoint, boundary, assumption and hat IDs resolve; component, LLR and carrier links are acyclic; no LLR has both parent and sr_refs; every interface is constrained by an LLR or a listed direct SR pair; all 123 SRs reach a top-level LLR; all rows are Drafted; dimensions satisfy the set/range/bool sampling grammar; hats do not repeat inherited SR hats. Boundary bridge assumptions were also checked against their declared crossings.

The carriers were scanned against all named functions extracted from the inspected implementation and against code-file extensions; no matches occurred. Manual text review separates interface form from behavior and uses only shipped-record names in LLRs. No LLR contains shall or module/code_symbol/component placement fields. The mapping has exactly one leading disposition for each ID LLR-001 through LLR-094, including the 11 IDs absent from the supplied carrier; none of those absent IDs was reused. Rationale describes tradeoffs rather than implementation history.

Counts: 16 components; 40 interfaces (28 boundary, 12 internal); 85 LLRs (75 top-level, 10 child); 63 legacy LLR IDs kept; 36 evidenced design gaps. Design choices and evidence limits are recorded separately from the gap count. Coverage is a design traceability result, not a claim that current code meets the rows.
