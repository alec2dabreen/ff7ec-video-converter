# Final Fantasy VII: Ever Crisis Video Converter

A PowerShell-based tool for extracting, decrypting, and converting video assets from the Windows/Steam version of **Final Fantasy VII: Ever Crisis**.

Created by **Alec Breen | TheBreenis**

## Overview

Final Fantasy VII: Ever Crisis stores many of its video assets inside the game's Octo resource directory as extensionless hashed files.

This tool automatically scans those resources, identifies CRI USM video containers, extracts their original embedded filenames, decrypts the video and audio streams, and creates standard MP4 files.

The converter is designed specifically around the Windows/Steam release of Final Fantasy VII: Ever Crisis.

## Features

- Recursively scans the FF7EC Octo resource directory
- Detects CRI USM video containers
- Reads the original embedded USM filename
- Uses the embedded filename for the final MP4
- Decrypts FF7EC CRI video assets
- Extracts VP9 video without re-encoding
- Extracts and decrypts HCA audio
- Converts HCA audio to AAC at 256 kbps
- Creates standard MP4 containers
- Supports both video-only and video-with-audio USM files
- Handles single-stream and multi-stream CRI containers
- Detects duplicate videos using embedded filename and source file size
- Skips duplicate assets instead of generating multiple identical MP4 files
- Logs the original Octo hash and resulting MP4 filename
- Treats recoverable VP9 decoding issues as warnings instead of fatal errors
- Removes temporary IVF, HCA, and WAV files after successful conversion
- Retains working files when a conversion fails so they can be investigated
- Supports resuming previous conversion runs

## Default Game Location

The converter scans:

```text
C:\Program Files (x86)\Steam\steamapps\common\FF7EC\octo\v1\3001
```

If Final Fantasy VII: Ever Crisis is installed somewhere else, update the `$SourceRoot` value near the beginning of the PowerShell script.

## Output Location

Converted MP4 files are placed in:

```text
C:\FF7EC-Decrypt\Final
```

For example:

```text
C:\FF7EC-Decrypt\Final\story_ff7_004.mp4
C:\FF7EC-Decrypt\Final\home_020015.mp4
C:\FF7EC-Decrypt\Final\gacha_weapon_3001.mp4
```

## Logs

Logs and tracking files are stored in:

```text
C:\FF7EC-Decrypt
```

The converter creates the following files:

### `ff7ec-processed.txt`

Tracks source assets that have already been successfully processed or identified as duplicates.

This allows future runs to skip files that have already been handled.

### `ff7ec-file-map.csv`

Maps the original hashed Octo filename to the converted MP4 filename.

Example:

```csv
"OriginalHashedFileName","ConvertedMP4Name"
"50e0ccfc6b5c0bdfe3a94de97eba10b3","story_ff7_004.mp4"
"3f0a7db546e09aaa9549811e5a92a2f7","home_020015.mp4"
"ed5b140185545ed086c5ccd619787112","gacha_weapon_3001.mp4"
```

If multiple Octo hashes contain the same duplicate video, each source hash can point to the same resulting MP4.

### `ff7ec-decryption-log.csv`

Contains detailed conversion results including:

- Source path
- Embedded USM filename
- Source file size
- Converted MP4 filename
- Conversion status
- VP9 decode warnings
- Output information

### `ff7ec-failures.csv`

Contains assets that could not be successfully processed.

### `ff7ec-skipped.csv`

Contains CRID resources that were intentionally skipped, including non-video containers and duplicate videos.

## Duplicate Detection

FF7EC may contain multiple Octo resources representing the same video.

The converter considers a video a duplicate when both of the following match:

```text
Embedded USM filename
Source file size
```

For example:

```text
Hash A
story_ff7_004.usm
22339234 bytes

Hash B
story_ff7_004.usm
22339234 bytes
```

Only one MP4 is created:

```text
story_ff7_004.mp4
```

Both hashes are still recorded in the file mapping log.

If two assets have the same embedded filename but different file sizes, they are treated as separate assets.

## Video Handling

CRI video streams are extracted as VP9 video inside an IVF container.

The VP9 video stream is copied directly into the final MP4:

```text
VP9 -> MP4
```

The video is not re-encoded.

This preserves the original video quality and significantly reduces conversion time.

## Recoverable VP9 Errors

Some FF7EC video assets contain isolated VP9 packets that FFmpeg may report as invalid.

In testing, these can result in a brief visual artifact while playback quickly recovers and continues normally.

The converter therefore distinguishes between:

```text
Invalid video stream
```

and:

```text
Recoverable VP9 decode warning
```

A recoverable decoder error does not automatically prevent the video from being converted.

Warnings are recorded in the conversion log.

## Audio Handling

USM files containing audio normally contain CRI HCA audio.

The converter performs:

```text
Encrypted HCA
    ->
Decrypted WAV
    ->
AAC 256 kbps
    ->
MP4
```

The final MP4 therefore contains:

```text
Video: Original VP9
Audio: AAC 256 kbps
```

If a video does not contain an HCA stream, a video-only MP4 is created.

If HCA decoding fails but the video is usable, the converter also creates a video-only MP4 and records the audio failure.

## Temporary Files

During conversion, temporary working files may include:

```text
.ivf
.hca
.wav
```

These are stored under:

```text
C:\FF7EC-Decrypt\Working
```

After a video converts successfully, its working files are automatically removed.

If conversion fails, available working files are retained for troubleshooting.

## Requirements

The converter uses the following tools:

- Windows PowerShell
- Winget
- Python
- FFmpeg
- FFprobe
- CriCodecs
- PyCriCodecs

The script checks for required dependencies when it starts and attempts to install missing supported components automatically.

## Running the Converter

Download:

```text
FF7EC-Video-Converter.ps1
```

Open PowerShell in the directory containing the script.

If PowerShell prevents the script from running, allow scripts for the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Then run:

```powershell
.\FF7EC-Video-Converter.ps1
```

The execution policy change above applies only to the current PowerShell process.

## Resuming a Previous Run

When the converter starts, it asks:

```text
Have you already decrypted files before? (Y/N)
```

Choose `N` for a completely new conversion run.

Choose `Y` to provide an existing:

```text
ff7ec-processed.txt
```

Previously completed files will be skipped.

## Final Directory Structure

A typical completed run looks like:

```text
C:\FF7EC-Decrypt\
│
├── Final\
│   ├── story_ff7_004.mp4
│   ├── home_020015.mp4
│   ├── gacha_weapon_3001.mp4
│   └── ...
│
├── Working\
│
├── ff7ec-processed.txt
├── ff7ec-file-map.csv
├── ff7ec-decryption-log.csv
├── ff7ec-failures.csv
└── ff7ec-skipped.csv
```

The `Working` directory should normally be empty after successful conversions.

## Important Notes

This project is intended for use with locally installed Final Fantasy VII: Ever Crisis game resources.

Game updates may change:

- Resource structures
- File formats
- Encryption behavior
- Directory layouts
- Codec behavior

Future game updates may therefore require changes to the converter.

## Credits

Created by:

**Alec Breen | TheBreenis**

GitHub:

https://github.com/alec2dabreen/ff7ec-video-converter

This project also relies on the work of the developers and contributors behind:

- FFmpeg
- CriCodecs
- PyCriCodecs

## License

This project is released under the MIT License.

See the `LICENSE` file for details.

## Disclaimer

This project is an independent community tool and is not affiliated with, endorsed by, or sponsored by Square Enix, Applibot, or CRI Middleware.

Final Fantasy VII, Final Fantasy VII: Ever Crisis, and related names and assets are trademarks and property of their respective owners.

This repository does not contain game assets.
