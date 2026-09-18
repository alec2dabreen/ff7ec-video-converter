$ErrorActionPreference = "Stop"

if (Test-Path Variable:\PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# ============================================================
# Final Fantasy VII: Ever Crisis
# Video Converter
#
# Created by: Alec Breen | TheBreenis
# GitHub: https://github.com/alec2dabreen/ff7ec-video-converter
#
# CRI key:
#   0x0011DA4DE45ADE
#
# Final MP4:
#   Video: Original decrypted VP9, stream copied
#   Audio: Decrypted HCA -> WAV -> AAC 256 kbps
# ============================================================


# ============================================================
# Configuration
# ============================================================

$SourceRoot = "C:\Program Files (x86)\Steam\steamapps\common\FF7EC\octo\v1\3001"

$OutputRoot = "C:\FF7EC-Decrypt"

$FinalRoot = Join-Path `
    $OutputRoot `
    "Final"

$WorkingRoot = Join-Path `
    $OutputRoot `
    "Working"

$Working3001 = Join-Path `
    $WorkingRoot `
    "octo\v1\3001"

$MinimumVideoFileSize = 10KB

$UsmKey = "0x0011DA4DE45ADE"

$RepositoryUrl = "https://github.com/alec2dabreen/ff7ec-video-converter"


# ============================================================
# Environment helpers
# ============================================================

function Refresh-EnvironmentPath {

    $MachinePath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::Machine
    )

    $UserPath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::User
    )

    $env:Path = "$MachinePath;$UserPath"

    $ExtraPaths = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links")
    )

    foreach ($ExtraPath in $ExtraPaths) {

        if (
            (Test-Path $ExtraPath) -and
            ($env:Path -notlike "*$ExtraPath*")
        ) {
            $env:Path += ";$ExtraPath"
        }
    }
}


function Test-CommandExists {

    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    return [bool](
        Get-Command $Command -ErrorAction SilentlyContinue
    )
}


# ============================================================
# Winget
# ============================================================

function Ensure-Winget {

    Refresh-EnvironmentPath

    if (Test-CommandExists "winget") {

        Write-Host "[OK] Winget" -ForegroundColor Green
        return
    }

    Write-Host "[MISSING] Winget" -ForegroundColor Yellow
    Write-Host "Installing Microsoft App Installer..."

    $TempDir = Join-Path `
        $env:TEMP `
        "winget-bootstrap"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $TempDir |
        Out-Null

    $Bundle = Join-Path `
        $TempDir `
        "Microsoft.DesktopAppInstaller.msixbundle"

    try {

        Invoke-WebRequest `
            -Uri "https://aka.ms/getwinget" `
            -OutFile $Bundle `
            -UseBasicParsing

        Add-AppxPackage `
            -Path $Bundle
    }
    catch {

        throw "Winget installation failed: $($_.Exception.Message)"
    }

    Refresh-EnvironmentPath

    Start-Sleep -Seconds 2

    Refresh-EnvironmentPath

    if (-not (Test-CommandExists "winget")) {

        throw "Microsoft App Installer was installed, but winget.exe could not be located."
    }

    Write-Host "[OK] Winget" -ForegroundColor Green
}


function Install-WingetPackage {

    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    Write-Host "[MISSING] $DisplayName" -ForegroundColor Yellow
    Write-Host "Installing $DisplayName..."

    & winget install `
        --id $PackageId `
        --exact `
        --accept-package-agreements `
        --accept-source-agreements

    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {

        throw "Winget failed to install $DisplayName. Exit code: $ExitCode"
    }

    Refresh-EnvironmentPath
}


# ============================================================
# Logging
# ============================================================

function Add-MainLog {

    param(
        [string]$RelativeSource,
        [string]$EmbeddedFileName,
        [long]$SourceSizeBytes,
        [string]$ConvertedMP4Name,
        [string]$Status,
        [string]$VideoWarning,
        [string]$Ivf,
        [string]$Hca,
        [string]$Wav,
        [string]$Mp4
    )

    $Row = [PSCustomObject]@{
        Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        RelativeSource   = $RelativeSource
        EmbeddedFileName = $EmbeddedFileName
        SourceSizeBytes  = $SourceSizeBytes
        ConvertedMP4Name = $ConvertedMP4Name
        Key              = $UsmKey
        Status           = $Status
        VideoWarning     = $VideoWarning
        IVF              = $Ivf
        HCA              = $Hca
        WAV              = $Wav
        MP4              = $Mp4
    }

    if (Test-Path $script:CsvLog) {

        $Row |
            Export-Csv `
                $script:CsvLog `
                -NoTypeInformation `
                -Append
    }
    else {

        $Row |
            Export-Csv `
                $script:CsvLog `
                -NoTypeInformation
    }
}


function Add-FailureLog {

    param(
        [string]$RelativeSource,
        [string]$EmbeddedFileName,
        [string]$Stage,
        [string]$Message
    )

    $Row = [PSCustomObject]@{
        Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        RelativeSource   = $RelativeSource
        EmbeddedFileName = $EmbeddedFileName
        Stage            = $Stage
        Key              = $UsmKey
        Message          = $Message
    }

    if (Test-Path $script:FailureLog) {

        $Row |
            Export-Csv `
                $script:FailureLog `
                -NoTypeInformation `
                -Append
    }
    else {

        $Row |
            Export-Csv `
                $script:FailureLog `
                -NoTypeInformation
    }
}


function Add-SkippedLog {

    param(
        [string]$RelativeSource,
        [long]$SizeBytes,
        [string]$Reason
    )

    $Row = [PSCustomObject]@{
        Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        RelativeSource = $RelativeSource
        SizeBytes      = $SizeBytes
        SizeMB         = [math]::Round(
            $SizeBytes / 1MB,
            4
        )
        Reason         = $Reason
    }

    if (Test-Path $script:SkippedLog) {

        $Row |
            Export-Csv `
                $script:SkippedLog `
                -NoTypeInformation `
                -Append
    }
    else {

        $Row |
            Export-Csv `
                $script:SkippedLog `
                -NoTypeInformation
    }
}


function Add-FileMap {

    param(
        [Parameter(Mandatory)]
        [string]$OriginalHashedFileName,

        [Parameter(Mandatory)]
        [string]$ConvertedMP4Name
    )

    $Row = [PSCustomObject]@{
        OriginalHashedFileName = $OriginalHashedFileName
        ConvertedMP4Name       = $ConvertedMP4Name
    }

    if (Test-Path $script:FileMapLog) {

        $Row |
            Export-Csv `
                $script:FileMapLog `
                -NoTypeInformation `
                -Append
    }
    else {

        $Row |
            Export-Csv `
                $script:FileMapLog `
                -NoTypeInformation
    }
}


# ============================================================
# CRID identification
# ============================================================

function Test-CridFile {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {

        $Stream = [System.IO.File]::OpenRead($Path)

        try {

            $Buffer = New-Object byte[] 4

            $Count = $Stream.Read(
                $Buffer,
                0,
                4
            )
        }
        finally {

            $Stream.Dispose()
        }

        if ($Count -ne 4) {
            return $false
        }

        $Signature = [System.Text.Encoding]::ASCII.GetString(
            $Buffer
        )

        return ($Signature -eq "CRID")
    }
    catch {

        return $false
    }
}


function Test-UsmHasVideo {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {

        $FileInfo = Get-Item $Path

        if ($FileInfo.Length -le $MinimumVideoFileSize) {
            return $false
        }

        $MaxRead = [Math]::Min(
            $FileInfo.Length,
            2MB
        )

        $Stream = [System.IO.File]::OpenRead($Path)

        try {

            $Buffer = New-Object byte[] $MaxRead

            $BytesRead = $Stream.Read(
                $Buffer,
                0,
                $MaxRead
            )
        }
        finally {

            $Stream.Dispose()
        }

        if ($BytesRead -le 0) {
            return $false
        }

        $Text = [System.Text.Encoding]::ASCII.GetString(
            $Buffer,
            0,
            $BytesRead
        )

        return $Text.Contains("@SFV")
    }
    catch {

        return $false
    }
}


# ============================================================
# Embedded USM metadata
# ============================================================

function Get-UsmMetadata {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {

        $MetadataOutput = @(
            & $script:CriCodecsCommand `
                -m `
                --json `
                $Path `
                2>$null
        )

        $ExitCode = $LASTEXITCODE

        if ($ExitCode -ne 0) {
            return $null
        }

        $JsonText = (
            $MetadataOutput |
                ForEach-Object {
                    $_.ToString()
                }
        ) -join ""

        if ([string]::IsNullOrWhiteSpace($JsonText)) {
            return $null
        }

        return (
            $JsonText |
                ConvertFrom-Json
        )
    }
    catch {

        return $null
    }
}


function Get-EmbeddedFileName {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Metadata = Get-UsmMetadata `
        -Path $Path

    if (
        $Metadata -and
        $Metadata.container_filename
    ) {

        return [System.IO.Path]::GetFileName(
            $Metadata.container_filename.ToString()
        )
    }

    return $null
}


# ============================================================
# Safe final MP4 filename
# ============================================================

function Get-FinalMp4Path {

    param(
        [Parameter(Mandatory)]
        [string]$EmbeddedFileName,

        [Parameter(Mandatory)]
        [string]$SourceHash
    )

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
        $EmbeddedFileName
    )


    foreach (
        $InvalidChar in
        [System.IO.Path]::GetInvalidFileNameChars()
    ) {

        $BaseName = $BaseName.Replace(
            $InvalidChar,
            "_"
        )
    }


    if ([string]::IsNullOrWhiteSpace($BaseName)) {
        $BaseName = $SourceHash
    }


    $CandidateName = "$BaseName.mp4"

    $CandidatePath = Join-Path `
        $FinalRoot `
        $CandidateName


    if (-not (Test-Path $CandidatePath)) {

        return [PSCustomObject]@{
            Name = $CandidateName
            Path = $CandidatePath
        }
    }


    $SuffixLength = [Math]::Min(
        8,
        $SourceHash.Length
    )

    $ShortHash = $SourceHash.Substring(
        0,
        $SuffixLength
    )


    $CandidateName = "${BaseName}_${ShortHash}.mp4"

    $CandidatePath = Join-Path `
        $FinalRoot `
        $CandidateName


    if (-not (Test-Path $CandidatePath)) {

        return [PSCustomObject]@{
            Name = $CandidateName
            Path = $CandidatePath
        }
    }


    $Counter = 2

    do {

        $CandidateName = "${BaseName}_${ShortHash}_$Counter.mp4"

        $CandidatePath = Join-Path `
            $FinalRoot `
            $CandidateName

        $Counter++

    }
    while (Test-Path $CandidatePath)


    return [PSCustomObject]@{
        Name = $CandidateName
        Path = $CandidatePath
    }
}


# ============================================================
# IVF validation
# ============================================================

function Get-IvfValidation {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Leaf)) {

        return [PSCustomObject]@{
            Valid   = $false
            Warning = $false
            Message = "IVF file does not exist."
        }
    }


    # --------------------------------------------------------
    # FFprobe must recognize the stream as VP9
    # --------------------------------------------------------

    try {

        $CodecOutput = @(
            & ffprobe `
                -v error `
                -select_streams v:0 `
                -show_entries stream=codec_name `
                -of default=noprint_wrappers=1:nokey=1 `
                $Path `
                2>&1
        )

        $ProbeExitCode = $LASTEXITCODE
    }
    catch {

        return [PSCustomObject]@{
            Valid   = $false
            Warning = $false
            Message = "FFprobe could not inspect the extracted video."
        }
    }


    if ($ProbeExitCode -ne 0) {

        return [PSCustomObject]@{
            Valid   = $false
            Warning = $false
            Message = "FFprobe rejected the extracted IVF."
        }
    }


    $CodecName = (
        $CodecOutput |
            Out-String
    ).Trim()


    if ($CodecName -ne "vp9") {

        return [PSCustomObject]@{
            Valid   = $false
            Warning = $false
            Message = "Extracted video codec is '$CodecName' instead of VP9."
        }
    }


    # --------------------------------------------------------
    # Complete decode pass without -xerror
    #
    # Recoverable VP9 errors are warnings only.
    # --------------------------------------------------------

    try {

        $DecodeOutput = @(
            & ffmpeg `
                -hide_banner `
                -v error `
                -i $Path `
                -map 0:v:0 `
                -f null `
                NUL `
                2>&1
        )

        $DecodeExitCode = $LASTEXITCODE
    }
    catch {

        $DecodeOutput = @(
            $_.Exception.Message
        )

        $DecodeExitCode = 1
    }


    $WarningText = (
        $DecodeOutput |
            ForEach-Object {
                $_.ToString()
            }
    ) -join " "


    if (
        $DecodeOutput.Count -gt 0 -or
        $DecodeExitCode -ne 0
    ) {

        if ([string]::IsNullOrWhiteSpace($WarningText)) {

            $WarningText = "FFmpeg reported recoverable VP9 decode errors."
        }

        if ($WarningText.Length -gt 500) {

            $WarningText = $WarningText.Substring(
                0,
                500
            ) + "..."
        }


        return [PSCustomObject]@{
            Valid   = $true
            Warning = $true
            Message = $WarningText
        }
    }


    return [PSCustomObject]@{
        Valid   = $true
        Warning = $false
        Message = ""
    }
}


function Test-Wav {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        return $false
    }

    try {

        $null = & ffmpeg `
            -hide_banner `
            -loglevel error `
            -xerror `
            -i $Path `
            -map 0:a:0 `
            -f null `
            NUL `
            2>&1

        $ExitCode = $LASTEXITCODE
    }
    catch {

        return $false
    }

    return ($ExitCode -eq 0)
}


# ============================================================
# CriCodecs extraction
#
# Single-stream:
#   -o itself becomes the IVF
#
# Multi-stream:
#   -o becomes a directory containing temp.ivf and temp.hca
# ============================================================

function Invoke-CriExtraction {

    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    if (Test-Path $OutputPath) {

        Remove-Item `
            $OutputPath `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }


    try {

        $null = & $script:CriCodecsCommand `
            $InputPath `
            --raw `
            --key $UsmKey `
            -o $OutputPath `
            2>&1

        $CriExitCode = $LASTEXITCODE
    }
    catch {

        return [PSCustomObject]@{
            Success      = $false
            IVF          = $null
            HCA          = $null
            VideoWarning = $false
            WarningText  = ""
            Message      = $_.Exception.Message
        }
    }


    if ($CriExitCode -ne 0) {

        return [PSCustomObject]@{
            Success      = $false
            IVF          = $null
            HCA          = $null
            VideoWarning = $false
            WarningText  = ""
            Message      = "CriCodecs exited with code $CriExitCode."
        }
    }


    # --------------------------------------------------------
    # Single-stream
    # --------------------------------------------------------

    if (Test-Path $OutputPath -PathType Leaf) {

        $Validation = Get-IvfValidation `
            -Path $OutputPath


        if (-not $Validation.Valid) {

            return [PSCustomObject]@{
                Success      = $false
                IVF          = $OutputPath
                HCA          = $null
                VideoWarning = $false
                WarningText  = ""
                Message      = $Validation.Message
            }
        }


        return [PSCustomObject]@{
            Success      = $true
            IVF          = $OutputPath
            HCA          = $null
            VideoWarning = $Validation.Warning
            WarningText  = $Validation.Message
            Message      = "Valid single-stream VP9."
        }
    }


    # --------------------------------------------------------
    # Multi-stream
    # --------------------------------------------------------

    if (Test-Path $OutputPath -PathType Container) {

        $IvfFile = Get-ChildItem `
            $OutputPath `
            -Recurse `
            -File `
            -Filter "*.ivf" `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1


        $HcaFile = Get-ChildItem `
            $OutputPath `
            -Recurse `
            -File `
            -Filter "*.hca" `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1


        if (-not $IvfFile) {

            return [PSCustomObject]@{
                Success      = $false
                IVF          = $null
                HCA          = if ($HcaFile) {
                    $HcaFile.FullName
                }
                else {
                    $null
                }
                VideoWarning = $false
                WarningText  = ""
                Message      = "CriCodecs created an output directory, but no IVF video stream was found."
            }
        }


        $Validation = Get-IvfValidation `
            -Path $IvfFile.FullName


        if (-not $Validation.Valid) {

            return [PSCustomObject]@{
                Success      = $false
                IVF          = $IvfFile.FullName
                HCA          = if ($HcaFile) {
                    $HcaFile.FullName
                }
                else {
                    $null
                }
                VideoWarning = $false
                WarningText  = ""
                Message      = $Validation.Message
            }
        }


        return [PSCustomObject]@{
            Success      = $true
            IVF          = $IvfFile.FullName
            HCA          = if ($HcaFile) {
                $HcaFile.FullName
            }
            else {
                $null
            }
            VideoWarning = $Validation.Warning
            WarningText  = $Validation.Message
            Message      = "Valid multi-stream VP9."
        }
    }


    return [PSCustomObject]@{
        Success      = $false
        IVF          = $null
        HCA          = $null
        VideoWarning = $false
        WarningText  = ""
        Message      = "CriCodecs returned success but produced no output."
    }
}


# ============================================================
# HCA to WAV using PyCriCodecs
# ============================================================

function Convert-HcaToWav {

    param(
        [Parameter(Mandatory)]
        [string]$HcaPath,

        [Parameter(Mandatory)]
        [string]$WavPath
    )

    if (Test-Path $WavPath) {

        Remove-Item `
            $WavPath `
            -Force `
            -ErrorAction SilentlyContinue
    }


    $PythonHelper = Join-Path `
        $env:TEMP `
        ("ff7ec_hca_" + [Guid]::NewGuid().ToString("N") + ".py")


    $PythonCode = @'
import sys
from PyCriCodecs import HCA

input_file = sys.argv[1]
output_file = sys.argv[2]
key_text = sys.argv[3]

key = int(key_text, 16)

hca = HCA(input_file, key=key)

wav = hca.decode()

with open(output_file, "wb") as f:
    f.write(wav)
'@


    Set-Content `
        -Path $PythonHelper `
        -Value $PythonCode `
        -Encoding UTF8


    try {

        if ($script:PythonCommand -eq "py") {

            $null = & py `
                $PythonHelper `
                $HcaPath `
                $WavPath `
                $UsmKey `
                2>&1
        }
        elseif ($script:PythonCommand -eq "python") {

            $null = & python `
                $PythonHelper `
                $HcaPath `
                $WavPath `
                $UsmKey `
                2>&1
        }
        else {

            $null = & $script:PythonCommand `
                $PythonHelper `
                $HcaPath `
                $WavPath `
                $UsmKey `
                2>&1
        }

        $ExitCode = $LASTEXITCODE
    }
    catch {

        $ExitCode = 1
    }
    finally {

        Remove-Item `
            $PythonHelper `
            -Force `
            -ErrorAction SilentlyContinue
    }


    if (
        $ExitCode -eq 0 -and
        (Test-Path $WavPath -PathType Leaf) -and
        (Test-Wav $WavPath)
    ) {

        return $true
    }


    if (Test-Path $WavPath) {

        Remove-Item `
            $WavPath `
            -Force `
            -ErrorAction SilentlyContinue
    }


    return $false
}


# ============================================================
# Clean successful working files
# ============================================================

function Remove-SuccessfulWorkingFiles {

    param(
        [string]$Ivf,
        [string]$Hca,
        [string]$Wav,
        [string]$WorkingDirectory
    )

    foreach ($WorkingFile in @(
        $Ivf,
        $Hca,
        $Wav
    )) {

        if (
            $WorkingFile -and
            (Test-Path $WorkingFile -PathType Leaf)
        ) {

            Remove-Item `
                $WorkingFile `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }


    # --------------------------------------------------------
    # Remove empty directories upward until WorkingRoot
    # --------------------------------------------------------

    $DirectoryToCheck = $WorkingDirectory


    while (
        $DirectoryToCheck -and
        $DirectoryToCheck.StartsWith(
            $WorkingRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        $DirectoryToCheck -ne $WorkingRoot
    ) {

        if (-not (Test-Path $DirectoryToCheck -PathType Container)) {

            $DirectoryToCheck = Split-Path `
                $DirectoryToCheck `
                -Parent

            continue
        }


        $RemainingItems = @(
            Get-ChildItem `
                $DirectoryToCheck `
                -Force `
                -ErrorAction SilentlyContinue
        )


        if ($RemainingItems.Count -gt 0) {
            break
        }


        Remove-Item `
            $DirectoryToCheck `
            -Force `
            -ErrorAction SilentlyContinue


        $DirectoryToCheck = Split-Path `
            $DirectoryToCheck `
            -Parent
    }
}


# ============================================================
# Startup
# ============================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Final Fantasy VII: Ever Crisis" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Created by: Alec Breen | TheBreenis"
Write-Host "GitHub: $RepositoryUrl" -ForegroundColor DarkCyan

Write-Host ""
Write-Host "Source:"
Write-Host "  $SourceRoot"

Write-Host ""
Write-Host "Final MP4 folder:"
Write-Host "  $FinalRoot"

Write-Host ""
Write-Host "CRI key:"
Write-Host "  $UsmKey"

Write-Host ""


if (-not (Test-Path $SourceRoot)) {

    throw "FF7EC source directory was not found: $SourceRoot"
}


# ============================================================
# Dependencies
# ============================================================

Write-Host "Checking dependencies..." -ForegroundColor Cyan
Write-Host ""

Refresh-EnvironmentPath

Ensure-Winget


# ------------------------------------------------------------
# Python
# ------------------------------------------------------------

$script:PythonCommand = $null


if (Test-CommandExists "py") {

    try {

        $null = & py --version 2>&1

        if ($LASTEXITCODE -eq 0) {

            $script:PythonCommand = "py"
        }
    }
    catch {}
}


if (
    -not $script:PythonCommand -and
    (Test-CommandExists "python")
) {

    try {

        $PythonResult = & python --version 2>&1

        if (
            $LASTEXITCODE -eq 0 -and
            $PythonResult -match "^Python\s+\d"
        ) {

            $script:PythonCommand = "python"
        }
    }
    catch {}
}


if (-not $script:PythonCommand) {

    Install-WingetPackage `
        -PackageId "Python.Python.3.13" `
        -DisplayName "Python 3.13"

    Refresh-EnvironmentPath

    if (Test-CommandExists "py") {

        $script:PythonCommand = "py"
    }
    elseif (Test-CommandExists "python") {

        $script:PythonCommand = "python"
    }
    else {

        $PythonExe = Get-ChildItem `
            "$env:LOCALAPPDATA\Programs\Python" `
            -Filter "python.exe" `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($PythonExe) {

            $script:PythonCommand = $PythonExe.FullName
        }
    }
}


if (-not $script:PythonCommand) {

    throw "Python could not be located."
}


Write-Host "[OK] Python" -ForegroundColor Green


# ------------------------------------------------------------
# FFmpeg and FFprobe
# ------------------------------------------------------------

if (
    -not (Test-CommandExists "ffmpeg") -or
    -not (Test-CommandExists "ffprobe")
) {

    Install-WingetPackage `
        -PackageId "Gyan.FFmpeg" `
        -DisplayName "FFmpeg"

    Refresh-EnvironmentPath
}


if (-not (Test-CommandExists "ffmpeg")) {

    throw "FFmpeg could not be located."
}


if (-not (Test-CommandExists "ffprobe")) {

    throw "FFprobe could not be located."
}


Write-Host "[OK] FFmpeg" -ForegroundColor Green
Write-Host "[OK] FFprobe" -ForegroundColor Green


# ------------------------------------------------------------
# CriCodecs
# ------------------------------------------------------------

$script:CriCodecsCommand = $null


if (Test-CommandExists "cricodecs") {

    $script:CriCodecsCommand = "cricodecs"
}


if (-not $script:CriCodecsCommand) {

    if ($script:PythonCommand -eq "py") {

        & py -m pip install --upgrade cricodecs
    }
    elseif ($script:PythonCommand -eq "python") {

        & python -m pip install --upgrade cricodecs
    }
    else {

        & $script:PythonCommand -m pip install --upgrade cricodecs
    }


    if ($LASTEXITCODE -ne 0) {

        throw "pip failed to install CriCodecs."
    }


    Refresh-EnvironmentPath
}


if (Test-CommandExists "cricodecs") {

    $script:CriCodecsCommand = "cricodecs"
}


if (-not $script:CriCodecsCommand) {

    $PossibleCri = Get-ChildItem `
        "$env:LOCALAPPDATA" `
        -Filter "cricodecs.exe" `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1


    if ($PossibleCri) {

        $script:CriCodecsCommand = $PossibleCri.FullName
    }
}


if (-not $script:CriCodecsCommand) {

    throw "CriCodecs could not be located."
}


Write-Host "[OK] CriCodecs" -ForegroundColor Green


# ------------------------------------------------------------
# PyCriCodecs
# ------------------------------------------------------------

if ($script:PythonCommand -eq "py") {

    $null = & py -c "import PyCriCodecs" 2>&1
}
elseif ($script:PythonCommand -eq "python") {

    $null = & python -c "import PyCriCodecs" 2>&1
}
else {

    $null = & $script:PythonCommand -c "import PyCriCodecs" 2>&1
}


$PyCriInstalled = ($LASTEXITCODE -eq 0)


if (-not $PyCriInstalled) {

    if ($script:PythonCommand -eq "py") {

        & py -m pip install --upgrade PyCriCodecs
    }
    elseif ($script:PythonCommand -eq "python") {

        & python -m pip install --upgrade PyCriCodecs
    }
    else {

        & $script:PythonCommand -m pip install --upgrade PyCriCodecs
    }


    if ($LASTEXITCODE -ne 0) {

        throw "pip failed to install PyCriCodecs."
    }
}


Write-Host "[OK] PyCriCodecs" -ForegroundColor Green

Write-Host ""
Write-Host "All dependencies are ready." -ForegroundColor Green
Write-Host ""


# ============================================================
# Output directories
# ============================================================

New-Item `
    -ItemType Directory `
    -Force `
    -Path $OutputRoot |
    Out-Null

New-Item `
    -ItemType Directory `
    -Force `
    -Path $FinalRoot |
    Out-Null

New-Item `
    -ItemType Directory `
    -Force `
    -Path $Working3001 |
    Out-Null


# ============================================================
# Logs
# ============================================================

$DefaultProcessedFile = Join-Path `
    $OutputRoot `
    "ff7ec-processed.txt"


$script:CsvLog = Join-Path `
    $OutputRoot `
    "ff7ec-decryption-log.csv"


$script:FailureLog = Join-Path `
    $OutputRoot `
    "ff7ec-failures.csv"


$script:SkippedLog = Join-Path `
    $OutputRoot `
    "ff7ec-skipped.csv"


$script:FileMapLog = Join-Path `
    $OutputRoot `
    "ff7ec-file-map.csv"


# ============================================================
# Resume
# ============================================================

$PreviousAnswer = Read-Host `
    "Have you already decrypted files before? (Y/N)"


if ($PreviousAnswer -match "^[Yy]") {

    do {

        $ProcessedFile = Read-Host `
            "Enter path to your previous ff7ec-processed.txt"

        $ProcessedFile = $ProcessedFile.Trim().Trim('"')

    }
    while ([string]::IsNullOrWhiteSpace($ProcessedFile))


    if (-not (Test-Path $ProcessedFile)) {

        throw "Processed-file list was not found: $ProcessedFile"
    }


    Write-Host ""
    Write-Host "Continuing previous run." -ForegroundColor Cyan
    Write-Host "Successfully completed files will be skipped."
}
else {

    $ProcessedFile = $DefaultProcessedFile


    Write-Host ""
    Write-Host "Starting from scratch." -ForegroundColor Cyan
    Write-Host "Existing tracking and log files will be overwritten."


    foreach ($FileToReset in @(
        $ProcessedFile,
        $script:CsvLog,
        $script:FailureLog,
        $script:SkippedLog,
        $script:FileMapLog
    )) {

        if (Test-Path $FileToReset) {

            Remove-Item `
                $FileToReset `
                -Force
        }
    }


    New-Item `
        -ItemType File `
        -Path $ProcessedFile `
        -Force |
        Out-Null
}


# ============================================================
# Load processed entries
# ============================================================

$Processed = @{}


if (Test-Path $ProcessedFile) {

    Get-Content $ProcessedFile |
        ForEach-Object {

            $Entry = $_.Trim()

            if ($Entry) {

                $Processed[
                    $Entry.ToLowerInvariant()
                ] = $true
            }
        }
}


# ============================================================
# Load previous successful signatures when resuming
#
# This allows duplicate detection to continue working across
# multiple runs rather than only inside the current session.
# ============================================================

$CompletedVideoSignatures = @{}


if (Test-Path $script:CsvLog) {

    try {

        $PreviousLogRows = @(
            Import-Csv $script:CsvLog
        )


        foreach ($LogRow in $PreviousLogRows) {

            if (
                $LogRow.Status -like "Success*" -and
                -not [string]::IsNullOrWhiteSpace($LogRow.EmbeddedFileName) -and
                -not [string]::IsNullOrWhiteSpace($LogRow.SourceSizeBytes) -and
                -not [string]::IsNullOrWhiteSpace($LogRow.ConvertedMP4Name)
            ) {

                $Signature = (
                    $LogRow.EmbeddedFileName.ToLowerInvariant() +
                    "|" +
                    $LogRow.SourceSizeBytes
                )


                if (-not $CompletedVideoSignatures.ContainsKey($Signature)) {

                    $SourceHash = ""

                    if ($LogRow.RelativeSource) {

                        $SourceHash = Split-Path `
                            $LogRow.RelativeSource `
                            -Leaf
                    }


                    $CompletedVideoSignatures[$Signature] = [PSCustomObject]@{
                        SourceHash = $SourceHash
                        MP4Name    = $LogRow.ConvertedMP4Name
                    }
                }
            }
        }
    }
    catch {

        Write-Host ""
        Write-Host "Warning: Could not preload duplicate signatures from the previous main log." -ForegroundColor Yellow
        Write-Host ""
    }
}


# ============================================================
# Enumerate source
# ============================================================

Write-Host ""
Write-Host "Enumerating source files..." -ForegroundColor Cyan


$AllFiles = @(
    Get-ChildItem `
        $SourceRoot `
        -Recurse `
        -File
)


$TotalFiles = $AllFiles.Count


Write-Host "Total source files: $TotalFiles"
Write-Host ""


# ============================================================
# Counters
# ============================================================

$CridCount             = 0
$SuccessCount          = 0
$SkipCount             = 0
$FailureCount          = 0
$NonCridCount          = 0
$NotVideoCount         = 0
$AudioCount            = 0
$NoAudioCount          = 0
$AudioFailCount        = 0
$SingleStreamCount     = 0
$MultiStreamCount      = 0
$VideoWarningCount     = 0
$DuplicateNameCount    = 0
$DuplicateContentCount = 0


# ============================================================
# Main loop
# ============================================================

foreach ($File in $AllFiles) {

    $RelativePath = $File.FullName.Substring(
        $SourceRoot.Length
    ).TrimStart("\")


    $RelativeKey = $RelativePath.ToLowerInvariant()


    # --------------------------------------------------------
    # Already processed
    # --------------------------------------------------------

    if ($Processed.ContainsKey($RelativeKey)) {

        $SkipCount++
        continue
    }


    # --------------------------------------------------------
    # CRID
    # --------------------------------------------------------

    if (-not (Test-CridFile $File.FullName)) {

        $NonCridCount++
        continue
    }


    $CridCount++


    # --------------------------------------------------------
    # Tiny CRID
    # --------------------------------------------------------

    if ($File.Length -le $MinimumVideoFileSize) {

        Add-SkippedLog `
            -RelativeSource $RelativePath `
            -SizeBytes $File.Length `
            -Reason "CRID container is 10 KB or smaller."


        $NotVideoCount++
        continue
    }


    # --------------------------------------------------------
    # Must contain video
    # --------------------------------------------------------

    if (-not (Test-UsmHasVideo $File.FullName)) {

        Add-SkippedLog `
            -RelativeSource $RelativePath `
            -SizeBytes $File.Length `
            -Reason "CRID container does not contain an @SFV video stream marker."


        $NotVideoCount++
        continue
    }


    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host "Video candidate" -ForegroundColor Cyan
    Write-Host "  Source hash: $($File.Name)"
    Write-Host ("  Size: {0:N2} MB" -f ($File.Length / 1MB))


    # ========================================================
    # Embedded original filename
    # ========================================================

    $EmbeddedFileName = Get-EmbeddedFileName `
        -Path $File.FullName


    if ([string]::IsNullOrWhiteSpace($EmbeddedFileName)) {

        $EmbeddedFileName = "$($File.Name).usm"

        Write-Host "  Embedded filename unavailable. Using fallback:"
        Write-Host "  $EmbeddedFileName" -ForegroundColor Yellow
    }
    else {

        Write-Host "  Original filename: $EmbeddedFileName"
    }


    # ========================================================
    # Duplicate content detection
    #
    # Same embedded filename + same source size
    # ========================================================

    $VideoSignature = (
        $EmbeddedFileName.ToLowerInvariant() +
        "|" +
        $File.Length.ToString()
    )


    if ($CompletedVideoSignatures.ContainsKey($VideoSignature)) {

        $ExistingVideo = $CompletedVideoSignatures[$VideoSignature]

        $DuplicateContentCount++


        Write-Host ""
        Write-Host "  DUPLICATE SKIPPED" -ForegroundColor Yellow

        Write-Host "  Original filename:"
        Write-Host "    $EmbeddedFileName"

        Write-Host "  Source hash:"
        Write-Host "    $($File.Name)"

        Write-Host "  Source size:"
        Write-Host ("    {0:N0} bytes" -f $File.Length)

        Write-Host "  Already converted as:"
        Write-Host "    $($ExistingVideo.MP4Name)"


        Add-SkippedLog `
            -RelativeSource $RelativePath `
            -SizeBytes $File.Length `
            -Reason (
                "Duplicate video. Embedded filename '$EmbeddedFileName' " +
                "and filesize $($File.Length) bytes match source hash " +
                "'$($ExistingVideo.SourceHash)'."
            )


        # Map this duplicate hash to the existing converted MP4.

        Add-FileMap `
            -OriginalHashedFileName $File.Name `
            -ConvertedMP4Name $ExistingVideo.MP4Name


        # Mark duplicate as processed.

        Add-Content `
            -Path $ProcessedFile `
            -Value $RelativePath


        $Processed[$RelativeKey] = $true

        continue
    }


    # ========================================================
    # Final MP4 filename
    # ========================================================

    $FinalInfo = Get-FinalMp4Path `
        -EmbeddedFileName $EmbeddedFileName `
        -SourceHash $File.Name


    $FinalMp4Name = $FinalInfo.Name
    $FinalMp4 = $FinalInfo.Path


    $ExpectedSimpleName = (
        [System.IO.Path]::GetFileNameWithoutExtension(
            $EmbeddedFileName
        )
    ) + ".mp4"


    if ($FinalMp4Name -ne $ExpectedSimpleName) {

        $DuplicateNameCount++

        Write-Host "  Existing filename detected." -ForegroundColor Yellow
        Write-Host "  Final filename: $FinalMp4Name"
    }


    # ========================================================
    # Working directory mirrors source structure
    # ========================================================

    $RelativeDirectory = $File.DirectoryName.Substring(
        $SourceRoot.Length
    ).TrimStart("\")


    if ($RelativeDirectory) {

        $WorkingDirectory = Join-Path `
            $Working3001 `
            $RelativeDirectory
    }
    else {

        $WorkingDirectory = $Working3001
    }


    New-Item `
        -ItemType Directory `
        -Force `
        -Path $WorkingDirectory |
        Out-Null


    $BaseName = $File.Name


    $FinalIvf = Join-Path `
        $WorkingDirectory `
        "$BaseName.ivf"


    $FinalHca = Join-Path `
        $WorkingDirectory `
        "$BaseName.hca"


    $FinalWav = Join-Path `
        $WorkingDirectory `
        "$BaseName.wav"


    # ========================================================
    # Temporary extraction
    # ========================================================

    $WorkRoot = Join-Path `
        $env:TEMP `
        ("ff7ec_" + [Guid]::NewGuid().ToString("N"))


    New-Item `
        -ItemType Directory `
        -Force `
        -Path $WorkRoot |
        Out-Null


    $ExtractOutput = Join-Path `
        $WorkRoot `
        "extracted"


    try {

        # ====================================================
        # Decrypt
        # ====================================================

        Write-Host "  Decrypting..."


        $Extraction = Invoke-CriExtraction `
            -InputPath $File.FullName `
            -OutputPath $ExtractOutput


        if (-not $Extraction.Success) {

            throw $Extraction.Message
        }


        # ====================================================
        # Stream layout
        # ====================================================

        if (Test-Path $ExtractOutput -PathType Leaf) {

            $SingleStreamCount++

            Write-Host "  Stream layout: Video only" -ForegroundColor DarkGray
        }
        else {

            $MultiStreamCount++

            Write-Host "  Stream layout: Video + additional stream(s)" -ForegroundColor DarkGray
        }


        # ====================================================
        # Video warning
        # ====================================================

        $VideoWarningText = ""


        if ($Extraction.VideoWarning) {

            $VideoWarningCount++

            $VideoWarningText = $Extraction.WarningText


            Write-Host ""
            Write-Host "  VIDEO WARNING" -ForegroundColor Yellow
            Write-Host "  VP9 decoder reported one or more recoverable errors."
            Write-Host "  The movie will still be retained and converted."
            Write-Host ""
        }


        # ====================================================
        # Preserve IVF temporarily
        # ====================================================

        Copy-Item `
            $Extraction.IVF `
            $FinalIvf `
            -Force


        # ====================================================
        # Preserve HCA temporarily
        # ====================================================

        $HasHca = $false
        $HasWav = $false


        if (
            $Extraction.HCA -and
            (Test-Path $Extraction.HCA -PathType Leaf)
        ) {

            Copy-Item `
                $Extraction.HCA `
                $FinalHca `
                -Force

            $HasHca = $true
        }


        # ====================================================
        # Decode HCA
        # ====================================================

        if ($HasHca) {

            Write-Host "  Decoding HCA audio..."


            $HasWav = Convert-HcaToWav `
                -HcaPath $FinalHca `
                -WavPath $FinalWav


            if ($HasWav) {

                $AudioCount++

                Write-Host "  Audio decoded successfully." -ForegroundColor Green
            }
            else {

                $AudioFailCount++

                Write-Host "  Audio decoding failed. Creating video-only MP4." -ForegroundColor Yellow


                Add-FailureLog `
                    -RelativeSource $RelativePath `
                    -EmbeddedFileName $EmbeddedFileName `
                    -Stage "Audio decoding" `
                    -Message "Video decrypted successfully, but HCA audio decoding failed."
            }
        }
        else {

            $NoAudioCount++

            Write-Host "  No HCA audio stream found."
        }


        # ====================================================
        # Create final MP4
        # ====================================================

        if ($HasWav) {

            Write-Host "  Creating final MP4..."


            $null = & ffmpeg `
                -y `
                -hide_banner `
                -loglevel error `
                -i $FinalIvf `
                -i $FinalWav `
                -map 0:v:0 `
                -map 1:a:0 `
                -c:v copy `
                -c:a aac `
                -b:a 256k `
                -movflags +faststart `
                -shortest `
                $FinalMp4 `
                2>&1


            $Mp4ExitCode = $LASTEXITCODE
        }
        else {

            Write-Host "  Creating final video-only MP4..."


            $null = & ffmpeg `
                -y `
                -hide_banner `
                -loglevel error `
                -i $FinalIvf `
                -map 0:v:0 `
                -c:v copy `
                -an `
                -movflags +faststart `
                $FinalMp4 `
                2>&1


            $Mp4ExitCode = $LASTEXITCODE
        }


        if (
            $Mp4ExitCode -ne 0 -or
            -not (Test-Path $FinalMp4 -PathType Leaf)
        ) {

            throw "FFmpeg failed to create the final MP4."
        }


        # ====================================================
        # Register successful signature for duplicate checks
        # ====================================================

        $CompletedVideoSignatures[$VideoSignature] = [PSCustomObject]@{
            SourceHash = $File.Name
            MP4Name    = $FinalMp4Name
        }


        # ====================================================
        # Mark processed
        # ====================================================

        Add-Content `
            -Path $ProcessedFile `
            -Value $RelativePath


        $Processed[$RelativeKey] = $true


        # ====================================================
        # Hash to MP4 map
        # ====================================================

        Add-FileMap `
            -OriginalHashedFileName $File.Name `
            -ConvertedMP4Name $FinalMp4Name


        # ====================================================
        # Status
        # ====================================================

        if ($Extraction.VideoWarning -and $HasWav) {

            $FinalStatus = "Success with audio and video warning"
        }
        elseif ($Extraction.VideoWarning) {

            $FinalStatus = "Success with video warning"
        }
        elseif ($HasWav) {

            $FinalStatus = "Success with audio"
        }
        elseif ($HasHca) {

            $FinalStatus = "Success, video only because HCA decode failed"
        }
        else {

            $FinalStatus = "Success, video has no HCA audio stream"
        }


        # ====================================================
        # Main log
        # ====================================================

        Add-MainLog `
            -RelativeSource $RelativePath `
            -EmbeddedFileName $EmbeddedFileName `
            -SourceSizeBytes $File.Length `
            -ConvertedMP4Name $FinalMp4Name `
            -Status $FinalStatus `
            -VideoWarning $VideoWarningText `
            -Ivf $FinalIvf `
            -Hca $(if ($HasHca) {
                $FinalHca
            }
            else {
                ""
            }) `
            -Wav $(if ($HasWav) {
                $FinalWav
            }
            else {
                ""
            }) `
            -Mp4 $FinalMp4


        # ====================================================
        # Remove successful working files
        # ====================================================

        Remove-SuccessfulWorkingFiles `
            -Ivf $FinalIvf `
            -Hca $FinalHca `
            -Wav $FinalWav `
            -WorkingDirectory $WorkingDirectory


        $SuccessCount++


        # ====================================================
        # Console result
        # ====================================================

        Write-Host ""
        Write-Host "  COMPLETE" -ForegroundColor Green

        Write-Host "  Source hash:"
        Write-Host "    $($File.Name)"

        Write-Host "  Original filename:"
        Write-Host "    $EmbeddedFileName"

        Write-Host "  Converted:"
        Write-Host "    $FinalMp4Name"

        Write-Host "  Final location:"
        Write-Host "    $FinalMp4"


        if ($HasWav) {

            Write-Host "  Audio: Yes" -ForegroundColor Green
        }
        else {

            Write-Host "  Audio: No"
        }


        if ($Extraction.VideoWarning) {

            Write-Host "  Video warning: Yes" -ForegroundColor Yellow
        }
        else {

            Write-Host "  Video warning: No"
        }


        Write-Host "  Working files removed: Yes" -ForegroundColor DarkGray
    }
    catch {

        $FailureCount++

        $Message = $_.Exception.Message


        Write-Host ""
        Write-Host "  FAILED: $Message" -ForegroundColor Red
        Write-Host "  Working files have been retained where available." -ForegroundColor Yellow


        Add-MainLog `
            -RelativeSource $RelativePath `
            -EmbeddedFileName $EmbeddedFileName `
            -SourceSizeBytes $File.Length `
            -ConvertedMP4Name "" `
            -Status ("Failed: " + $Message) `
            -VideoWarning "" `
            -Ivf $(if (Test-Path $FinalIvf -PathType Leaf) {
                $FinalIvf
            }
            else {
                ""
            }) `
            -Hca $(if (Test-Path $FinalHca -PathType Leaf) {
                $FinalHca
            }
            else {
                ""
            }) `
            -Wav $(if (Test-Path $FinalWav -PathType Leaf) {
                $FinalWav
            }
            else {
                ""
            }) `
            -Mp4 ""


        Add-FailureLog `
            -RelativeSource $RelativePath `
            -EmbeddedFileName $EmbeddedFileName `
            -Stage "File processing" `
            -Message $Message
    }
    finally {

        # Temp extraction data can always be removed.
        # Working files are kept separately for failed conversions.

        if (Test-Path $WorkRoot) {

            Remove-Item `
                $WorkRoot `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}


# ============================================================
# Summary
# ============================================================

Write-Host ""
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Finished" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Successfully processed    : $SuccessCount" -ForegroundColor Green
Write-Host "Duplicate videos skipped  : $DuplicateContentCount" -ForegroundColor Yellow
Write-Host "Video decode warnings     : $VideoWarningCount" -ForegroundColor Yellow
Write-Host "Video/file failures       : $FailureCount"

Write-Host ""
Write-Host "Total source files        : $TotalFiles"
Write-Host "CRID containers found     : $CridCount"
Write-Host "Non-video CRID skipped    : $NotVideoCount"
Write-Host "Non-CRID files ignored    : $NonCridCount"
Write-Host "Previously processed      : $SkipCount"

Write-Host ""
Write-Host "Single-stream videos      : $SingleStreamCount"
Write-Host "Multi-stream videos       : $MultiStreamCount"

Write-Host ""
Write-Host "Audio tracks decoded      : $AudioCount"
Write-Host "Videos with no HCA        : $NoAudioCount"
Write-Host "Audio decode failures     : $AudioFailCount"
Write-Host "Filename collisions       : $DuplicateNameCount"

Write-Host ""
Write-Host "Final MP4 folder:"
Write-Host "  $FinalRoot"

Write-Host ""
Write-Host "Working files:"
Write-Host "  $WorkingRoot"
Write-Host "  Successful conversions are cleaned automatically."
Write-Host "  Failed conversions retain working files when available."

Write-Host ""
Write-Host "File mapping log:"
Write-Host "  $script:FileMapLog"

Write-Host ""
Write-Host "Main log:"
Write-Host "  $script:CsvLog"

Write-Host ""
Write-Host "Failure log:"
Write-Host "  $script:FailureLog"

Write-Host ""
Write-Host "Skipped log:"
Write-Host "  $script:SkippedLog"

Write-Host ""
Write-Host "Processed list:"
Write-Host "  $ProcessedFile"

Write-Host ""
Write-Host "Created by: Alec Breen | TheBreenis"
Write-Host "GitHub: $RepositoryUrl"

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""