# Shared resolver for Checkpoint.md and EOD_Summary.md location.
# Dot-source from each hook:
#   . "$PSScriptRoot\_lib.ps1"
#   $r = Resolve-ManagedFile -Filename 'Checkpoint.md'
#   # $r is a hashtable: Path, RelPath, Status, Note
#
# Resolution rules (with project.json cache layer, parity with _lib.sh):
#   0. Cache hit (.claude/state/project.json valid + path exists)
#                                                    -> Status: cached
#   1. 0 matches  -> create at $root\<filename>      -> Status: create
#   2. 1 match    -> adopt that path                 -> Status: adopt
#   3. 2+ matches -> if $root\<filename> is among,   -> Status: ambiguous-root
#                    else shortest path lex-tied     -> Status: ambiguous-fallback
#                    Both 2+ cases: Note lists every match.
#                    If cache holds acknowledged=true for the
#                    chosen path, the warning is suppressed.

# Schema version for .claude/state/project.json. Bump on incompatible
# schema changes; older caches treated as miss and rewritten.
$script:ProjectJsonVersion = 1

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
function Get-CanonicalPath {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return $item.FullName
    } catch {
        return $null
    }
}

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
    $sep = $t.Substring($b.Length, 1)
    if ($sep -eq '\' -or $sep -eq '/') {
        return $t.Substring($b.Length + 1)
    }
    return $t
}

# Map a filename to its key in project.json.
function Get-CacheKey {
    param([string]$Filename)
    switch ($Filename) {
        'Checkpoint.md'  { return 'checkpoint' }
        'EOD_Summary.md' { return 'eod_summary' }
        default          { return $Filename }
    }
}

# Read a cache entry. Returns hashtable with Path / Acknowledged, or
# $null if cache is missing / version-mismatched / path doesn't exist.
function Get-ProjectJsonEntry {
    param(
        [string]$CacheFile,
        [string]$Key
    )
    if (-not (Test-Path -LiteralPath $CacheFile -PathType Leaf)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $CacheFile -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
    if (([int]($obj.version)) -ne $script:ProjectJsonVersion) { return $null }
    $entry = $obj.$Key
    if (-not $entry) { return $null }
    $p = [string]$entry.path
    if (-not $p) { return $null }
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return @{
        Path         = $p
        Acknowledged = [bool]$entry.acknowledged
    }
}

# Write/update a cache entry. Preserves acknowledged sticky only when
# the path is unchanged.
function Set-ProjectJsonEntry {
    param(
        [string]$CacheFile,
        [string]$Key,
        [string]$Path,
        [string]$Decision,
        [string[]]$Alternatives
    )
    $cacheDir = Split-Path -Parent $CacheFile
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        $null = New-Item -ItemType Directory -Force -Path $cacheDir
    }
    $obj = $null
    if (Test-Path -LiteralPath $CacheFile -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $CacheFile -Raw -ErrorAction Stop
            $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch { $obj = $null }
    }
    if (-not $obj) {
        $obj = [pscustomobject]@{ version = $script:ProjectJsonVersion }
    } else {
        $obj | Add-Member -NotePropertyName version -NotePropertyValue $script:ProjectJsonVersion -Force
    }

    $existing = $obj.$Key
    $acknowledged = $false
    if ($existing -and ([string]$existing.path -ieq $Path)) {
        $acknowledged = [bool]$existing.acknowledged
    }
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $entry = [pscustomobject]@{
        path                   = $Path
        resolved_at            = $now
        decision               = $Decision
        ambiguous_alternatives = @($Alternatives | Where-Object { $_ })
        acknowledged           = $acknowledged
    }
    $obj | Add-Member -NotePropertyName $Key -NotePropertyValue $entry -Force

    $json = $obj | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $CacheFile -Value $json -Encoding UTF8
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

    $cacheKey  = Get-CacheKey $Filename
    $cacheFile = Join-Path $rootCanon '.claude\state\project.json'

    # --- Cache layer ---
    $cached = Get-ProjectJsonEntry -CacheFile $cacheFile -Key $cacheKey
    if ($cached) {
        $rel = Get-RelativePath -Base $rootCanon -Target $cached.Path
        $display = if ([string]::IsNullOrEmpty($rel)) { 'project root' } else { $rel }
        return @{
            Path    = $cached.Path
            RelPath = if ([string]::IsNullOrEmpty($rel)) { $Filename } else { $rel }
            Status  = 'cached'
            Note    = "Using cached path for $Filename ($display) from .claude\state\project.json. Delete the cache or move the file to force a re-scan."
        }
    }

    # --- Scan layer (tree walk with pruning) ---
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
                    [void]$matches.Add($e.FullName)
                }
            }
        }
    }

    $count = $matches.Count

    if ($count -eq 0) {
        Set-ProjectJsonEntry -CacheFile $cacheFile -Key $cacheKey `
                              -Path $rootFilePath -Decision 'create' -Alternatives @()
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
        Set-ProjectJsonEntry -CacheFile $cacheFile -Key $cacheKey `
                              -Path $picked -Decision 'adopt' -Alternatives @()
        return @{
            Path    = $picked
            RelPath = $pickedRel
            Status  = 'adopt'
            Note    = $note
        }
    }

    # 2+ matches — deterministic pick.
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
        $sorted = 0..($matches.Count - 1) | Sort-Object @{
            Expression = { $matches[$_].Length }
        }, @{
            Expression = { $matches[$_] }
        }
        $picked    = $matches[$sorted[0]]
        $pickedRel = $rels[$sorted[0]]
        $status    = 'ambiguous-fallback'
    }

    # Build alternatives list.
    $alternatives = @()
    foreach ($m in $matches) {
        if ($m -ne $picked) { $alternatives += $m }
    }

    Set-ProjectJsonEntry -CacheFile $cacheFile -Key $cacheKey `
                          -Path $picked -Decision $status -Alternatives $alternatives

    # If user previously acknowledged this resolution, suppress warning.
    $cachedNow = Get-ProjectJsonEntry -CacheFile $cacheFile -Key $cacheKey
    if ($cachedNow -and $cachedNow.Acknowledged) {
        $rel = Get-RelativePath -Base $rootCanon -Target $picked
        $display = if ([string]::IsNullOrEmpty($rel)) { 'project root' } else { $rel }
        return @{
            Path    = $picked
            RelPath = $pickedRel
            Status  = $status
            Note    = "Using $Filename at $display (ambiguity acknowledged in .claude\state\project.json)."
        }
    }

    $list = ($rels -join ', ')
    return @{
        Path    = $picked
        RelPath = $pickedRel
        Status  = $status
        Note    = "WARNING: $count $Filename files found in tree ($list). Using $pickedRel. Set acknowledged=true in .claude\state\project.json to silence this warning, or consolidate to a single file."
    }
}
