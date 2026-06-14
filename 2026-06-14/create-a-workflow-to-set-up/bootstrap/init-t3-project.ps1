[CmdletBinding()]
param(
    [string]$TargetDir = ".",
    [string]$RepoName,
    [Alias("Force")]
    [switch]$ForceDocs,
    [switch]$NoRemote
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:TouchedFiles = New-Object System.Collections.Generic.List[string]

function Add-TouchedFile {
    param([Parameter(Mandatory = $true)][string]$GitPath)

    if (-not $script:TouchedFiles.Contains($GitPath)) {
        $script:TouchedFiles.Add($GitPath)
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "$FilePath $($Arguments -join ' ') failed with exit code $exitCode"
    }

    return $exitCode
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    return Invoke-External -FilePath "git" -Arguments (@("-C", $script:Root) + $Arguments) -AllowFailure:$AllowFailure
}

function ConvertTo-GitHubRepoName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $repo = $Name.Trim().ToLowerInvariant() -replace "[^a-z0-9._-]+", "-"
    $repo = $repo.Trim([char[]]@(".", "-", "_"))
    if ([string]::IsNullOrWhiteSpace($repo)) {
        throw "Could not derive a valid GitHub repository name from '$Name'. Pass -RepoName explicitly."
    }

    return $repo
}

function Write-TextFileSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [string]$GitPath,
        [switch]$Overwrite
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $Path) -and (-not $Overwrite)) {
        Write-Host "skip  $Path"
        return
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, ($Content.TrimEnd() + "`r`n"), $encoding)
    if (-not [string]::IsNullOrWhiteSpace($GitPath)) {
        Add-TouchedFile -GitPath $GitPath
    }
    Write-Host "write $Path"
}

function Ensure-EmptyFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$GitPath
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Path) {
        Write-Host "skip  $Path"
        return
    }

    [System.IO.File]::WriteAllBytes($Path, [byte[]]@())
    if (-not [string]::IsNullOrWhiteSpace($GitPath)) {
        Add-TouchedFile -GitPath $GitPath
    }
    Write-Host "write $Path"
}

function Add-GitIgnoreEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Entries,
        [string]$GitPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TextFileSafe -Path $Path -Content "" -Overwrite
    }

    $current = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $missing = @($Entries | Where-Object { $current -notcontains $_ })
    if ($missing.Count -eq 0) {
        Write-Host "skip  $Path"
        return
    }

    $linesToAdd = New-Object System.Collections.Generic.List[string]
    $nonEmptyLines = @($current | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hasContent = $nonEmptyLines.Count -gt 0
    if ($hasContent) {
        $linesToAdd.Add("")
    }

    if ($current -notcontains "# OpenClaw local artifacts") {
        $linesToAdd.Add("# OpenClaw local artifacts")
    }

    foreach ($entry in $missing) {
        $linesToAdd.Add($entry)
    }

    Add-Content -LiteralPath $Path -Value $linesToAdd.ToArray()
    if (-not [string]::IsNullOrWhiteSpace($GitPath)) {
        Add-TouchedFile -GitPath $GitPath
    }
    Write-Host "update $Path"
}

function Test-GitRemote {
    param([Parameter(Mandatory = $true)][string]$Name)

    Invoke-Git -Arguments @("remote", "get-url", $Name) -AllowFailure | Out-Null
    return $LASTEXITCODE -eq 0
}

function Ensure-GitRepository {
    if (-not (Test-Path -LiteralPath (Join-Path $script:Root ".git"))) {
        Invoke-External -FilePath "git" -Arguments @("init", "-b", "main", $script:Root) | Out-Null
        Write-Host "git   initialized main in $script:Root"
    }

    $branch = (& git -C $script:Root branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine current git branch in $script:Root"
    }

    if ($branch -ne "main") {
        Invoke-Git -Arguments @("rev-parse", "--verify", "HEAD") -AllowFailure | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Invoke-Git -Arguments @("branch", "-M", "main") | Out-Null
            Write-Host "git   renamed empty branch to main"
            return
        }

        throw "Existing repository is on branch '$branch'. Switch or rename it to 'main' before running this workflow."
    }
}

function Stage-BootstrapFiles {
    $files = @($script:TouchedFiles)
    if ($files.Count -eq 0) {
        Write-Host "git   no workflow-touched files to stage"
        return
    }

    Invoke-Git -Arguments (@("add", "--") + $files) | Out-Null
}

function Commit-BootstrapFiles {
    Invoke-Git -Arguments @("diff", "--cached", "--quiet") -AllowFailure | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "git   no bootstrap changes to commit"
        return
    }

    Invoke-Git -Arguments @("commit", "-m", "Initialize project scaffold") | Out-Null
    Write-Host "git   committed bootstrap scaffold"
}

function Ensure-GitHubRemote {
    if ($NoRemote) {
        Write-Host "gh    skipped remote creation because -NoRemote was set"
        return
    }

    if (Test-GitRemote -Name "origin") {
        Write-Host "gh    using existing origin"
        return
    }

    Invoke-External -FilePath "gh" -Arguments @("auth", "status") | Out-Null
    Invoke-External -FilePath "gh" -Arguments @(
        "repo",
        "create",
        $script:EffectiveRepoName,
        "--private",
        "--source",
        $script:Root,
        "--remote",
        "origin"
    ) | Out-Null
    Write-Host "gh    created private repository $script:EffectiveRepoName"
}

function Push-Main {
    if ($NoRemote) {
        Write-Host "git   skipped push because -NoRemote was set"
        return
    }

    Invoke-Git -Arguments @("push", "-u", "origin", "main") | Out-Null
    Write-Host "git   pushed main"
}

if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$script:Root = (Resolve-Path -LiteralPath $TargetDir).Path
$projectName = Split-Path -Leaf $script:Root
if ([string]::IsNullOrWhiteSpace($RepoName)) {
    $script:EffectiveRepoName = ConvertTo-GitHubRepoName -Name $projectName
} else {
    $script:EffectiveRepoName = $RepoName.Trim()
}

$date = Get-Date -Format "yyyy-MM-dd"

$agents = @'
# AGENTS.md

Default orchestration profile for this repository.

## Mission
- Define what this project is trying to achieve.
- Keep implementation decisions consistent with product outcomes.

## Execution Rules
- Make scoped, reviewable changes.
- Prefer deterministic scripts for repeatable tasks.
- Keep security-sensitive data out of tracked files.

## Coordination
- Use `TOOLS.md` for canonical commands and tooling notes.
- Use `MEMORY.md` and `memory/` to preserve project context.
'@

$soul = @'
# SOUL.md

## Working Identity
- Primary priorities:
- Non-negotiable standards:
- Communication style:

## Decision Heuristics
- Favor clarity over novelty.
- Favor reversible changes over irreversible migrations.
- Favor measured outcomes over assumptions.
'@

$tools = @'
# TOOLS.md

## Core Commands
- Install: `...`
- Dev: `...`
- Build: `...`
- Test: `...`
- Lint/Format: `...`

## Operational Notes
- Package manager:
- CI entrypoint:
- Deployment command:
'@

$user = @'
# USER.md

## Preferences
- Default verbosity:
- Preferred stack choices:
- Risk tolerance:

## Collaboration Defaults
- Ask before destructive operations.
- Prioritize clear diffs over large rewrites.
'@

$memory = @'
# MEMORY.md

Durable project memory.

## Product Context
- Problem:
- Audience:
- Success metrics:

## Architecture Context
- Key modules:
- Data model notes:
- Integration boundaries:

## Decisions
- YYYY-MM-DD:
'@

$readmeTemplate = @'
# {0}

## Overview
Describe what this project does and who it is for.

## Getting Started
- Install: `...`
- Run: `...`
- Test: `...`

## Project Context
- `AGENTS.md` defines agent execution rules.
- `TOOLS.md` records canonical commands.
- `MEMORY.md` and `memory/` preserve durable project context.
'@
$readme = $readmeTemplate -f $projectName

$todayTemplate = @'
# today.md

## Date
- {0}

## Goals
-

## Progress Notes
-

## Blockers
-
'@
$today = $todayTemplate -f $date

$ignoreEntries = @(
    ".openclaw/",
    "memory/session-*.md",
    "memory/tmp/",
    "*.openclaw.log"
)

Write-TextFileSafe -Path (Join-Path $script:Root "AGENTS.md") -Content $agents -GitPath "AGENTS.md" -Overwrite:$ForceDocs
Write-TextFileSafe -Path (Join-Path $script:Root "SOUL.md") -Content $soul -GitPath "SOUL.md" -Overwrite:$ForceDocs
Write-TextFileSafe -Path (Join-Path $script:Root "TOOLS.md") -Content $tools -GitPath "TOOLS.md" -Overwrite:$ForceDocs
Write-TextFileSafe -Path (Join-Path $script:Root "USER.md") -Content $user -GitPath "USER.md" -Overwrite:$ForceDocs
Write-TextFileSafe -Path (Join-Path $script:Root "MEMORY.md") -Content $memory -GitPath "MEMORY.md" -Overwrite:$ForceDocs
Write-TextFileSafe -Path (Join-Path $script:Root "README.md") -Content $readme -GitPath "README.md" -Overwrite:$ForceDocs
Write-TextFileSafe -Path (Join-Path $script:Root "memory/today.md") -Content $today -GitPath "memory/today.md" -Overwrite:$ForceDocs
Ensure-EmptyFile -Path (Join-Path $script:Root "agents/.gitkeep") -GitPath "agents/.gitkeep"
Add-GitIgnoreEntries -Path (Join-Path $script:Root ".gitignore") -Entries $ignoreEntries -GitPath ".gitignore"

Ensure-GitRepository
Stage-BootstrapFiles
Commit-BootstrapFiles
Ensure-GitHubRemote
Push-Main

Write-Host "done  Initialized project scaffold at $script:Root"
