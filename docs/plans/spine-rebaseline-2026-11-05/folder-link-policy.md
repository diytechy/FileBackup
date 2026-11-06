# Folder-link preference and feasibility

Date: 2026-11-05. Scoped owner preference, not approval of the SR tier.

The owner said:

> Ideally a folder link would expand as a link, but it would only work if the link itself could be converted to a relative path underneath the root of what is being backed up. If that can be supported relatively easily, that would be preferred.

## Draft interpretation

Preserve a supported folder link when its resolved destination lies within the
configured source root and maps to a directory in the recovered tree. Record
that relationship without following the alias again. Recovery creates a
relative link from the link's parent to the corresponding restored directory.
An originally absolute link can qualify; an originally relative link can fail
if it resolves outside the root.

For example, a source link `Data/Albums/Favourites` pointing at
`Data/Photos` becomes `Albums/Favourites -> ../Photos` within the restored
root. Moving that whole root preserves the relationship. `..` in a link target
is allowed when the destination stays inside the root; blindly banning every
parent component would exclude this ordinary sibling-folder case.

Ordinary directories and files are restored first, then supported links.
Recovery never writes content through the links. An unsupported host or missing
link-creation privilege is reported; there is no silent replacement with copied
content or an absolute link to the original machine. The restored link need not
use the original host-specific junction representation if a supported relative
folder link preserves its behavior.

This narrows SR-150/151/152 while leaving them Drafted. Approved SN-036 already
asks for in-tree link fidelity; no SN, boundary, assumption or approval baseline
was changed. SR-137's proposal to expand genuinely external links remains an
open policy, not an owner-approved fallback. External targets cannot simply be
made portable by spelling them with enough `..` components. The Gemini concern
about external expansion and the scale counting basis therefore remains open.

## Feasibility assessment

**Feasible as a contained feature, but not already implemented or a one-line
script adjustment.** Source inspection found directory records containing
`RelativePath` and `Attributes`, without persisted link destinations, in
[Get-SourceDirectoryRecord](../../../Modules/FileBackup.Engine.psm1).
The recovery scripts recreate directory records and apply attributes, but do
not currently reconstruct recorded folder-link relationships. Existing link
resolution in [Reconstruct.ps1](../../../Reconstruct.ps1) is for containment,
not evidence of link-preserving recovery. The earlier audit likewise records
link behavior as unfinished work.

The necessary primitives exist: Microsoft documents relative Windows directory
symlink creation from PowerShell 7.1 in
[New-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item?view=powershell-7.5),
and GNU documents relative target resolution from a link's containing directory
in [ln](https://www.gnu.org/software/coreutils/manual/html_node/ln-invocation.html).
These establish feasibility, not validation of every host/filesystem or the
macOS tool route. Windows permission requirements and supported link kinds need
explicit platform checks.

The work package needs capture classification/containment, a versioned portable
link record, implementations in both independent recovery scripts, and fixtures
covering root relocation, absolute-to-relative conversion, junction input,
sibling/ancestor targets, escaping or missing targets, and unavailable host
capabilities. Format support and kit handling must follow the designated
compatibility policy. Do not guess destinations for old snapshots that never
recorded them. This review did not implement or runtime-test that feature.
