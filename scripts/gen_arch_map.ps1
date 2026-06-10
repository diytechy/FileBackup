<#
.SYNOPSIS
    Regenerate the code map, dependency diagram, and high-level flow from the
    real source AST, so none of them can drift. PowerShell counterpart of the
    kit's Python gen_arch_map.py (which parses Python).

.DESCRIPTION
    Parses Modules/*.psm1 (and the entry scripts, for the diagram) with the
    PowerShell AST and maintains three generated regions:

    GENERATED MODULE MAP (required in every -Doc): per module —
      - the module's one-line summary (its comment-based-help .SYNOPSIS),
      - internal coupling: which OTHER in-tree modules it calls into (cross-module
        function calls) — this makes the load-bearing invariant auditable
        (Common must never depend on Engine) and shows a change's blast radius,
      - each function, whether it is exported (Export-ModuleMember), and any
        'Implements: SR-/LLR-' back-link comment in the function body.

    GENERATED DEPENDENCY DIAGRAM (optional per -Doc; presence opts in): the same
    internal coupling rendered as a Mermaid `graph LR`, plus the entry scripts
    (FileBackup.ps1, Reconstruct.ps1) and which modules they call — so BOTH
    layering invariants are visible at a glance: an arrow from Common into
    Engine, or from Reconstruct.ps1 into Engine, is a defect you can see.
    Mermaid fences render natively on GitHub and in the VS Code Markdown
    preview; no diagram toolchain (see docs/process.md "Diagrams are text").

    GENERATED FLOW (optional per -Doc): the ordered internal calls the -Flow
    orchestrator function makes, each with the callee's .SYNOPSIS — a generated
    rendering of the "thin orchestrators" rule. A short or vague list here means
    the routine inlines logic instead of delegating.

.PARAMETER Doc
    Target file(s) to update (each must contain the MODULE MAP marker pair;
    DIAGRAM/FLOW markers are optional per file). Default: docs/architecture.md
    and AGENTS.md.

.PARAMETER Flow
    Orchestrator function whose call sequence fills the GENERATED FLOW markers.
    Default: Invoke-BackupSet (the per-set backup pipeline). Pass '' to skip.

.PARAMETER Check
    Do not write; exit 1 if any target's generated regions differ from disk
    (so CI / check.ps1 can fail when a doc is stale).

.NOTES
    Implements: (tooling — supports the traceability harness, not an SR/LLR.)
#>
[CmdletBinding()]
param(
    [string[]]$Doc,
    [string]$Flow = 'Invoke-BackupSet',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repo    = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$modules = Get-ChildItem -LiteralPath (Join-Path $repo 'Modules') -Filter '*.psm1' | Sort-Object Name
$entryScripts = @('FileBackup.ps1','Reconstruct.ps1') |
    ForEach-Object { Join-Path $repo $_ } | Where-Object { Test-Path -LiteralPath $_ }

if (-not $Doc) {
    $Doc = @((Join-Path $repo 'docs\architecture.md'), (Join-Path $repo 'AGENTS.md'))
}

function Get-ExportedNames {
    param([System.Management.Automation.Language.Ast]$Ast)
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $calls = $Ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and
        $n.GetCommandName() -eq 'Export-ModuleMember' }, $true)
    foreach ($c in $calls) {
        # Every nested string constant (handles bareword lists and
        # `-Function @( 'A', 'B' )` array literals), minus the keywords.
        $strings = $c.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
        foreach ($s in $strings) {
            if ($s.Value -in 'Export-ModuleMember','Function','Alias','Cmdlet','Variable') { continue }
            [void]$names.Add($s.Value)
        }
    }
    return $names
}

function Get-ModuleCalls {
    # Distinct OTHER in-tree modules an AST calls into.
    param([System.Management.Automation.Language.Ast]$Ast, [hashtable]$FuncToModule, [string]$SelfShort)
    $deps = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cmds = $Ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        $name = $c.GetCommandName()
        if (-not $name) { continue }
        $owner = $FuncToModule[$name.ToLowerInvariant()]
        if ($owner -and $owner -ne $SelfShort) { [void]$deps.Add($owner) }
    }
    return $deps
}

function Get-FirstSynopsisLine {
    param($HelpContent)
    if ($HelpContent -and $HelpContent.Synopsis) {
        return ($HelpContent.Synopsis -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
    }
    return ''
}

# --- Pass 1: parse every module; index function name -> module/synopsis -------
$parsed = @{}
$funcToModule = @{}   # lower-case function name -> module short name
$funcSynopsis = @{}   # lower-case function name -> one-line .SYNOPSIS ('' if none)
foreach ($mod in $modules) {
    $tokens = $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($mod.FullName, [ref]$tokens, [ref]$errs)
    $short = $mod.BaseName -replace '^FileBackup\.', ''   # e.g. "Common", "Engine"
    $fns = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($fn in $fns) {
        $key = $fn.Name.ToLowerInvariant()
        $funcToModule[$key] = $short
        if (-not $funcSynopsis.ContainsKey($key)) {
            $funcSynopsis[$key] = Get-FirstSynopsisLine -HelpContent $fn.GetHelpContent()
        }
    }
    $parsed[$mod.Name] = [pscustomobject]@{
        Ast      = $ast
        Short    = $short
        Synopsis = Get-FirstSynopsisLine -HelpContent $ast.GetHelpContent()
        Exported = Get-ExportedNames -Ast $ast
        Fns      = $fns
    }
}

# --- Pass 2: the MODULE MAP block ----------------------------------------------
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<!-- BEGIN GENERATED MODULE MAP -->')
[void]$sb.AppendLine("_Generated by ``scripts/gen_arch_map.ps1`` from the modules' AST. Do not edit by hand;")
[void]$sb.AppendLine('run the generator. Summary = the module''s .SYNOPSIS; back-links come from `Implements:` comments._')
foreach ($mod in $modules) {
    $info = $parsed[$mod.Name]
    $deps = Get-ModuleCalls -Ast $info.Ast -FuncToModule $funcToModule -SelfShort $info.Short

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("### ``Modules/$($mod.Name)``")
    [void]$sb.AppendLine('')
    if ($info.Synopsis) { [void]$sb.AppendLine("_$($info.Synopsis)_") }
    if ($deps.Count) {
        $depList = ($deps | ForEach-Object { '`' + $_ + '`' }) -join ', '
        [void]$sb.AppendLine("Imports (internal): $depList")
    } else {
        [void]$sb.AppendLine('Imports (internal): _none_')
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Function | Exported | Implements |')
    [void]$sb.AppendLine('|---|:---:|---|')
    foreach ($fn in $info.Fns | Sort-Object Name) {
        $impl = ''
        # Only the dedicated back-link comment line counts — prose inside a help
        # block may mention "Implements: ..." too (e.g. a .PARAMETER note).
        $m = [regex]::Match($fn.Extent.Text, '(?m)^\s*#\s*Implements:\s*([^\r\n#]+)')
        if ($m.Success) { $impl = $m.Groups[1].Value.Trim().TrimEnd('.') }
        $exp = if (($info.Exported.Count -eq 0) -or $info.Exported.Contains($fn.Name)) { 'yes' } else { 'no' }
        $imp = if ($impl) { $impl } else { '—' }
        [void]$sb.AppendLine("| ``$($fn.Name)`` | $exp | $imp |")
    }
}
[void]$sb.Append('<!-- END GENERATED MODULE MAP -->')
$mapBlock = $sb.ToString() -replace "`r`n", "`n"

# --- Pass 3: the DEPENDENCY DIAGRAM block (Mermaid) -----------------------------
function Get-MermaidNodeId { param([string]$Name) return 'n_' + ($Name -replace '\W', '_') }
function Get-MermaidLabel {
    param([string]$Name, [string]$Synopsis)
    $label = $Name
    if ($Synopsis) {
        $short = if ($Synopsis.Length -le 48) { $Synopsis } else { $Synopsis.Substring(0, 47) + '…' }
        $label = "$Name — $short"
    }
    return $label.Replace('"', "'")
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('<!-- BEGIN GENERATED DEPENDENCY DIAGRAM -->')
[void]$sb.AppendLine('_Generated by `scripts/gen_arch_map.ps1`: each arrow is a call into another')
[void]$sb.AppendLine('in-tree module. An arrow from `Common` into `Engine`, or from `Reconstruct.ps1`')
[void]$sb.AppendLine('into `Engine`, would violate the AGENTS.md §3 invariants. Do not edit by hand._')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('```mermaid')
[void]$sb.AppendLine('graph LR')
$edges = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($mod in $modules) {
    $info = $parsed[$mod.Name]
    $id = Get-MermaidNodeId $info.Short
    $label = Get-MermaidLabel $info.Short $info.Synopsis
    [void]$sb.AppendLine("    $id[`"$label`"]")
    foreach ($dep in (Get-ModuleCalls -Ast $info.Ast -FuncToModule $funcToModule -SelfShort $info.Short)) {
        [void]$edges.Add("    $id --> $(Get-MermaidNodeId $dep)")
    }
}
foreach ($script in $entryScripts) {
    $tokens = $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errs)
    $name = [System.IO.Path]::GetFileName($script)
    # Functions defined inside the script itself are not module calls.
    $localFns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($fn in $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { [void]$localFns.Add($fn.Name) }
    $deps = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $cn = $c.GetCommandName()
        if (-not $cn -or $localFns.Contains($cn)) { continue }
        $owner = $funcToModule[$cn.ToLowerInvariant()]
        if ($owner) { [void]$deps.Add($owner) }
    }
    $synopsis = Get-FirstSynopsisLine -HelpContent $ast.GetHelpContent()
    $id = Get-MermaidNodeId $name
    $label = Get-MermaidLabel $name $synopsis
    [void]$sb.AppendLine("    $id([`"$label`"])")
    foreach ($dep in $deps) {
        [void]$edges.Add("    $id --> $(Get-MermaidNodeId $dep)")
    }
}
foreach ($e in $edges) { [void]$sb.AppendLine($e) }
[void]$sb.AppendLine('```')
[void]$sb.Append('<!-- END GENERATED DEPENDENCY DIAGRAM -->')
$diagramBlock = $sb.ToString() -replace "`r`n", "`n"

# --- Pass 4: the FLOW block (ordered internal calls of the orchestrator) -------
$flowBlock = $null
if ($Flow) {
    $entryFn = $null
    foreach ($mod in $modules) {
        $hit = $parsed[$mod.Name].Fns | Where-Object { $_.Name -eq $Flow }
        if ($hit) { $entryFn = $hit | Select-Object -First 1; break }
    }
    if (-not $entryFn) { throw "Flow entry function not found in Modules/: $Flow" }

    $calls = $entryFn.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
        Sort-Object { $_.Extent.StartOffset }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!-- BEGIN GENERATED FLOW -->')
    [void]$sb.AppendLine("_Generated by ``scripts/gen_arch_map.ps1 -Flow $Flow`` — the ordered internal calls")
    [void]$sb.AppendLine("in ``$Flow``. Keep orchestrators thin: a readable flow here means the routine")
    [void]$sb.AppendLine('delegates instead of computing. Loops/branches are not shown — see the')
    [void]$sb.AppendLine('hand-written pipeline overview for control flow. Do not edit by hand._')
    [void]$sb.AppendLine('')
    $entrySynopsis = $funcSynopsis[$Flow.ToLowerInvariant()]
    if ($entrySynopsis) {
        [void]$sb.AppendLine("**``$Flow``** — $entrySynopsis")
        [void]$sb.AppendLine('')
    }
    $i = 0
    foreach ($c in $calls) {
        $cn = $c.GetCommandName()
        if (-not $cn) { continue }
        $key = $cn.ToLowerInvariant()
        if (-not $funcToModule.ContainsKey($key) -or $cn -eq $Flow) { continue }
        $i++
        $s = $funcSynopsis[$key]
        $line = if ($s) { "$i. ``$cn`` — $s" } else { "$i. ``$cn``" }
        [void]$sb.AppendLine($line)
    }
    if ($i -eq 0) {
        [void]$sb.AppendLine("_(no internal calls found — is ``$Flow`` the orchestrator?)_")
    }
    [void]$sb.Append('<!-- END GENERATED FLOW -->')
    $flowBlock = $sb.ToString() -replace "`r`n", "`n"
}

# --- Splice the regions into every target doc -----------------------------------
function Set-DocRegion {
    # Replace the marker-delimited region; required markers must exist, optional
    # ones opt in by presence. A duplicated marker would make the splice ambiguous
    # (and silently eat the text between the copies) — refuse rather than corrupt.
    param([string]$Text, [string]$Marker, [string]$Content, [string]$Target, [switch]$Required)
    $begin = "<!-- BEGIN $Marker -->"
    $end   = "<!-- END $Marker -->"
    $pattern = "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))"
    $count = [regex]::Matches($Text, $pattern).Count
    if ($count -eq 0) {
        if ($Required) { throw "$Marker markers not found in $Target" }
        return $Text
    }
    if ($count -gt 1 -or ([regex]::Matches($Text, [regex]::Escape($begin)).Count -gt 1)) {
        throw "$Target contains a duplicated $Marker marker; keep exactly one pair per file"
    }
    return [regex]::Replace($Text, $pattern, { param($m) $Content }.GetNewClosure())
}

$stale = $false
foreach ($target in $Doc) {
    if (-not (Test-Path -LiteralPath $target)) { throw "Target doc not found: $target" }
    $doc = (Get-Content -LiteralPath $target -Raw) -replace "`r`n", "`n"
    $updated = Set-DocRegion -Text $doc -Marker 'GENERATED MODULE MAP' -Content $mapBlock -Target $target -Required
    $updated = Set-DocRegion -Text $updated -Marker 'GENERATED DEPENDENCY DIAGRAM' -Content $diagramBlock -Target $target
    if ($flowBlock) {
        $updated = Set-DocRegion -Text $updated -Marker 'GENERATED FLOW' -Content $flowBlock -Target $target
    }

    if ($Check) {
        if ($updated -ne $doc) {
            Write-Error "Generated regions are stale in $target. Run: pwsh -File scripts/gen_arch_map.ps1"
            $stale = $true
        } else {
            Write-Host "[OK]  Generated regions current in $target"
        }
    } elseif ($updated -ne $doc) {
        Set-Content -LiteralPath $target -Value $updated -NoNewline -Encoding utf8
        Write-Host "Updated generated regions in $target"
    } else {
        Write-Host "[OK]  Generated regions already current in $target"
    }
}

if ($Check -and $stale) { exit 1 }
exit 0
