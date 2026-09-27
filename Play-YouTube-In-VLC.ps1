# Play a YouTube video in VLC by resolving its streams with yt-dlp.
# Accepts URLs with or without https:// and handles separate video/audio streams.

$ErrorActionPreference = "Stop"

function Find-Executable {
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [string[]]$FallbackPaths = @()
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($candidate in $FallbackPaths) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machinePath, $userPath) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";"
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$WingetPath,

        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    Write-Host "$DisplayName is missing. Installing it with WinGet..." -ForegroundColor Yellow

    & $WingetPath install `
        --id $PackageId `
        --exact `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        throw "WinGet could not install $DisplayName (package: $PackageId)."
    }

    Refresh-ProcessPath
}

try {
    $enteredUrl = (Read-Host "Enter the YouTube video URL").Trim()

    if ([string]::IsNullOrWhiteSpace($enteredUrl)) {
        throw "No URL was entered."
    }

    # Remove matching quotation marks that may have been copied with the URL.
    if ($enteredUrl.Length -ge 2) {
        $firstCharacter = $enteredUrl[0]
        $lastCharacter = $enteredUrl[$enteredUrl.Length - 1]
        if (($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or
            ($firstCharacter -eq "'" -and $lastCharacter -eq "'")) {
            $enteredUrl = $enteredUrl.Substring(1, $enteredUrl.Length - 2).Trim()
        }
    }

    # A pasted URL such as www.youtube.com/watch?v=... needs a URI scheme.
    if ($enteredUrl -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $enteredUrl = "https://$enteredUrl"
    }

    $youtubeUri = $null
    if (-not [Uri]::TryCreate($enteredUrl, [UriKind]::Absolute, [ref]$youtubeUri)) {
        throw "The entered value is not a valid URL."
    }

    if ($youtubeUri.Scheme -notin @("http", "https")) {
        throw "Only HTTP and HTTPS YouTube URLs are supported."
    }

    $hostName = $youtubeUri.DnsSafeHost.ToLowerInvariant()
    $isYouTubeHost = (
        $hostName -eq "youtube.com" -or
        $hostName.EndsWith(".youtube.com") -or
        $hostName -eq "youtu.be" -or
        $hostName.EndsWith(".youtu.be") -or
        $hostName -eq "youtube-nocookie.com" -or
        $hostName.EndsWith(".youtube-nocookie.com")
    )

    if (-not $isYouTubeHost) {
        throw "This script accepts only YouTube or youtu.be URLs."
    }

    # Refresh PATH so this script also works when launched from a PowerShell
    # window that was open before WinGet installed a required command.
    Refresh-ProcessPath

    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    $windowsApps = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    $wingetPath = Find-Executable -CommandName "winget.exe" -FallbackPaths @(
        (Join-Path $windowsApps "winget.exe")
    )

    $ytDlpPath = Find-Executable -CommandName "yt-dlp.exe" -FallbackPaths @(
        (Join-Path $wingetLinks "yt-dlp.exe")
    )

    if (-not $ytDlpPath) {
        if (-not $wingetPath) {
            throw "yt-dlp is missing and WinGet is unavailable. Install Microsoft App Installer, then run this script again."
        }

        # The yt-dlp WinGet package currently declares Deno and FFmpeg as
        # dependencies, but both are also checked independently below.
        Install-WingetPackage `
            -WingetPath $wingetPath `
            -PackageId "yt-dlp.yt-dlp" `
            -DisplayName "yt-dlp"

        $ytDlpPath = Find-Executable -CommandName "yt-dlp.exe" -FallbackPaths @(
            (Join-Path $wingetLinks "yt-dlp.exe")
        )
    }

    $denoPath = Find-Executable -CommandName "deno.exe" -FallbackPaths @(
        (Join-Path $wingetLinks "deno.exe")
    )

    if (-not $denoPath) {
        if (-not $wingetPath) {
            throw "Deno is missing and WinGet is unavailable."
        }

        Install-WingetPackage `
            -WingetPath $wingetPath `
            -PackageId "DenoLand.Deno" `
            -DisplayName "Deno"

        $denoPath = Find-Executable -CommandName "deno.exe" -FallbackPaths @(
            (Join-Path $wingetLinks "deno.exe")
        )
    }

    $ffmpegPath = Find-Executable -CommandName "ffmpeg.exe" -FallbackPaths @(
        (Join-Path $wingetLinks "ffmpeg.exe")
    )

    if (-not $ffmpegPath) {
        if (-not $wingetPath) {
            throw "FFmpeg is missing and WinGet is unavailable."
        }

        Install-WingetPackage `
            -WingetPath $wingetPath `
            -PackageId "yt-dlp.FFmpeg" `
            -DisplayName "FFmpeg"

        $ffmpegPath = Find-Executable -CommandName "ffmpeg.exe" -FallbackPaths @(
            (Join-Path $wingetLinks "ffmpeg.exe")
        )
    }

    if (-not $ytDlpPath -or -not $denoPath -or -not $ffmpegPath) {
        throw "One or more required tools could not be found after installation."
    }

    $vlcCandidates = @()
    if ($env:ProgramFiles) {
        $vlcCandidates += Join-Path $env:ProgramFiles "VideoLAN\VLC\vlc.exe"
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) {
        $vlcCandidates += Join-Path $programFilesX86 "VideoLAN\VLC\vlc.exe"
    }

    $vlcPath = Find-Executable -CommandName "vlc.exe" -FallbackPaths $vlcCandidates
    if (-not $vlcPath) {
        throw "VLC was not found. Install VLC or add vlc.exe to PATH."
    }

    Write-Host "Resolving YouTube streams..." -ForegroundColor Cyan

    # Prefer a broadly compatible H.264/AAC combination up to 1080p.
    # Fall back to any <=1080p video/audio pair, a combined format, or any format.
    $formatSelector = "bv[vcodec~='^avc1'][height<=1080]+ba[acodec~='^mp4a']/bv[height<=1080]+ba/b[height<=1080]/b"

    $ytDlpOutput = @(
        & $ytDlpPath `
            --no-playlist `
            --no-warnings `
            --format $formatSelector `
            --get-url `
            $youtubeUri.AbsoluteUri
    )

    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp could not resolve this YouTube video."
    }

    $streamUrls = @(
        $ytDlpOutput |
            Where-Object { $_ -is [string] -and $_ -match '^https?://' }
    )

    if ($streamUrls.Count -eq 0) {
        throw "No playable stream URL was returned by yt-dlp."
    }

    Write-Host "Opening the video in VLC..." -ForegroundColor Green

    if ($streamUrls.Count -eq 1) {
        & $vlcPath "--network-caching=3000" $streamUrls[0]
    }
    else {
        $videoStreamUrl = $streamUrls[0]
        $audioStreamUrl = $streamUrls[1]
        & $vlcPath `
            "--network-caching=3000" `
            "--input-slave=$audioStreamUrl" `
            $videoStreamUrl
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
