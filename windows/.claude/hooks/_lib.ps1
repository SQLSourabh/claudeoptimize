# Shared resolver for Checkpoint.md and EOD_Summary.md location.
# Dot-source from each hook:
#   . "$PSScriptRoot\_lib.ps1"
#   $r = Resolve-ManagedFile -Filename 'Checkpoint.md'
#   # $r is a hashtable: Path, Status, Note, RelPath
#
# Resolution rules (Option A):
#   0 matches  -> create at $root\<filename>            (Status: create)
#   1 match    -> adopt that path                       (Status: adopt)
#   2+ matches -> if $root\<filename> is among them,    (Status: ambiguous-root)
#                 use it; else pick shortest path with  (Status: ambiguous-fallback)
#                 lex tiebreaker. Note lists every match.

$script:SkipDirNames = @(
    '.git', '.hg', '.svn',
    'node_modules', '.venv', 'venv', 'env',
    'dist', 'build', 'out', '.next', '.nuxt',
    'target', '__pycache__', '.pytest_cache', '.mypy_cache', '.tox',
    '.gradle', '.idea', '.vscode',
    '.claude', '.agents'
)

# Canonicalize a path so casing, 8.3 short names, and trailing slashes
# all reduce to one stable representation. Used for equality + prefix
# checks. Returns $null if the path doesn't exist.
#
# Critical: Resolve-Path does NOT expand 8.3 short names (e.g.
# "SOURAB~1.AGA" stays short), but Get-ChildItem.FullName returns the
# long form. We must explicitly expand via GetItem so prefix checks work.
function Get-CanonicalPath {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return $item.FullName
    } catch {
        return $null
    }
}

# Compute a relative path from $base to $target, both already canonical.
# Pure string operation: Resolve-Path -Relative requires Push-Location
# which mutates state and breaks under concurrent invocation.
function Get-RelativePath {
    param(
        [string]$Base,
        [string]$Target
    )
    $b = $Base.TrimEnd('\','/')
    $t = $Target
    if ($t.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    if ($t.Length -le $b.Length) {
        return $t
    }
    $prefix = $t.Substring(0, $b.Length)
    if (-not $prefix.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $t
    }
    # Use substring extraction (more robust than char indexing across PS
    # versions). The character right after $b must be a separator.
    $sep = $t.Substring($b.Length, 1)
    if ($sep -eq '\' -or $sep -eq '/') {
        return $t.Substring($b.Length + 1)
    }
    return $t
}

function Resolve-ManagedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Filename
    )

    $root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    $rootCanon = Get-CanonicalPath $root
    if (-not $rootCanon) { $rootCanon = $root.TrimEnd('\','/') }
    $rootCanon = $rootCanon.TrimEnd('\','/')

    $rootFilePath = Join-Path $rootCanon $Filename

    # Walk the tree iteratively, pruning skip dirs at every level.
    $matches = New-Object System.Collections.Generic.List[string]
    $stack   = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($rootCanon)

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        try {
            $entries = Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop
        } catch {
            continue
        }
        foreach ($e in $entries) {
            if ($e.PSIsContainer) {
                if ($script:SkipDirNames -notcontains $e.Name) {
                    $stack.Push($e.FullName)
                }
            } else {
                if ($e.Name -ieq $Filename) {
                    # Use FullName as-is. Since we walked from $rootCanon,
                    # FullName will already share that prefix. Re-canonicalizing
                    # via Resolve-Path can break the prefix when junctions or
                    # symlinks are present anywhere in the path.
                    [void]$matches.Add($e.FullName)
                }
            }
        }
    }

    $count = $matches.Count

    if ($count -eq 0) {
        return @{
            Path    = $rootFilePath
            RelPath = $Filename
            Status  = 'create'
            Note    = "No existing $Filename found in project tree; will create at project root."
        }
    }

    # Pre-compute relative paths for all matches.
    $rels = @()
    foreach ($m in $matches) {
        $r = Get-RelativePath -Base $rootCanon -Target $m
        if ([string]::IsNullOrEmpty($r)) { $r = $Filename }
        $rels += $r
    }

    if ($count -eq 1) {
        $picked    = $matches[0]
        $pickedRel = $rels[0]
        $note = if ($picked.Equals($rootFilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            "Adopted existing $Filename at project root."
        } else {
            "Adopted existing $Filename at $pickedRel (single match in tree)."
        }
        return @{
            Path    = $picked
            RelPath = $pickedRel
            Status  = 'adopt'
            Note    = $note
        }
    }

    # 2+ matches.
    $picked    = $null
    $pickedRel = $null
    $status    = $null
    for ($i = 0; $i -lt $matches.Count; $i++) {
        if ($matches[$i].Equals($rootFilePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $picked    = $matches[$i]
            $pickedRel = $rels[$i]
            $status    = 'ambiguous-root'
            break
        }
    }
    if (-not $picked) {
        # Sort by length, lex tiebreaker.
        $sorted = 0..($matches.Count - 1) | Sort-Object @{
            Expression = { $matches[$_].Length }
        }, @{
            Expression = { $matches[$_] }
        }
        $picked    = $matches[$sorted[0]]
        $pickedRel = $rels[$sorted[0]]
        $status    = 'ambiguous-fallback'
    }

    $list = ($rels -join ', ')
    return @{
        Path    = $picked
        RelPath = $pickedRel
        Status  = $status
        Note    = "WARNING: $count $Filename files found in tree ($list). Using $pickedRel. Consolidate to a single file to silence this warning."
    }
}
