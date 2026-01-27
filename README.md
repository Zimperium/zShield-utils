# zShieldPro-utils

Various utilities to use with zShield Pro

## zshield_protect.sh

A bash script to upload mobile app files (APK, AAB, XCARCHIVE compressed as a ZIP) to zShield Pro for protection, poll until processing is complete, and download the protected artifacts.

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
- `--app-file PATTERN`          : Glob pattern for input files (required, max 5 files, extensions: .apk, .aab, .zip)
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

### Supported File Formats

The script accepts the following file types:

- `.apk` - Android application packages
- `.aab` - Android app bundles
- `.zip` - ZIP files containing a `.xcarchive` (for iOS/macOS apps)

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

By default, the script uses a standard protection configuration. You can customize it by providing a JSON file or inline JSON. For more details, please see the API reference available through the console.

#### Protection settings

| Parameter | Type | Required | Description |
| -- | -- | -- | -- |
| accessToken | String | Yes | This is the token required for Console access. |
| description | String | Yes | This is the description of the uploading app. |
| signatureVerification | boolean | Yes | This determines whether the signature verification checkbox is selected in the user interface, and sets it similarly in the API request. |
| staticDexEncryption | boolean | Yes | This determines whether the static dex encryption checkbox is selected in the user interface, and sets it similarly in the API request. |
| resourceEncryption | boolean | Yes | This determines whether the resource encryption checkbox is selected in the user interface, and sets it similarly in the API request. |
| metadataEncryption | boolean | Yes | This determines whether the metadata encryption checkbox is selected in the user interface, and sets it similarly in the API request. |
| codeObfuscation | boolean | Yes | This determines whether the code obfuscation checkbox is selected in the user interface, and sets it similarly in the API request. |
| runtimeProtection | boolean | Yes | This determines whether the runtime protection checkbox is selected in the user interface, and sets it similarly in the API request. |
| autoScanBuild | boolean | Yes | This determines whether the auto scan build checkbox is selected in the user interface, and sets it similarly in the API request. |

#### Default protection settings

```json
{
  "description": "CI zShield Pro protection",
  "signatureVerification": false,
  "staticDexEncryption": true,
  "resourceEncryption": false,
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
- `PROTECTED_URL`: Signed, short-expiration URL for the protected artifact; can be used to re-download the artifact
- `PROTECTED_FILE`: Local path to the downloaded protected file

Sample output:

```text
BUILD_ID=0b88138f-...-114a71e4e805
PROTECTED_URL=https://s3.amazonaws.com/com.zimperium.usmtddemo.us-east-1.privatebucket/zshield/customer/81b72679-ddd6-4a9f-bcfd-845e71347671/app/57a6ecad-d949-4b2e-aeb0-6e5d6560d132/build/0b88138f-a484-49e0-91f5-114a71e4e805/protected-files/app.aab?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=<...>&X-Amz-SignedHeaders=host&X-Amz-Credential=<...%2F20260123%2Fus-east-1%2Fs3%2Faws4_request>&X-Amz-Expires=60&X-Amz-Signature=<...>
PROTECTED_FILE=app_zshield_protected.aab
```

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
