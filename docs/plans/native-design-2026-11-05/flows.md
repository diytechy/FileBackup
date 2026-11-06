# Critical flows retained by the native port

Draft design sequences, not generated code diagrams. See the
[review guide](review.md), [contracts](contracts.md) and current implemented
[user backup flow](../../backup-flow.md). Each sequence preserves existing
responsibilities and marks the additional metadata behavior.

## Backup and interruption

LLR-155..167; SR-005, SR-017, SR-059, SR-082, SR-100, SR-150.

```mermaid
sequenceDiagram
    actor Operator
    participant Run
    participant Source
    participant Latest as CurrentBackup
    participant History as BackupHistory
    Operator->>Run: Back up configured sources
    Run->>Run: Validate config, roots and prerequisites; acquire ownership
    Run->>Latest: Read prior state and index available content
    Run->>History: Stage prior records and kit; rename Building to dated state
    Run->>Latest: Publish and sync INCOMPLETE_RUN before latest record changes
    loop Entries, with bounded retries
        Run->>Source: Read metadata; copy/hash changed file or classify folder/link
        Run->>Latest: Reuse or publish complete content
        Run->>Latest: Checkpoint valid file rows
    end
    Run->>Latest: Final manifest then directory/link record then completion markers
    alt Required metadata failed
        Run-->>Operator: Incomplete/host-stop with named metadata gap
    else Finalization succeeded
        Run->>Latest: Clear INCOMPLETE_RUN after required metadata is synced
        Run->>History: Remove unneeded new snapshot; move superseded objects last
        Run-->>Operator: Complete or incomplete file result plus metadata warnings
    end
    Note over Run,History: On interruption, prior state and published file dependencies remain available
    Run->>Run: Release ownership on every exit
```

The directory/link record extends the existing sidecar phase. Interruption tests
must cover cross-file consistency; ordering alone is not a claim that the pair
is atomic. A failed row or source disappearance never supplies a removal list.

## Managed removal

LLR-169..170; SR-045, SR-046, SR-101, SR-102.

```mermaid
sequenceDiagram
    actor Operator
    participant Prune
    participant Pool
    Operator->>Prune: Select saved state for removal
    Prune->>Prune: Validate request; acquire ownership
    Prune->>Pool: Read protected latest/later-state dependencies one manifest at a time
    alt Incomplete scan or unusable survivor supply
        Prune-->>Operator: Refuse destructive removal with cause
    else Complete plan
        Prune->>Pool: Rehome and verify required last copies
        Prune->>Pool: Publish survivor metadata, then commit Pruning phase
        Prune->>Pool: Resume/finish selected folder deletion
        Prune-->>Operator: Result and removal-window implications
    end
    Note over Prune,Pool: A restart resumes the same protocol; no new global garbage collector
```

## Independent restore and relative links

LLR-172..177; SR-056, SR-118, SR-121, SR-137, SR-150..152.

```mermaid
sequenceDiagram
    actor Operator
    participant Kit as Carried PowerShell or bash kit
    participant Pool
    participant Target
    Operator->>Kit: Select state and target
    Kit->>Pool: Read declared supported records and INCOMPLETE_RUN state
    Kit->>Target: Validate ancestry, collisions, tools and expanded capacity
    loop Ordinary directories and file rows
        Kit->>Pool: Resolve content; try verified alternate candidates if needed
        Kit->>Target: Write private temp; verify length/hash; publish file
    end
    Kit->>Target: Apply supported directory/file metadata
    loop Valid supported in-root folder links in finalized metadata
        Kit->>Target: Compute target relative to link parent; validate; create link last
    end
    Kit-->>Operator: File result and distinct metadata limitations/incompleteness
    Note over Kit,Target: No writes through restored links; no native engine or network required
```

## Kit refresh

LLR-186; SR-007, SR-084, SR-110, SR-117.

```mermaid
sequenceDiagram
    actor Operator
    participant Refresh
    participant State
    Operator->>Refresh: Explicit refresh request
    Refresh->>Refresh: Acquire ownership; admit supported format/kit pair
    Refresh->>State: Stage complete version-matched kit and verify inventory
    Refresh->>State: Retain prior usable route; commit replacement
    alt Interruption
        State-->>Operator: Prior or new usable route; detectable resumable partial update
    else Complete
        Refresh-->>Operator: Refreshed kit; records and content unchanged
    end
```

This last sequence is a contract to realize and test, not a claim that current
per-file refresh already gives multi-file atomicity. N1/N4 select the smallest
kit-local mechanism that meets it.
