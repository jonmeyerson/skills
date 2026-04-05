<#
.SYNOPSIS
    Generates a unified diff patch file for a review tribunal session.

.DESCRIPTION
    Writes the git diff to {OutputPath} and returns the list of changed files
    to stdout (newline-separated). Exits non-zero on failure.

.PARAMETER Mode
    Diff mode: 'branch' or 'uncommitted'.

.PARAMETER OutputPath
    Absolute path where the .patch file should be written.
    The orchestrator is responsible for constructing this path before invoking the script.

.PARAMETER Base
    (branch mode only) Base branch or ref — the left side of the diff.

.PARAMETER Head
    (branch mode only) Head branch or ref — the right side of the diff.

.PARAMETER Branch
    (uncommitted mode only) Branch name — used for documentation only;
    git diff --staged captures only staged (indexed) changes, not unstaged working-tree changes.

.OUTPUTS
    Writes changed file paths to stdout, one per line.
    Writes the patch to OutputPath.
    Writes progress to stderr so stdout is clean for the caller.

.EXAMPLE
    .\ReviewPatch.ps1 -Mode branch -OutputPath C:\sessions\files\review-add-auth.patch `
        -Base develop -Head feature/add-auth

.EXAMPLE
    .\ReviewPatch.ps1 -Mode uncommitted -OutputPath C:\sessions\files\review-add-auth.patch `
        -Branch feature/add-auth
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('branch', 'uncommitted')]
    [string] $Mode,

    [Parameter(Mandatory)]
    [string] $OutputPath,

    [string] $Base,
    [string] $Head,
    [string] $Branch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Err([string]$msg) { Write-Error $msg -ErrorAction Stop }

# --- Validate args per mode ---
if ($Mode -eq 'branch') {
    if (-not $Base)  { Write-Err "'-Base' is required when Mode is 'branch'." }
    if (-not $Head)  { Write-Err "'-Head' is required when Mode is 'branch'." }
    if ($Base -eq $Head) { Write-Err "Base and Head must not be the same ref ('$Base')." }
}
if ($Mode -eq 'uncommitted') {
    if (-not $Branch) { Write-Err "'-Branch' is required when Mode is 'uncommitted'." }
}

# --- Ensure output directory exists ---
$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path $outDir)) {
    Write-Progress -Activity "ReviewPatch" -Status "Creating output directory"
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# --- Get changed file list ---
Write-Progress -Activity "ReviewPatch" -Status "Listing changed files"

$nameArgs = switch ($Mode) {
    'branch'      { @('diff', "$Base..$Head", '--name-only') }
    'uncommitted' { @('diff', '--staged', '--name-only') }
}

$changedFiles = git @nameArgs
if ($LASTEXITCODE -ne 0) {
    Write-Err "git $($nameArgs -join ' ') failed (exit $LASTEXITCODE)"
}

# --- Write patch ---
Write-Progress -Activity "ReviewPatch" -Status "Writing patch to $OutputPath"

$diffArgs = switch ($Mode) {
    'branch'      { @('diff', "$Base..$Head") }
    'uncommitted' { @('diff', '--staged') }
}

$patch = git @diffArgs
if ($LASTEXITCODE -ne 0) {
    Write-Err "git $($diffArgs -join ' ') failed (exit $LASTEXITCODE)"
}

[System.IO.File]::WriteAllText($OutputPath, ($patch -join "`n"), [System.Text.Encoding]::UTF8)

Write-Progress -Activity "ReviewPatch" -Completed -Status "Done"

# --- Emit changed files to stdout for the caller ---
$changedFiles
