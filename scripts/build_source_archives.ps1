[CmdletBinding()]
param(
    [ValidatePattern("^[0-9A-Za-z][0-9A-Za-z._-]*$")]
    [string]$Version = "0.1.0-alpha.1",
    [string]$Ref = "HEAD",
    [string]$OutputDirectory = "dist"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OutputDirectory = [IO.Path]::GetFullPath(
    (Join-Path $RepoRoot $OutputDirectory)
)
$ArchiveName = "ProjectRecomp-$Version-Source"
$TemporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) "projectrecomp-source-$([Guid]::NewGuid().ToString('N'))"
$StageDirectory = Join-Path $TemporaryRoot $ArchiveName
$ZipPath = Join-Path $OutputDirectory "$ArchiveName.zip"
$TarPath = Join-Path $OutputDirectory "$ArchiveName.tar.gz"
$ChecksumPath = Join-Path $OutputDirectory "$ArchiveName-SHA256SUMS.txt"

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
        $RepoRoot $StageDirectory
    Invoke-Git -C $StageDirectory checkout --quiet --detach $Commit
    Invoke-Git -C $StageDirectory submodule update --init --recursive

    $RootGitDirectory = Join-Path $StageDirectory ".git"
    Remove-Item -LiteralPath $RootGitDirectory -Recurse -Force
    Get-ChildItem -LiteralPath $StageDirectory -Filter ".git" `
        -File -Force -Recurse | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
        }

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

    & tar -czf $TarPath -C $TemporaryRoot $ArchiveName
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
