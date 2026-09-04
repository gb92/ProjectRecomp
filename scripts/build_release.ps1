[CmdletBinding()]
param(
    [ValidatePattern("^[0-9A-Za-z][0-9A-Za-z._-]*$")]
    [string]$Version = "0.1.0-alpha.1",
    [string]$Ref = "HEAD",
    [string]$BuildDirectory = "project\build",
    [string]$Configuration = "RelWithDebInfo",
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OutputDirectory = [IO.Path]::GetFullPath(
    (Join-Path $RepoRoot $OutputDirectory)
)

& git -C $RepoRoot diff --quiet --ignore-submodules=all
if ($LASTEXITCODE) {
    throw "Commit tracked working-tree changes before building a release."
}
& git -C $RepoRoot diff --cached --quiet --ignore-submodules=all
if ($LASTEXITCODE) {
    throw "Commit staged changes before building a release."
}

$HeadCommit = (& git -C $RepoRoot rev-parse "HEAD^{commit}").Trim()
$ReleaseCommit = (& git -C $RepoRoot rev-parse "$Ref^{commit}").Trim()
if ($LASTEXITCODE -or !$ReleaseCommit) {
    throw "Git ref not found: $Ref"
}
if ($HeadCommit -ne $ReleaseCommit) {
    throw "The release ref must resolve to the checked-out HEAD."
}

& (Join-Path $PSScriptRoot "build_windows_installer.ps1") `
    -BuildDirectory $BuildDirectory `
    -Configuration $Configuration `
    -OutputDirectory $OutputDirectory `
    -Version $Version
if ($LASTEXITCODE) {
    throw "Windows installer build failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot "build_source_archives.ps1") `
    -Version $Version `
    -Ref $Ref `
    -OutputDirectory $OutputDirectory
if ($LASTEXITCODE) {
    throw "Source archive build failed with exit code $LASTEXITCODE."
}

$Installer = Join-Path $OutputDirectory (
    "ProjectRecomp-$Version-Windows-x64-Setup.exe"
)
$SourceZip = Join-Path $OutputDirectory (
    "ProjectRecomp-$Version-Source.zip"
)
$ReleaseChecksums = Join-Path $OutputDirectory (
    "ProjectRecomp-$Version-SHA256SUMS.txt"
)

$Checksums = foreach ($Path in @($Installer, $SourceZip)) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Expected release artifact not found: $Path"
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    "$($Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($Path))"
}
Set-Content -LiteralPath $ReleaseChecksums -Value $Checksums -Encoding ASCII

Write-Output "Release artifacts for commit ${ReleaseCommit}:"
Get-Item -LiteralPath $Installer, $SourceZip, $ReleaseChecksums
