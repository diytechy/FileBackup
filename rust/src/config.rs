//! IF-002: whole-configuration, nonmutating admission.
use crate::platform::{overlaps, resolve};
use anyhow::{Context, Result, ensure};
use serde_json::{Map, Value};
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug)]
pub struct BackupSet {
    pub name: String,
    pub source: PathBuf,
    pub store: PathBuf,
    pub frequency: String,
    pub compress: bool,
    pub probe: String,
    pub view: Option<PathBuf>,
}
#[derive(Clone, Debug)]
pub struct Config {
    pub sets: Vec<BackupSet>,
    pub ffprobe: Option<PathBuf>,
    pub notification: Option<crate::notify::Settings>,
}
fn object<'a>(v: &'a Value, field: &str, keys: &[&str]) -> Result<&'a Map<String, Value>> {
    let o = v
        .as_object()
        .with_context(|| format!("{field}: expected object"))?;
    ensure!(
        o.keys().all(|k| keys.contains(&k.as_str())),
        "{field}: unknown or retired setting (check documented schema)"
    );
    Ok(o)
}
fn string(o: &Map<String, Value>, key: &str, default: Option<&str>) -> Result<String> {
    match o.get(key) {
        Some(v) => v
            .as_str()
            .filter(|s| !s.trim().is_empty())
            .map(str::to_owned)
            .with_context(|| format!("{key}: expected nonempty string")),
        None => default
            .map(str::to_owned)
            .with_context(|| format!("{key}: missing required setting")),
    }
}
fn boolean(o: &Map<String, Value>, key: &str, default: bool) -> Result<bool> {
    match o.get(key) {
        Some(v) => v
            .as_bool()
            .with_context(|| format!("{key}: expected boolean")),
        None => Ok(default),
    }
}
pub fn load(path: &Path) -> Result<Config> {
    let bytes = fs::read(path).context("configuration cannot be read")?;
    let v: Value = serde_json::from_slice(&bytes)
        .map_err(|_| anyhow::anyhow!("configuration is not valid JSON"))?;
    let top = object(
        &v,
        "configuration",
        &["ConfigVersion", "BackupSets", "Tools", "Secrets"],
    )?;
    ensure!(
        top.get("ConfigVersion").and_then(Value::as_f64) == Some(3.0),
        "ConfigVersion: native engine requires version 3"
    );
    let notification = if let Some(secrets) = top.get("Secrets") {
        let s = object(
            secrets,
            "Secrets",
            &[
                "ToEmail",
                "FromEmail",
                "SmtpServer",
                "SmtpPort",
                "Credential",
            ],
        )?;
        if let Some(credential) = s.get("Credential") {
            ensure!(
                credential
                    .as_str()
                    .is_some_and(|s| s.starts_with("credential:")),
                "Secrets.Credential: readable secrets are forbidden; use a protected credential reference"
            );
        }
        if s.is_empty() {
            None
        } else {
            let settings = crate::notify::Settings {
                to: string(s, "ToEmail", None)?,
                from: string(s, "FromEmail", None)?,
                server: string(s, "SmtpServer", None)?,
                port: match s.get("SmtpPort") {
                    Some(v) => v
                        .as_u64()
                        .and_then(|n| u16::try_from(n).ok())
                        .filter(|n| *n != 0)
                        .context("SmtpPort: expected integer 1..65535")?,
                    None => 587,
                },
                credential: if s.contains_key("Credential") {
                    Some(string(s, "Credential", None)?)
                } else {
                    None
                },
            };
            crate::notify::validate(&settings)?;
            Some(settings)
        }
    } else {
        None
    };
    let empty = Value::Object(Map::new());
    let tools = object(
        top.get("Tools").unwrap_or(&empty),
        "Tools",
        &["SevenZipPath", "FfprobePath"],
    )?;
    let tool = |key| -> Result<Option<PathBuf>> {
        if tools.contains_key(key) {
            let value = PathBuf::from(string(tools, key, None)?);
            ensure!(
                value.is_absolute() || value.components().count() == 1,
                "tool setting must be an absolute executable path or a bare PATH command name"
            );
            ensure!(
                !value
                    .components()
                    .any(|c| matches!(c, std::path::Component::ParentDir)),
                "tool setting contains a parent component"
            );
            Ok(Some(value))
        } else {
            Ok(None)
        }
    };
    let entries = top
        .get("BackupSets")
        .and_then(Value::as_array)
        .context("BackupSets: expected nonempty array")?;
    ensure!(!entries.is_empty(), "BackupSets: expected nonempty array");
    let mut sets = Vec::new();
    let mut names = BTreeSet::new();
    for entry in entries {
        let s = object(
            entry,
            "BackupSets entry",
            &[
                "Name",
                "SourcePath",
                "StorePath",
                "HashRecalcFreq",
                "CompressEnabled",
                "CompressProbe",
                "BrowseView",
                "ViewPath",
            ],
        )?;
        let name = string(s, "Name", None)?;
        ensure!(names.insert(name.clone()), "Name: duplicate set name");
        let source = resolve(Path::new(&string(s, "SourcePath", None)?))
            .context("SourcePath: cannot resolve root")?;
        let store = resolve(Path::new(&string(s, "StorePath", None)?))
            .context("StorePath: cannot resolve root")?;
        let frequency = string(s, "HashRecalcFreq", Some("W"))?;
        ensure!(
            ["A", "E", "D", "W", "M", "Y", "N"].contains(&frequency.as_str()),
            "HashRecalcFreq: invalid schedule"
        );
        let probe = string(s, "CompressProbe", Some("always"))?;
        ensure!(
            ["off", "excluded-extensions", "always"].contains(&probe.as_str()),
            "CompressProbe: invalid mode"
        );
        let browse = string(s, "BrowseView", Some("off"))?;
        ensure!(
            ["off", "index"].contains(&browse.as_str()),
            "BrowseView: expected off or index"
        );
        let view = if browse == "index" {
            Some(if s.contains_key("ViewPath") {
                resolve(Path::new(&string(s, "ViewPath", None)?))?
            } else {
                resolve(&store.join("View"))?
            })
        } else {
            ensure!(
                !s.contains_key("ViewPath"),
                "ViewPath requires BrowseView=index"
            );
            None
        };
        sets.push(BackupSet {
            name,
            source,
            store,
            frequency,
            compress: boolean(s, "CompressEnabled", true)?,
            probe,
            view,
        });
    }
    for (i, a) in sets.iter().enumerate() {
        for (j, b) in sets.iter().enumerate() {
            ensure!(
                !overlaps(&a.store, &b.source),
                "SourcePath/StorePath overlap within configuration"
            );
            if i != j {
                ensure!(
                    !overlaps(&a.store, &b.store),
                    "StorePath: destinations must be unique and nonoverlapping"
                );
            }
            if let Some(v) = &a.view {
                ensure!(
                    !overlaps(v, &b.source),
                    "ViewPath overlaps a configured source"
                );
                ensure!(
                    (i == j && *v == a.store.join("View")) || !overlaps(v, &b.store),
                    "ViewPath overlaps a protected store"
                );
                if i != j
                    && let Some(w) = &b.view
                {
                    ensure!(!overlaps(v, w), "ViewPath: overlapping views");
                }
            }
        }
    }
    // Accepted for existing configurations; native operations always use the packaged helper.
    let _ = tool("SevenZipPath")?;
    Ok(Config {
        sets,
        ffprobe: tool("FfprobePath")?,
        notification,
    })
}
