# zShieldPro-utils

Various utilities to use with zShield Pro

## zshield_protect.sh

A bash script to upload mobile app files (APK, AAB, XCARCHIVE) to zShield Pro for protection, poll until processing is complete, and download the protected artifacts.

### Prerequisites

- `curl` (for API calls)
- `jq` (for JSON processing)
- bash or zsh environment
- A valid zShield Pro account with API credentials

### Usage

```bash
./zshield_protect.sh [options]
```

### Options

- `--console-url URL`           : zShield console URL (required, e.g., `https://ziap.zimperium.com`)
- `--client-id ID`              : API client ID (required)
- `--client-secret SECRET`      : API client secret (required)
- `--app-file PATTERN`          : Glob pattern for input files (required, max 5 files, extensions: .apk, .aab, .xcarchive)
- `--team-name NAME`            : Team name (default: "Default")
- `--group-name NAME`           : Group name for zDefend protection (default: "Default Group")
- `--protection-json-file FILE` : Path to custom protection JSON file (optional)
- `--protection-json JSON`      : Inline protection JSON (optional)
- `--output-file FILE`          : Output filename or directory (optional)
- `--timeout-minutes N`         : Wait timeout in minutes (default: 60)
- `--poll-interval-seconds N`   : Poll interval in seconds (default: 30)
- `-h, --help`                  : Show help

### Environment Variables

You can set these instead of using command-line options:

- `CONSOLE_URL`
- `CLIENT_ID`
- `CLIENT_SECRET`

### Examples

#### Basic usage with environment variables

```bash
export CONSOLE_URL="https://ziap.zimperium.com"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"

./zshield_protect.sh --app-file "build/*.apk" --team-name "My Team" --group-name "Production"
```

#### Using command-line options

```bash
./zshield_protect.sh \
  --console-url "https://ziap.zimperium.com" \
  --client-id "your-client-id" \
  --client-secret "your-client-secret" \
  --app-file "../build/*.aab" \
  --team-name "Development" \
  --group-name "Test Group" \
  --output-file "./protected/"
```

#### Processing multiple files

```bash
./zshield_protect.sh \
  --console-url "https://ziap.zimperium.com" \
  --client-id "your-client-id" \
  --client-secret "your-client-secret" \
  --app-file "apps/*.apk" \
  --output-file "protected_apps/"
```

### Protection Configuration

By default, the script uses a standard protection configuration. You can customize it by providing a JSON file or inline JSON.

#### Default protection settings

```json
{
  "description": "CI zShield Pro protection",
  "signatureVerification": false,
  "staticDexEncryption": true,
  "resourceEncryption": true,
  "metadataEncryption": true,
  "codeObfuscation": false,
  "runtimeProtection": true,
  "autoScanBuild": true
}
```

#### Custom protection via file

```bash
./zshield_protect.sh --protection-json-file "my_protection.json" [other options]
```

#### Custom protection inline

```bash
./zshield_protect.sh --protection-json '{"signatureVerification": true, "codeObfuscation": true}' [other options]
```

### Output

The script outputs key-value pairs that can be captured by CI/CD systems:

- `BUILD_ID`: The zShield build ID
- `PROTECTED_URL`: Signed URL for the protected artifact
- `PROTECTED_FILE`: Local path to the downloaded protected file

### Error Handling

The script will exit with different codes:

- 0: Success
- 2: Validation or configuration error
- 3: API or processing error

### Compatibility

The script is compatible with both Bash and Zsh shells.

### Troubleshooting

- Ensure `curl` and `jq` are installed
- Verify API credentials and console URL
- Check file patterns match existing files
- For large files, increase `--timeout-minutes` if needed
- The script supports pagination for teams (if many exist)
