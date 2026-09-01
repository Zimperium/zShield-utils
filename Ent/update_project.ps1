<#
.SYNOPSIS
    Updates selected fields in a .nwproj XML file.

.DESCRIPTION
    This script processes a .nwproj XML file and updates one or more of the
    following nodes:
      - /nw/platform/sdk
      - /nw/platform/dcp/originalInput
      - /nw/platform/dcp/javaHome
      - /nw/platform/dcp/androidBuildTools

    The script accepts named parameters and validates both mandatory and
    unknown input before attempting to modify the XML file.
#>

function Show-Usage {
    <#
    Display usage information and exit with a non-zero status.
    #>
    Write-Host "Usage: .\update_project.ps1 -FilePath <file_path> [-OriginalInput <original_input>] [-JavaHome <java_home>] [-AndroidBuildTools <android_build_tools>] [-Ndk <ndk>]"
    Write-Host "  -FilePath : Path to the .nwproj file (Mandatory)"
    Write-Host "  -OriginalInput : Path to .apk/.aab file (Optional)"
    Write-Host "  -JavaHome : Location of Java JDK (Optional)"
    Write-Host "  -AndroidBuildTools : Path to Android Build Tools (Optional)"
    Write-Host "  -Ndk : Path to Android NDK (Optional)"
    exit 1
}

# Initialize input variables with default values.
$FilePath = $null
$OriginalInput = $null
$JavaHome = $null
$AndroidBuildTools = $null
$Ndk = $null

# Parse command-line arguments manually so we can detect unknown parameters.
$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i].ToLower()) {
        '-filepath' {
            if ($i + 1 -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Error "Missing value for -FilePath"
                Show-Usage
            }
            $FilePath = $args[$i + 1]
            $i += 2
        }
        '-originalinput' {
            if ($i + 1 -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Error "Missing value for -OriginalInput"
                Show-Usage
            }
            $OriginalInput = $args[$i + 1]
            $i += 2
        }
        '-javahome' {
            if ($i + 1 -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Error "Missing value for -JavaHome"
                Show-Usage
            }
            $JavaHome = $args[$i + 1]
            $i += 2
        }
        '-androidbuildtools' {
            if ($i + 1 -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Error "Missing value for -AndroidBuildTools"
                Show-Usage
            }
            $AndroidBuildTools = $args[$i + 1]
            $i += 2
        }
        '-ndk' {
            if ($i + 1 -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Error "Missing value for -Ndk"
                Show-Usage
            }
            $Ndk = $args[$i + 1]
            $i += 2
        }
        '-help' { Show-Usage }
        '--help' { Show-Usage }
        default {
            Write-Error "Invalid parameter: $($args[$i])"
            Show-Usage
        }
    }
}

# Require the mandatory FilePath parameter.
if ([string]::IsNullOrEmpty($FilePath)) {
    Write-Error "Error: FilePath is required."
    Show-Usage
}

# Verify that the provided file exists before continuing.
if (Test-Path $FilePath) {
    try {
        # Load the XML document from the file.
        [xml]$xmlNode = Get-Content -Path $FilePath -Raw

        $platformNode = $xmlNode.nw.platform
        $dcpNode = $platformNode.dcp

        $updatedCount = 0

        # --- Update platform-level fields ---
        if ($platformNode) {
            if (-not [string]::IsNullOrEmpty($Ndk)) {
                $platformNode.sdk = $Ndk
                $updatedCount++
                Write-Host "Updating 'sdk' -> $Ndk" -ForegroundColor Cyan
            }
        }

        # --- Update dcp-level fields ---
        if ($dcpNode) {
            if (-not [string]::IsNullOrEmpty($OriginalInput)) {
                $dcpNode.originalInput = $OriginalInput
                $updatedCount++
                Write-Host "Updating 'originalInput' -> $OriginalInput" -ForegroundColor Cyan
            }
            if (-not [string]::IsNullOrEmpty($JavaHome)) {
                $dcpNode.javaHome = $JavaHome
                $updatedCount++
                Write-Host "Updating 'javaHome' -> $JavaHome" -ForegroundColor Cyan
            }
            if (-not [string]::IsNullOrEmpty($AndroidBuildTools)) {
                $dcpNode.androidBuildTools = $AndroidBuildTools
                $updatedCount++
                Write-Host "Updating 'androidBuildTools' -> $AndroidBuildTools" -ForegroundColor Cyan
            }
        } else {
            Write-Warning "Could not find the <dcp> element structure inside the XML file."
        }

        # Save the XML only if any updates were made.
        if ($updatedCount -gt 0) {
            $xmlNode.Save($FilePath)
            Write-Host "Successfully updated $updatedCount field(s) in '$FilePath'." -ForegroundColor Green
        } else {
            Write-Host "No parameters were provided. File left unchanged." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "An error occurred while processing the XML: $_"
    }
} else {
    Write-Error "File not found at: $FilePath"
}
