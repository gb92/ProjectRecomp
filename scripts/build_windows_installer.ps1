[CmdletBinding()]
param(
    [string]$BuildDirectory = "project\build",
    [string]$Configuration = "RelWithDebInfo",
    [string]$OutputDirectory = "dist",
    [string]$Version = "0.1.0-alpha.1"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (![IO.Path]::IsPathFullyQualified($BuildDirectory)) {
    $BuildDirectory = Join-Path $RepoRoot $BuildDirectory
}
if (![IO.Path]::IsPathFullyQualified($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot $OutputDirectory
}
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$StageDirectory = Join-Path $BuildDirectory "package\windows-root"
$InstallerScript = Join-Path $RepoRoot "packaging\windows\ProjectRecomp.iss"

$Iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if ($Iscc) {
    $IsccPath = $Iscc.Source
} else {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 7\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 7\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 7\ISCC.exe")
    )
    $candidate = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (!$candidate) {
        throw (
            "Inno Setup 7 was not found. Install it with: " +
            "winget install -e --id JRSoftware.InnoSetup.7"
        )
    }
    $IsccPath = $candidate
}

& cmake --build $BuildDirectory --config $Configuration
if ($LASTEXITCODE) {
    throw "Project build failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $StageDirectory) {
    Remove-Item -LiteralPath $StageDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $StageDirectory | Out-Null
& cmake --install $BuildDirectory --config $Configuration `
    --prefix $StageDirectory --component ProjectRecomp
if ($LASTEXITCODE) {
    throw "Install staging failed with exit code $LASTEXITCODE."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
& $IsccPath `
    "/DSourceDir=$StageDirectory" `
    "/DRepoDir=$RepoRoot" `
    "/DOutputDir=$OutputDirectory" `
    "/DAppVersion=$Version" `
    $InstallerScript
if ($LASTEXITCODE) {
    throw "Installer compilation failed with exit code $LASTEXITCODE."
}
