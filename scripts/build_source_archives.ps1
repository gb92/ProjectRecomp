[CmdletBinding()]
param(
    [ValidatePattern("^[0-9A-Za-z][0-9A-Za-z._-]*$")]
    [string]$Version = "0.1.0-alpha.1",
    [string]$Ref = "HEAD",
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (![IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot $OutputDirectory
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$ArchiveName = "ProjectRecomp-$Version-Source"
$TemporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) "prsrc-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$CheckoutDirectory = Join-Path $TemporaryRoot "r"
$StageDirectory = Join-Path $TemporaryRoot $ArchiveName
$ZipPath = Join-Path $OutputDirectory "$ArchiveName.zip"
$TarPath = Join-Path $OutputDirectory "$ArchiveName.tar.gz"
$ChecksumPath = Join-Path $OutputDirectory "$ArchiveName-SHA256SUMS.txt"

function Get-TarCommand {
    $TarCommand = (Get-Command tar -ErrorAction Stop).Source
    if ($env:OS -eq "Windows_NT") {
        $GitCommand = (Get-Command git -ErrorAction Stop).Source
        $GitRoot = Split-Path -Parent (Split-Path -Parent $GitCommand)
        $GitTarCommand = Join-Path $GitRoot "usr\bin\tar.exe"
        if (Test-Path -LiteralPath $GitTarCommand) {
            return $GitTarCommand
        }
    }
    return $TarCommand
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & git @Arguments
    if ($LASTEXITCODE) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

try {
    $Commit = (& git -C $RepoRoot rev-parse "$Ref^{commit}").Trim()
    if ($LASTEXITCODE -or !$Commit) {
        throw "Git ref not found: $Ref"
    }

    New-Item -ItemType Directory -Path $TemporaryRoot | Out-Null
    Invoke-Git clone --quiet --no-checkout --no-hardlinks `
        $RepoRoot $CheckoutDirectory
    Invoke-Git -C $CheckoutDirectory checkout --quiet --detach $Commit
    Invoke-Git -C $CheckoutDirectory submodule update --init --recursive

    $RootGitDirectory = Join-Path $CheckoutDirectory ".git"
    Remove-Item -LiteralPath $RootGitDirectory -Recurse -Force
    Get-ChildItem -LiteralPath $CheckoutDirectory -Filter ".git" `
        -File -Force -Recurse | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    Move-Item -LiteralPath $CheckoutDirectory -Destination $StageDirectory

    $ForbiddenFiles = Get-ChildItem -LiteralPath $StageDirectory `
        -File -Force -Recurse | Where-Object {
            $_.Name -in @("default.xex", "default.xexp") -or
            $_.Extension -ieq ".iso"
        }
    if ($ForbiddenFiles) {
        throw (
            "Refusing to archive tracked game files: " +
            (($ForbiddenFiles.FullName) -join ", ")
        )
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    foreach ($Path in @($ZipPath, $TarPath, $ChecksumPath)) {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
    }

    Compress-Archive -LiteralPath $StageDirectory `
        -DestinationPath $ZipPath -CompressionLevel Optimal

    $TarCommand = Get-TarCommand
    & $TarCommand -czf $TarPath -C $TemporaryRoot $ArchiveName
    if ($LASTEXITCODE) {
        throw "Creating the tar.gz archive failed with exit code $LASTEXITCODE."
    }

    $Checksums = foreach ($Path in @($ZipPath, $TarPath)) {
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        "$($Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($Path))"
    }
    Set-Content -LiteralPath $ChecksumPath -Value $Checksums -Encoding ASCII

    Write-Output "Archived commit $Commit with recursive submodules."
    Write-Output $ZipPath
    Write-Output $TarPath
    Write-Output $ChecksumPath
} finally {
    if (Test-Path -LiteralPath $TemporaryRoot) {
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force
    }
}
