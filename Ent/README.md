# README for the zShield Enterprise Utilities

## Project File Update

This directory contains two helper scripts for updating `.nwproj` project files used by the zShield Enterprise tooling with folders specific to the environment where protection is executed:

1. `update_project.sh` - Bash script for POSIX-compatible shells
2. `update_project.ps1` - PowerShell script for Windows and PowerShell 7+ environments

Both scripts update selected XML fields in a `.nwproj` file without requiring a full project rebuild. This is frequently required when running protection in the CI/CD environment where various system paths may differ from developer workstations.

## Purpose

These utilities are designed to keep `.nwproj` metadata in sync with the current build environment by updating:

- `/nw/platform/sdk`
- `/nw/platform/dcp/originalInput`
- `/nw/platform/dcp/javaHome`
- `/nw/platform/dcp/androidBuildTools`

The bash and PowerShell versions expose the same semantics via native shell parameter styles.

## Prerequisites

### Bash script (`update_project.sh`)

- `bash` or `zsh`
- `xmlstarlet`
- POSIX-compatible shell environment

Install `xmlstarlet` on Debian/Ubuntu:

```bash
sudo apt-get update && sudo apt-get install xmlstarlet
```

### PowerShell script (`update_project.ps1`)

- PowerShell 7 or higher
- A host platform that supports PowerShell Core

## Usage

### Bash version

```bash
./update_project.sh -f <file_path> [-i <original_input>] [-j <java_home>] [-b <android_build_tools>] [-n <ndk>]
```

### PowerShell version

```powershell
./update_project.ps1 -FilePath <file_path> [-OriginalInput <original_input>] [-JavaHome <java_home>] [-AndroidBuildTools <android_build_tools>] [-Ndk <ndk>]
```

## Parameters

| Parameter | Bash | PowerShell | Required | Description |
|---|---|---|---|---|
| `.nwproj` path | `-f` | `-FilePath` | Yes | Path to the `.nwproj` XML file to update |
| Original input file | `-i` | `-OriginalInput` | No | Path to the original `.apk` or `.aab` input artifact |
| Java JDK home | `-j` | `-JavaHome` | No | Java JDK installation path |
| Android Build Tools | `-b` | `-AndroidBuildTools` | No | Android SDK build-tools path |
| Android NDK | `-n` | `-Ndk` | No | Android NDK installation path |

### Notes

- The bash script requires `-f <file_path>` as the only mandatory parameter.
- The PowerShell script validates all input parameters manually and reports unknown parameters.
- If no optional values are provided, the script reports that the file was left unchanged.

## Field mapping

The scripts update the following XML nodes inside the `.nwproj` file:

- `sdk` is updated from `-n` / `-Ndk`
- `originalInput` is updated from `-i` / `-OriginalInput`
- `javaHome` is updated from `-j` / `-JavaHome`
- `androidBuildTools` is updated from `-b` / `-AndroidBuildTools`

> Note: The `.nwproj` field named `sdk` is used to store the NDK path in this project structure.

## Examples

### Bash examples

Update the `MyApp.nwproj` file with the NDK path:

```bash
./update_project.sh -f "MyApp.nwproj" -n "$ANDROID_NDK_HOME"
```

Update the original input and Java home fields:

```bash
./update_project.sh -f "MyApp.nwproj" -i "build/MyApp.apk" -j "$JAVA_HOME"
```

Update all supported fields in one invocation:

```bash
./update_project.sh -f "MyApp.nwproj" -i "build/MyApp.aab" -j "$JAVA_HOME" -b "$ANDROID_HOME/build-tools/35.0.0" -n "$ANDROID_NDK_HOME"
```

### PowerShell examples

Update only the NDK path:

```powershell
.\update_project.ps1 -FilePath "MyApp.nwproj" -Ndk "$env:ANDROID_NDK_HOME"
```

Update original input, Java home, and build tools paths:

```powershell
.\update_project.ps1 -FilePath "MyApp.nwproj" -OriginalInput "build\MyApp.apk" -JavaHome "$env:JAVA_HOME" -AndroidBuildTools "$env:ANDROID_HOME\build-tools\35.0.0"
```

Update all fields at once:

```powershell
.\update_project.ps1 -FilePath "MyApp.nwproj" -OriginalInput "build\MyApp.aab" -JavaHome "$env:JAVA_HOME" -AndroidBuildTools "$env:ANDROID_HOME\build-tools\35.0.0" -Ndk "$env:ANDROID_NDK_HOME"
```

## Output

The scripts print status messages to the console for each field updated and provide a final summary:

- `Successfully updated X field(s) in '<file_path>'.`
- `No optional parameters were provided. File left unchanged.`

## Error handling

### Bash script

- Exits with code `1` if the required file path is missing or if the file does not exist.
- Reports invalid options when unknown flags are passed.

### PowerShell script

- Writes an error and shows usage if required parameters are missing.
- Writes an error and exits if unknown parameters are supplied.
- Writes an error if the file does not exist or if XML processing fails.

## Compatibility

- `update_project.sh` is compatible with Bash and Zsh environments on Linux/macOS where `xmlstarlet` is installed.
- `update_project.ps1` is compatible with PowerShell 7+ on Windows, Linux, and macOS.

## Troubleshooting

- Ensure the `.nwproj` file path is correct and the file exists.
- Install `xmlstarlet` for the bash script before running it.
- Use quoted paths when file or directory names contain spaces.
- If the PowerShell version reports invalid XML, verify the `.nwproj` file is well-formed XML.

## Notes for developers

- The bash script updates XML in place using `xmlstarlet -L`.
- The PowerShell script loads XML via `[xml]` and saves changes with `$xmlNode.Save($FilePath)`.
- Both scripts intentionally only update provided values and do not modify other segments of the `.nwproj` file.
