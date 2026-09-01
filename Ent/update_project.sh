#!/bin/bash

# --- Default Variables ---
FILE_PATH=""
ORIGINAL_INPUT=""
JAVA_HOME=""
ANDROID_BUILD_TOOLS=""
NDK=""

# --- Help Menu Function ---
usage() {
    echo "Usage: $0 -f <file_path> [-i <original_input>] [-j <java_home>] [-b <android_build_tools>] [-n <ndk>]"
    echo "  -f : Path to the .nwproj file (Mandatory)"
    echo "  -i : Path to .apk/.aab file (Optional)"
    echo "  -j : Location of Java JDK (Optional)"
    echo "  -b : Path to Android Build Tools (Optional)"
    echo "  -n : Path to Android NDK (Optional)"
    exit 1
}

# --- Parse Command-Line Arguments ---
while getopts "f:i:j:b:n:" opt; do
    case "$opt" in
        f) FILE_PATH="$OPTARG" ;;
        i) ORIGINAL_INPUT="$OPTARG" ;;
        j) JAVA_HOME="$OPTARG" ;;
        b) ANDROID_BUILD_TOOLS="$OPTARG" ;;
        n) NDK="$OPTARG" ;;
        *) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Check if mandatory file path parameter is provided
if [ -z "$FILE_PATH" ]; then
    echo "Error: File path (-f) is required."
    usage
fi

# Check if file actually exists
if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found at '$FILE_PATH'"
    exit 1
fi

UPDATED_COUNT=0

# --- Update <platform> level fields ---
# Even though the field is called "sdk", it actually refers to the NDK path in the .nwproj structure, 
# so we will update it if the NDK parameter is provided.
if [ -n "$NDK" ]; then
    echo "Updating 'sdk' -> $NDK"
    xmlstarlet ed -L -u "/nw/platform/sdk" -v "$NDK" "$FILE_PATH"
    ((UPDATED_COUNT++))
fi

# --- Update <dcp> level fields ---
if [ -n "$ORIGINAL_INPUT" ]; then
    echo "Updating 'originalInput' -> $ORIGINAL_INPUT"
    xmlstarlet ed -L -u "/nw/platform/dcp/originalInput" -v "$ORIGINAL_INPUT" "$FILE_PATH"
    ((UPDATED_COUNT++))
fi

if [ -n "$JAVA_HOME" ]; then
    echo "Updating 'javaHome' -> $JAVA_HOME"
    xmlstarlet ed -L -u "/nw/platform/dcp/javaHome" -v "$JAVA_HOME" "$FILE_PATH"
    ((UPDATED_COUNT++))
fi

if [ -n "$ANDROID_BUILD_TOOLS" ]; then
    echo "Updating 'androidBuildTools' -> $ANDROID_BUILD_TOOLS"
    xmlstarlet ed -L -u "/nw/platform/dcp/androidBuildTools" -v "$ANDROID_BUILD_TOOLS" "$FILE_PATH"
    ((UPDATED_COUNT++))
fi

# --- Final Summary ---
if [ "$UPDATED_COUNT" -gt 0 ]; then
    echo "Successfully updated $UPDATED_COUNT field(s) in '$FILE_PATH'."
else
    echo "No optional parameters were provided. File left unchanged."
fi