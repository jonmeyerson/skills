<#
.SYNOPSIS
    Generates an index file mapping each changed file to its line number in a patch.

.DESCRIPTION
    Reads the patch at PatchPath and writes an index to OutputPath.
    Each line of the index has the format:
        diff --git a/<path> b/<path>  <line_number>

    Subagents use this index to seek directly to a file's hunk in the patch
    rather than scanning the full diff from the top.

.PARAMETER PatchPath
    Absolute path to the .patch file produced by ReviewPatch.ps1.

.PARAMETER OutputPath
    Absolute path where the .index file should be written.
    The orchestrator is responsible for constructing this path before invoking the script.

.OUTPUTS
    Writes the index to OutputPath.
    Writes progress and line count to stderr so stdout is clean for the caller.

.EXAMPLE
    .\ReviewIndex.ps1 `
        -PatchPath  C:\sessions\files\review-add-auth.patch `
        -OutputPath C:\sessions\files\review-add-auth.index
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PatchPath,

    [Parameter(Mandatory)]
    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Err([string]$msg) { Write-Error $msg -ErrorAction Stop }

# --- Validate input ---
if (-not (Test-Path $PatchPath)) {
    Write-Err "Patch file not found: '$PatchPath'"
}

# --- Ensure output directory exists ---
$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Write-Progress -Activity "ReviewIndex" -Status "Reading patch"

$lines   = [System.IO.File]::ReadAllLines($PatchPath)
$entries = [System.Collections.Generic.List[string]]::new()
$header  = 'diff --git '

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($header)) {
        # Format: "diff --git a/<path> b/<path>  <1-based line number>"
        # Two spaces before the line number match the bash awk -F: output format
        # that subagents already expect.
        $entries.Add("$($lines[$i])  $($i + 1)")
    }
}

Write-Progress -Activity "ReviewIndex" -Status "Writing index ($($entries.Count) entries)"

[System.IO.File]::WriteAllLines($OutputPath, $entries, [System.Text.Encoding]::UTF8)

Write-Progress -Activity "ReviewIndex" -Completed -Status "Done"

Write-Error "Index written: $OutputPath ($($entries.Count) file(s) indexed)" -ErrorAction Continue
