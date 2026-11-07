//! Explicit maintenance; read-only inspection writes only external scratch.
use crate::{
    config::BackupSet,
    engine::Report,
    format::{self, ContentKey},
    kit, platform,
    progress::{Counters, Phase, Reporter},
    store::{Store, is_state_file, snapshot_order},
    tools,
};
use anyhow::{Context, Result, ensure};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File},
    io::Write,
    path::Path,
    sync::Arc,
};

pub fn snapshots(set: &BackupSet) -> Result<Vec<String>> {
    let store = Store::new(&set.store);
    ensure!(!store.admit()?, "store has no saved state");
    Ok(store
        .states()?
        .into_iter()
        .skip(1)
        .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
        .collect())
}
pub fn inventory(set: &BackupSet) -> Report {
    let mut report = Report::new("snapshots", &set.name);
    let work = |report: &mut Report| -> Result<()> {
        let store = Store::new(&set.store);
        let mut states = Vec::new();
        for state in store.states()? {
            let name = if state.as_path() == store.current.as_ref() {
                "CurrentBackup".into()
            } else {
                state.file_name().unwrap().to_string_lossy().into_owned()
            };
            match format::read_manifest(&state.join(format::MANIFEST)) {
                Ok(rows) => states.push(serde_json::json!({"state":name,"logical_files":rows.len(),
                    "logical_bytes":rows.iter().map(|r| r.length as u128).sum::<u128>().to_string()})),
                Err(e) => {
                    report.finding_at(1,"file_records_unavailable",Some(&name),format!("State inventory unavailable: {e:#}"));
                    states.push(serde_json::json!({"state":name,"logical_files":null,"logical_bytes":null}));
                }
            }
        }
        report.details = Some(serde_json::json!({"states":states,
            "removal_advice":"Use prune --snapshot DATE --dry-run for selection-specific estimates. Removing a date may invalidate older states; complete-store handoff is required."}));
        Ok(())
    };
    if let Err(e) = work(&mut report) {
        report.finding(4, format!("Inventory unavailable: {e:#}"));
    }
    report
}
// Implements: LLR-191.
pub fn verify(set: &BackupSet, deep: bool, repair: bool) -> Report {
    let reporter = Reporter::start(&set.name);
    let mut report = Report::new(if repair { "repair" } else { "verify" }, &set.name);
    report.details = Some(
        serde_json::json!({"inspection_mode":if deep || repair {"verified_content"} else {"metadata_only"}}),
    );
    if !deep && !repair {
        report.finding_at(
            0,
            "metadata_only",
            None,
            "Quick inspection checks records and object shape; use --deep to verify content bytes"
                .into(),
        );
    }
    if let Err(e) = verify_inner(set, deep, repair, &mut report, reporter.counters()) {
        report.finding(4, format!("{e:#}"));
    }
    report
}
fn verify_inner(
    set: &BackupSet,
    deep: bool,
    repair: bool,
    report: &mut Report,
    counters: &Arc<Counters>,
) -> Result<()> {
    let store = Store::new(&set.store);
    ensure!(
        store.current.is_dir() && store.history.is_dir(),
        "store unavailable"
    );
    let _lock = if repair {
        Some(platform::StoreLock::acquire(&store.root)?)
    } else {
        None
    };
    counters.enter(Phase::IndexingStore);
    let index = store.index()?;
    let mut verdicts: BTreeMap<&Path, Option<tools::StoredForm>> = BTreeMap::new();
    let states = store.states()?;
    // A deep pass hashes each object once, so objects are its measure. A quick pass
    // has no total before it reads each manifest, so it counts states and records.
    if deep || repair {
        let objects = index.values().map(Vec::len).sum::<usize>();
        counters.enter_counted(Phase::DeepVerify, objects as u64);
    } else {
        counters.enter_counted(Phase::QuickVerify, states.len() as u64);
    }
    for state in states {
        let path = state.join(format::MANIFEST);
        let before = match fs::metadata(&path).and_then(|m| m.modified()) {
            Ok(stamp) => stamp,
            Err(e) => {
                report.finding_at(
                    1,
                    "file_records_unavailable",
                    Some(&path.to_string_lossy()),
                    format!("Cannot inspect this state's records: {e}"),
                );
                continue;
            }
        };
        let directories = format::read_directories(&state.join(format::DIRECTORIES));
        if let Err(e) = &directories {
            report.finding_at(
                1,
                "metadata_invalid",
                Some(&state.to_string_lossy()),
                format!("Required supplemental metadata invalid: {e:#}"),
            );
        }
        let mut rows = match format::read_manifest(&path) {
            Ok(rows) => rows,
            Err(e) => {
                report.finding_at(
                    1,
                    "file_records_invalid",
                    Some(&path.to_string_lossy()),
                    format!("Invalid file records: {e:#}"),
                );
                continue;
            }
        };
        if let Ok(dirs) = &directories
            && let Err(e) = format::validate_records(&rows, dirs)
        {
            report.finding_at(
                1,
                "metadata_conflict",
                Some(&state.to_string_lossy()),
                format!("Conflicting supplemental metadata: {e:#}"),
            );
        }
        let mut changed = false;
        for row in &mut rows {
            counters.record_seen();
            let mut usable = false;
            let mut unavailable = false;
            if let Some(objects) = index.get(&row.key()) {
                for object in objects {
                    let form = if deep || repair {
                        if let Some(form) = verdicts.get(object.path.as_path()) {
                            *form
                        } else {
                            match tools::verify_form_counted(&object.path, &row.key(), counters) {
                                Ok(form) => {
                                    verdicts.insert(object.path.as_path(), form);
                                    counters.item_done();
                                    form
                                }
                                Err(e) => {
                                    unavailable = true;
                                    report.finding_at(
                                        4,
                                        "verification_unavailable",
                                        Some(&object.path.to_string_lossy()),
                                        format!("Cannot verify content: {e:#}"),
                                    );
                                    continue;
                                }
                            }
                        }
                    } else {
                        let n = match fs::metadata(&object.path) {
                            Ok(metadata) => metadata.len(),
                            Err(e) => {
                                unavailable = true;
                                report.finding_at(
                                    4,
                                    "verification_unavailable",
                                    Some(&object.path.to_string_lossy()),
                                    format!("Object became unavailable during inspection: {e}"),
                                );
                                continue;
                            }
                        };
                        tools::listed_form(&object.path, n, row.length)
                    };
                    if let Some(form) = form {
                        usable = true;
                        if deep || repair {
                            let flag = if form == tools::StoredForm::Raw {
                                "No"
                            } else {
                                "Yes"
                            };
                            if row.compressed != flag {
                                report.finding_at(
                                    1,
                                    "storage_form_mismatch",
                                    Some(&row.relative_path),
                                    format!(
                                        "Stored form differs from record in {}",
                                        state.display()
                                    ),
                                );
                                if repair {
                                    row.compressed = flag.into();
                                    row.data_path = object.name.clone();
                                    changed = true;
                                }
                            }
                        }
                        break;
                    } else if !deep && !repair {
                        report.finding_at(
                            1,
                            "object_damaged",
                            Some(&object.path.to_string_lossy()),
                            "Object shape disagrees with its recorded identity".into(),
                        );
                    }
                }
            }
            if usable {
                report.reused += 1;
            } else {
                report.failed += 1;
                if unavailable {
                    continue;
                }
                report.finding_at(
                    1,
                    if index.contains_key(&row.key()) {
                        "content_damaged"
                    } else {
                        "content_missing"
                    },
                    Some(&row.relative_path),
                    format!("Missing/damaged content in {}", state.display()),
                );
            }
        }
        if fs::metadata(&path).and_then(|m| m.modified()).ok() != Some(before) {
            report.finding_at(
                1,
                "concurrent_change",
                Some(&path.to_string_lossy()),
                "Metadata changed during inspection; no metadata repair published".into(),
            );
        } else if changed {
            platform::atomic_write_with(&path, true, |file| format::write_manifest(file, &rows))?;
        }
        if !deep && !repair {
            counters.item_done();
        }
    }
    for objects in index.values() {
        if objects.len() > 1 {
            report.finding_at(
                1,
                "duplicate_object",
                None,
                format!("{} physical copies for one content identity", objects.len()),
            );
        }
        let mut good = Vec::new();
        for object in objects {
            if deep || repair {
                let form = if let Some(form) = verdicts.get(object.path.as_path()) {
                    *form
                } else {
                    match tools::verify_form_counted(&object.path, &object.key, counters) {
                        Ok(form) => {
                            counters.item_done();
                            form
                        }
                        Err(e) => {
                            report.finding_at(
                                4,
                                "verification_unavailable",
                                Some(&object.path.to_string_lossy()),
                                format!("Cannot verify object: {e:#}"),
                            );
                            continue;
                        }
                    }
                };
                if form.is_some() {
                    good.push(object.path.clone());
                } else {
                    report.finding_at(
                        1,
                        "object_damaged",
                        Some(&object.path.to_string_lossy()),
                        "Stored object does not match its identity".into(),
                    );
                }
            }
        }
        if repair && let Some(keeper) = good.first() {
            for object in objects {
                if &object.path != keeper {
                    ensure!(
                        tools::verify(keeper, &object.key)?,
                        "retained supply changed before repair"
                    );
                    store.quarantine(&object.path)?;
                    report.finding_at(
                        0,
                        "object_quarantined",
                        Some(&object.path.to_string_lossy()),
                        "Duplicate/uncertain bytes preserved in Verify".into(),
                    );
                }
            }
        }
    }
    platform::checkpoint("verify-objects-checked");
    for path in store.misplaced()? {
        report.finding_at(
            1,
            "object_misplaced",
            Some(&path.to_string_lossy()),
            "Object is outside its declared shard; not usable pool supply".into(),
        );
        if repair {
            // An only copy goes home, not aside; its bytes must prove its name.
            let name = path
                .file_name()
                .and_then(|n| n.to_str())
                .context("non-Unicode object name")?;
            let home = store.path(name)?;
            if !home.try_exists()? && tools::verify(&path, &format::parse_name(name)?)? {
                let parent = home.parent().context("object has no shard")?;
                fs::create_dir_all(parent)?;
                platform::ordinary_dir(parent)?;
                fs::rename(&path, &home)?;
                platform::sync_directory(path.parent().context("object has no folder")?)?;
                platform::sync_directory(parent)?;
            } else {
                store.quarantine(&path)?;
            }
        }
    }
    Ok(())
}
pub fn prune(set: &BackupSet, names: &[String], dry_run: bool) -> Report {
    let mut report = Report::new("prune", &set.name);
    if let Err(e) = prune_inner(set, names, dry_run, &mut report) {
        let code =
            if platform::is_host_stop(&e) || e.chain().any(|cause| cause.is::<std::io::Error>()) {
                4
            } else {
                2
            };
        report.finding(code, format!("Removal stopped/refused: {e:#}"));
    }
    report
}
fn known_snapshot_files(folder: &Path) -> Result<()> {
    platform::ordinary_dir(folder)?;
    for entry in fs::read_dir(folder)? {
        let entry = entry?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| anyhow::anyhow!("unknown non-Unicode content"))?;
        let metadata = fs::symlink_metadata(entry.path())?;
        if name == "RECOVERY.previous" {
            platform::ordinary_dir(&entry.path())?;
            for member in fs::read_dir(entry.path())? {
                let member = member?;
                let m = fs::symlink_metadata(member.path())?;
                ensure!(
                    platform::is_ordinary_file(&m)
                        && kit::members().any(|n| member.file_name() == n),
                    "unknown previous kit member"
                );
            }
            continue;
        }
        ensure!(
            platform::is_ordinary_file(&metadata),
            "unknown/redirected entry prevents deletion"
        );
        ensure!(
            is_state_file(name.as_ref()) || format::parse_name(&name).is_ok(),
            "unknown content prevents deletion"
        );
    }
    Ok(())
}
fn delete_committed(folder: &Path) -> Result<()> {
    known_snapshot_files(folder)?;
    for entry in fs::read_dir(folder)? {
        let entry = entry?;
        if entry.file_name() == "RECOVERY.previous" {
            for member in fs::read_dir(entry.path())? {
                fs::remove_file(member?.path())?;
            }
            fs::remove_dir(entry.path())?;
        } else {
            fs::remove_file(entry.path())?;
        }
    }
    fs::remove_dir(folder)?;
    Ok(())
}
fn prune_inner(
    set: &BackupSet,
    names: &[String],
    dry_run: bool,
    report: &mut Report,
) -> Result<()> {
    ensure!(!names.is_empty(), "explicit snapshot selection required");
    let store = Store::new(&set.store);
    ensure!(!store.admit()?, "no saved state");
    let _lock = if dry_run {
        None
    } else {
        Some(platform::StoreLock::acquire(&store.root)?)
    };
    let mut selected = BTreeSet::new();
    for name in names {
        ensure!(
            snapshot_order(name).is_some() && !name.contains(['/', '\\']),
            "invalid snapshot identity"
        );
        selected.insert(store.history.join(name));
    }
    let cutoff = selected
        .iter()
        .filter_map(|p| snapshot_order(p.file_name()?.to_str()?))
        .min()
        .context("missing cutoff")?;
    let committed_name = |path: &Path| {
        store.history.join(format!(
            "Pruning_{}",
            path.file_name().unwrap().to_string_lossy()
        ))
    };
    let journal = store.root.join("PrunePlan.json");
    let selection: BTreeSet<String> = names.iter().cloned().collect();
    let resuming = if journal.try_exists()? {
        let prior: BTreeSet<String> = serde_json::from_slice(&fs::read(&journal)?)?;
        ensure!(
            prior == selection,
            "unfinished prune requires the original explicit selection"
        );
        true
    } else {
        false
    };
    for path in &selected {
        let committed = committed_name(path);
        if committed.exists() {
            ensure!(
                !path.exists(),
                "both pending and committed removal identities exist"
            );
            if !dry_run {
                delete_committed(&committed)?;
            }
        } else {
            ensure!(
                path.exists() || resuming,
                "selected snapshot does not exist"
            );
            if path.exists() {
                known_snapshot_files(path)?;
            }
        }
    }
    let index = store.index()?;
    let mut demand: BTreeSet<ContentKey> = BTreeSet::new();
    let mut protected_states = Vec::new();
    for state in store.states()? {
        let protected = state.as_path() == store.current.as_ref()
            || snapshot_order(state.file_name().unwrap().to_str().unwrap())
                .is_some_and(|t| t > cutoff);
        if protected && !selected.contains(&state) {
            protected_states.push(state.file_name().unwrap().to_string_lossy().into_owned());
            for row in format::read_manifest(&state.join(format::MANIFEST))? {
                demand.insert(row.key());
            }
            format::read_directories(&state.join(format::DIRECTORIES))?;
        }
    }
    let previous = store.current.join("MANIFEST.csv.prev");
    if previous.try_exists()? {
        for row in format::read_manifest(&previous)
            .context("previous definitions invalid; cannot prove prune demand")?
        {
            demand.insert(row.key());
        }
    }
    let mut rehome_bytes = 0u128;
    let mut selected_bytes = 0u128;
    for path in &selected {
        if path.exists() {
            for entry in fs::read_dir(path)? {
                let entry = entry?;
                if entry.file_type()?.is_file() {
                    selected_bytes += entry.metadata()?.len() as u128;
                }
            }
        }
    }
    for key in demand {
        let candidates = index.get(&key).context("protected content is missing")?;
        let mut survivor = false;
        let mut source = None;
        for object in candidates {
            if tools::verify(&object.path, &key)? {
                if !selected.contains(object.state.as_ref()) {
                    survivor = true;
                    break;
                }
                source = Some(object);
            }
        }
        if survivor {
            continue;
        }
        let source = source.context("protected content has no usable supply")?;
        rehome_bytes += fs::metadata(&source.path)?.len() as u128;
        report
            .findings
            .push(format!("Rehome protected object: {}", source.name));
        if dry_run {
            continue;
        }
        let destination = store.path(&source.name)?;
        let parent = destination.parent().unwrap();
        fs::create_dir_all(parent)?;
        platform::ordinary_dir(parent)?;
        ensure!(
            !destination.exists(),
            "unusable destination object must be repaired first"
        );
        if let Some(free) = platform::available(parent) {
            ensure!(
                free >= fs::metadata(&source.path)?.len(),
                platform::HostStop("insufficient capacity for required rehome")
            );
        } else {
            report.finding(
                0,
                "Capacity is unavailable; rehome will stop on write failure".into(),
            );
        }
        let mut staged = platform::store_temp_file(parent)?;
        std::io::copy(&mut File::open(&source.path)?, &mut staged)?;
        staged.flush()?;
        staged.as_file().sync_all()?;
        let staged = staged.into_temp_path();
        ensure!(
            tools::verify(&staged, &key)?,
            "rehomed bytes failed verification"
        );
        staged.persist_noclobber(&destination)?;
        platform::sync_directory(parent)?;
        platform::checkpoint("prune-rehome");
    }
    report.details = Some(serde_json::json!({"selected_states":selection,
        "cutoff":cutoff.0.to_rfc3339(),"protected_states":protected_states,
        "estimated_selected_file_bytes":selected_bytes.to_string(),
        "estimated_required_rehome_bytes":rehome_bytes.to_string(),
        "estimated_net_reclaim_bytes":selected_bytes.saturating_sub(rehome_bytes).to_string(),
        "estimate_basis":"Logical lengths of selected regular files minus required verified rehome copies; filesystem allocation, compression, links, previous-kit directories and concurrent changes can differ. Not an exact free-space promise.",
        "recovery_limit":"Latest and retained states later than this cutoff are protected. Older unselected states may become unrestorable; their folders are not deleted."}));
    if !dry_run {
        if !resuming {
            platform::atomic_write(&journal, &serde_json::to_vec(&selection)?, false)?;
        }
        for path in selected {
            if !path.exists() {
                continue;
            }
            let committed = committed_name(&path);
            fs::rename(&path, &committed)?;
            platform::sync_directory(&store.history)?;
            delete_committed(&committed)?;
            platform::checkpoint("prune-deleted");
        }
        fs::remove_file(journal)?;
        platform::sync_directory(&store.root)?;
    }
    Ok(())
}
pub fn refresh(set: &BackupSet) -> Report {
    let mut report = Report::new("refresh-kits", &set.name);
    let work = || -> Result<()> {
        kit::preflight()?;
        let store = Store::new(&set.store);
        ensure!(!store.admit()?, "no saved state");
        let _lock = platform::StoreLock::acquire(&store.root)?;
        for state in store.states()? {
            format::read_directories(&state.join(format::DIRECTORIES))?;
            let prior = state.join("RECOVERY.previous");
            fs::create_dir_all(&prior)?;
            platform::ordinary_dir(&prior)?;
            for name in kit::members() {
                platform::preserve(&state.join(name), &prior.join(name))?;
            }
            kit::publish(&state)?;
        }
        Ok(())
    };
    if let Err(e) = work() {
        report.finding(4, format!("Kit refresh incomplete: {e:#}"));
    }
    report
}
fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
fn file_url(path: &Path) -> String {
    let text = path.to_string_lossy().replace('\\', "/");
    let text = text
        .strip_prefix("//?/UNC/")
        .map(|s| format!("//{s}"))
        .unwrap_or_else(|| text.strip_prefix("//?/").unwrap_or(&text).to_owned());
    let encoded: String = text
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~/:".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    if encoded.starts_with('/') {
        format!("file://{encoded}")
    } else {
        format!("file:///{encoded}")
    }
}
pub fn view(set: &BackupSet) -> Report {
    let mut report = Report::new("view", &set.name);
    let work = || -> Result<()> {
        let store = Store::new(&set.store);
        ensure!(!store.admit()?, "no saved state");
        let _lock = platform::StoreLock::acquire(&store.root)?;
        let root = set.view.as_ref().context("BrowseView=index required")?;
        let stamp = platform::path_identity(&store.root);
        if root.exists() {
            platform::ordinary_dir(root)?;
            for entry in fs::read_dir(root)? {
                ensure!(
                    ["index.html", ".viewstamp"]
                        .iter()
                        .any(|n| entry.as_ref().is_ok_and(|e| e.file_name() == *n)),
                    "view contains unrelated files; refusing replacement"
                );
            }
            if fs::read_dir(root)?.next().is_some() {
                ensure!(
                    fs::read_to_string(root.join(".viewstamp"))? == stamp,
                    "view is not owned by this store"
                );
            }
        } else {
            fs::create_dir_all(root)?;
        }
        platform::atomic_write(&root.join(".viewstamp"), stamp.as_bytes(), true)?;
        let rows = format::read_manifest(&store.current.join(format::MANIFEST))?;
        let index = store.index()?;
        let mut counts = BTreeMap::new();
        for row in &rows {
            *counts.entry(row.key()).or_insert(0usize) += 1;
        }
        let mut html = String::from(
            "<!doctype html><meta charset=utf-8><title>FileBackup view</title><h1>Saved files</h1><label>Search <input id=q></label><table><thead><tr><th>Path</th><th>Logical bytes</th><th>Stored content</th><th>Stored bytes</th><th>Shared</th><th>Media MiB/s</th></tr></thead><tbody>",
        );
        for row in rows {
            let object = index.get(&row.key()).and_then(|v| v.first());
            let (access, size) = if let Some(object) = object
                && let Ok(metadata) = fs::metadata(&object.path)
            {
                (
                    format!(
                        "<a href=\"{}\">{}</a>",
                        file_url(&object.path),
                        if row.compressed == "Yes" {
                            "Archive"
                        } else {
                            "File"
                        }
                    ),
                    metadata.len().to_string(),
                )
            } else {
                ("Unavailable".into(), "Unavailable".into())
            };
            html.push_str(&format!(
                "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
                escape(&row.relative_path),
                row.length,
                access,
                size,
                if counts[&row.key()] > 1 { "Yes" } else { "No" },
                if row.media.is_empty() {
                    "Unavailable".into()
                } else {
                    escape(&row.media)
                }
            ));
        }
        html.push_str("</tbody></table><script>const q=document.getElementById('q');q.oninput=()=>document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q.value.toLowerCase()))</script>");
        platform::atomic_write(&root.join("index.html"), html.as_bytes(), true)?;
        Ok(())
    };
    if let Err(e) = work() {
        report.finding(4, format!("View failed: {e:#}"));
    }
    report
}
