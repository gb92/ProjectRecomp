[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Validate", "Install")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$SupportedXexSha256 =
    "CFC732340E55DEFDA400E25F03231AA9BB65FD9545B618212F69A4952384A5DD"
$InstallMarker = ".projectrecomp-game"

function Get-NormalizedPath([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $root
    }
    return $fullPath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-Sha256([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = $algorithm.ComputeHash($stream)
        return [BitConverter]::ToString($bytes).Replace("-", "")
    } finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}

function Test-PathsOverlap([string]$First, [string]$Second) {
    $comparison = [StringComparison]::OrdinalIgnoreCase
    $firstPrefix = $First + [IO.Path]::DirectorySeparatorChar
    $secondPrefix = $Second + [IO.Path]::DirectorySeparatorChar
    return $First.Equals($Second, $comparison) -or
        $First.StartsWith($secondPrefix, $comparison) -or
        $Second.StartsWith($firstPrefix, $comparison)
}

function Get-ImportEntries(
    [string]$Directory,
    [string]$RelativeDirectory = ""
) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if (
            !$RelativeDirectory -and
            $item.Name.Equals(
                '$SYSTEMUPDATE',
                [StringComparison]::OrdinalIgnoreCase
            )
        ) {
            continue
        }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Symbolic links and reparse points are not supported: $($item.FullName)"
        }

        $relativePath = if ($RelativeDirectory) {
            Join-Path $RelativeDirectory $item.Name
        } else {
            $item.Name
        }
        [pscustomobject]@{
            Source = $item.FullName
            RelativePath = $relativePath
            IsDirectory = $item.PSIsContainer
            Length = if ($item.PSIsContainer) { 0L } else { $item.Length }
        }

        if ($item.PSIsContainer) {
            Get-ImportEntries $item.FullName $relativePath
        }
    }
}

function Test-GameSource([string]$SourcePath) {
    if (!(Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Extracted game directory not found: $SourcePath"
    }

    $xexPath = Join-Path $SourcePath "default.xex"
    if (!(Test-Path -LiteralPath $xexPath -PathType Leaf)) {
        throw "default.xex was not found in the extracted game directory."
    }
    if (Test-Path -LiteralPath (Join-Path $SourcePath "default.xexp")) {
        throw "default.xexp is unsupported. Import the unpatched base game."
    }

    $actualHash = Get-Sha256 $xexPath
    if (!$actualHash.Equals(
        $SupportedXexSha256,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw (
            "Unsupported default.xex. Expected SHA-256 {0}, found {1}." -f
            $SupportedXexSha256, $actualHash
        )
    }
}

function Install-Game([string]$SourcePath, [string]$DestinationPath) {
    if (Test-PathsOverlap $SourcePath $DestinationPath) {
        throw "The source and destination directories must not overlap."
    }

    $destinationParent = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null

    if (Test-Path -LiteralPath $DestinationPath) {
        $marker = Join-Path $DestinationPath $InstallMarker
        if (
            !(Test-Path -LiteralPath $DestinationPath -PathType Container) -or
            !(Test-Path -LiteralPath $marker -PathType Leaf)
        ) {
            throw (
                "Refusing to replace a directory not managed by " +
                "ProjectRecomp: $DestinationPath"
            )
        }
    }

    $entries = @(Get-ImportEntries $SourcePath)
    $files = @($entries | Where-Object { !$_.IsDirectory })
    $totalBytes = [long](($files | Measure-Object Length -Sum).Sum)
    $driveRoot = [IO.Path]::GetPathRoot($DestinationPath)
    $availableBytes = [IO.DriveInfo]::new($driveRoot).AvailableFreeSpace
    if ($availableBytes -lt $totalBytes) {
        throw (
            "Not enough free space. The import needs {0:N1} GiB, but only " +
            "{1:N1} GiB is available." -f
            ($totalBytes / 1GB), ($availableBytes / 1GB)
        )
    }

    $suffix = [Guid]::NewGuid().ToString("N")
    $staging = Join-Path $destinationParent ".game.import-$suffix"
    $backup = Join-Path $destinationParent ".game.backup-$suffix"
    $copiedBytes = 0L
    $lastPercent = -1

    try {
        New-Item -ItemType Directory -Path $staging | Out-Null
        foreach ($entry in $entries) {
            $target = Join-Path $staging $entry.RelativePath
            if ($entry.IsDirectory) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
                -Force | Out-Null
            Copy-Item -LiteralPath $entry.Source -Destination $target -Force
            $copiedBytes += $entry.Length
            $percent = if ($totalBytes) {
                [Math]::Floor(($copiedBytes * 100.0) / $totalBytes)
            } else {
                100
            }
            if ($percent -ne $lastPercent) {
                Write-Output "PROGRESS:$percent"
                $lastPercent = $percent
            }
        }

        $copiedHash = Get-Sha256 (Join-Path $staging "default.xex")
        if (!$copiedHash.Equals(
            $SupportedXexSha256,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "The copied default.xex failed verification."
        }
        Set-Content -LiteralPath (Join-Path $staging $InstallMarker) `
            -Value "xex_sha256=$($SupportedXexSha256.ToLowerInvariant())" `
            -Encoding ASCII

        if (Test-Path -LiteralPath $DestinationPath) {
            Move-Item -LiteralPath $DestinationPath -Destination $backup
        }
        try {
            Move-Item -LiteralPath $staging -Destination $DestinationPath
        } catch {
            if (
                (Test-Path -LiteralPath $backup) -and
                !(Test-Path -LiteralPath $DestinationPath)
            ) {
                Move-Item -LiteralPath $backup -Destination $DestinationPath
            }
            throw
        }
        if (Test-Path -LiteralPath $backup) {
            try {
                Remove-Item -LiteralPath $backup -Recurse -Force
            } catch {
                Write-Output (
                    "WARNING:The previous import could not be removed: " +
                    "$backup. $($_.Exception.Message)"
                )
            }
        }
    } finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}

try {
    $sourcePath = Get-NormalizedPath $Source
    $destinationPath = Get-NormalizedPath $Destination
    Test-GameSource $sourcePath

    if ($Mode -eq "Install") {
        Install-Game $sourcePath $destinationPath
        Write-Output "Game import completed."
    } else {
        Write-Output "Supported base game validated."
    }
} catch {
    Write-Output "ERROR:$($_.Exception.Message)"
    exit 1
}
