# zShield-utils

Various utilities to use with zShield Pro and Enterprise

## zshieldpro_protect.sh

A bash script to upload mobile app files (APK, AAB, XCARCHIVE compressed as a ZIP) to zShield Pro for protection, poll until processing is complete, and download the protected artifacts.

### Prerequisites

- `curl` (for API calls)
- `jq` (for JSON processing)
- `xxd` (for file validation; included in `vim-common` package on Linux)
- bash or zsh environment
- A valid zShield Pro account with API credentials

### Usage

```bash
./zshieldpro_protect.sh [options]
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
- `--certificate-file FILE`     : Path to signing certificate file (optional, DER format)
- `--output-file FILE`          : Output filename or directory for downloaded artifacts (optional)
- `--timeout-minutes N`         : Wait timeout in minutes (default: 60)
- `--poll-interval-seconds N`   : Poll interval in seconds (default: 30)
- `-h, --help`                  : Show help

**Parameter quoting:** It is recommended to enclose `--app-file` and `--output-file` parameters in quotes to prevent shell expansion and handle paths with spaces:
- `--app-file "build/*.apk"` ensures glob patterns are passed literally to the script
- `--output-file "/path/with spaces/dir/"` handles paths containing spaces

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

### Output File Handling

The script handles output files based on the `--output-file` parameter and the number of input files:

#### Single File Processing

- **With `--output-file` as exact filename**: Uses the specified filename directly (no build ID added). **Note:** If the file already exists, it will be overwritten.
- **With `--output-file` as directory**: Creates `{original_basename}_zshieldpro_protected_{build_id}.{original_extension}` in the directory
- **Without `--output-file`**: Creates `{original_basename}_zshieldpro_protected_{build_id}.{original_extension}` in current directory

#### Multiple File Processing

- **`--output-file` must be a directory**: Creates `{original_basename}_zshieldpro_protected_{build_id}.{original_extension}` for each file in the directory
- **Without `--output-file`**: Creates files in current directory with the naming pattern above

The build ID is automatically included in the filename to prevent accidental overwriting of existing protected artifacts. If you want to use a specific filename without the build ID, provide the exact filename with `--output-file`.

#### Sample input and output

```bash
# Single file, custom output name (exact filename, no build ID added)
./zshieldpro_protect.sh --app-file "app.apk" --output-file "my_protected.apk"
# Result: my_protected.apk (will overwrite if exists)

# Single file, directory output (build ID included in filename)
./zshieldpro_protect.sh --app-file "app.apk" --output-file "./protected/"
# Result: ./protected/app_zshieldpro_protected_0b88138f-a484-49e0-91f5-114a71e4e805.apk

# Multiple files, directory output (build ID included for each)
./zshieldpro_protect.sh --app-file "*.apk" --output-file "./protected/"
# Result: ./protected/app1_zshieldpro_protected_0b88138f-....apk, ./protected/app2_zshieldpro_protected_1c99249g-....apk

# Single file, no output specified (build ID included in filename)
./zshieldpro_protect.sh --app-file "app.apk"
# Result: ./app_zshieldpro_protected_0b88138f-a484-49e0-91f5-114a71e4e805.apk

# Multiple files, current directory (default, build ID included for each)
./zshieldpro_protect.sh --app-file "*.apk"
# Result: ./app1_zshieldpro_protected_0b88138f-....apk, ./app2_zshieldpro_protected_1c99249g-....apk
```

### Examples

#### Basic usage with environment variables

```bash
export CONSOLE_URL="https://ziap.zimperium.com"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"

./zshieldpro_protect.sh --app-file "build/*.apk" --team-name "My Team" --group-name "Production"
```

#### Using command-line options

```bash
./zshieldpro_protect.sh \
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
./zshieldpro_protect.sh \
  --console-url "https://ziap.zimperium.com" \
  --client-id "your-client-id" \
  --client-secret "your-client-secret" \
  --app-file "apps/*.apk" \
  --output-file "protected_apps/"
```

### Protection Configuration

By default, the script uses a standard protection configuration. You can customize it by providing a JSON file or inline JSON. For more details, please see the API reference available through the console.

#### Signing Certificate

An optional signing certificate in DER format can be provided using the `--certificate-file` parameter. The certificate will be submitted with each binary matching the input pattern. If the same certificate should not be used for all binaries, ensure that your input pattern matches only one binary at a time.

Example with certificate:
```bash
./zshieldpro_protect.sh \
  --console-url "https://ziap.zimperium.com" \
  --client-id "your-client-id" \
  --client-secret "your-client-secret" \
  --app-file "app.apk" \
  --certificate-file "path/to/cert.der" \
  --output-file "./protected/"
```

**Note:** When processing multiple binaries with a glob pattern, the same certificate file will be submitted for each match. To use different certificates for different binaries, run the script separately for each binary or use specific patterns that match one file at a time.

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

Please note, that since some settings are only available on certain platofrms (iOS, Android, or Hybrid), the default protection settings are conservative in order to be compatible with all platforms. For more information on which features are supported on which platform, please refer to the documentation available through the console. 

```json
{
  "description": "CI zShield Pro protection",
  "signatureVerification": false,
  "staticDexEncryption": false,
  "resourceEncryption": false,
  "metadataEncryption": false,
  "codeObfuscation": false,
  "runtimeProtection": true,
  "autoScanBuild": true
}
```

#### Custom protection via file

```bash
./zshieldpro_protect.sh --protection-json-file "my_protection.json" [other options]
```

#### Custom protection inline

```bash
./zshieldpro_protect.sh --protection-json '{"signatureVerification": true, "codeObfuscation": true}' [other options]
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
PROTECTED_FILE=app_zshieldpro_protected.aab
```

### Error Handling

The script will exit with different codes:

- 0: Success
- 2: Validation or configuration error
- 3: API or processing error

### Compatibility

The script is compatible with both Bash and Zsh shells.

**Note on Alpine Linux and other non-GNU distros:** The script uses bash/zsh specific features (e.g., `[[ ]]` syntax) and GNU tool variants. Alpine Linux ships with busybox and `sh` by default. To use this script on Alpine, you must explicitly install `bash`:
```bash
apk add bash curl jq vim-common
```
The script has not been extensively tested on other non-GNU Linux distributions (e.g., BSD variants). Compatibility issues with `sed` or `stat` variants are possible.

### Troubleshooting

- Ensure `curl` and `jq` are installed
- Verify API credentials and console URL
- Check file patterns match existing files
- For large files, increase `--timeout-minutes` if needed
- The script supports pagination for teams (if many exist)
## zshieldpro_protect.ps1

A PowerShell script providing equivalent functionality to the bash version for uploading mobile app files to zShield Pro for protection, polling until processing is complete, and downloading the protected artifacts.

### Prerequisites

- PowerShell 7 or higher
- A valid zShield Pro account with API credentials

### Usage

```powershell
./zshieldpro_protect.ps1 [options]
```

### Options

- `-ConsoleUrl <URL>`               : zShield console URL (required)
- `-ClientId <ID>`                  : API client ID (required)
- `-ClientSecret <SECRET>`          : API client secret (required)
- `-AppFile <PATTERN>`              : Glob pattern for input files (required, max 5 files, extensions: .apk, .aab, .zip)
- `-TeamName <NAME>`                : Team name (default: "Default")
- `-GroupName <NAME>`               : Group name for zDefend protection (default: "Default Group")
- `-ProtectionJsonFile <FILE>`      : Path to custom protection JSON file (optional)
- `-ProtectionJson <JSON>`          : Inline protection JSON (optional)
- `-CertificateFile <FILE>`         : Path to signing certificate file (optional, DER format)
- `-OutputFile <FILE>`              : Output filename or directory for downloaded artifacts (optional)
- `-TimeoutMinutes <N>`             : Wait timeout in minutes (default: 60)
- `-PollIntervalSeconds <N>`        : Poll interval in seconds (default: 30)
- `-Help`                           : Show help

### Environment Variables

The same environment variables as the bash version are supported:

- `console_url`
- `client_id`
- `client_secret`

### Differences from Bash Version

The PowerShell version has the following differences from the bash version:

#### Parameter Syntax
- Parameters use PowerShell syntax (e.g., `-ConsoleUrl` instead of `--console-url`)
- Parameters do not require quoting for glob patterns; PowerShell handles expansion differently

#### Network Retries
Unlike Bash, which relies on built-in curl features to implement retries, PowerShell script implelements retry logic in code.

- Built-in automatic retry logic with exponential backoff for all HTTP requests
- Retry policy: 3 attempts with a maximum total time of 120 seconds
- Retries are transparent and do not require additional configuration

#### HttpClient for Multipart Requests
- Uses `System.Net.Http.HttpClient` for file uploads instead of curl form submissions
- Provides better control over multipart form data construction and response handling

#### Output Directory Creation
- Automatically creates output directories (including parent directories) if they don't exist using `New-Item -Force`

### Behavior Parity with Bash Version

Refer to the [Bash section](#zshieldpro_protectsh) for details on these features, as they work identically in the PowerShell version:

- **Supported File Formats**: Accepts .apk, .aab, and .zip files
- **Output File Handling**: Same single/multiple file processing logic and naming conventions (see [Output File Handling](#output-file-handling))
- **Protection Configuration**: Supports the same protection JSON configuration options (see [Protection Configuration](#protection-configuration))
- **Signing Certificate**: Optional DER format certificate support works the same way
- **Default Protection Settings**: Uses the same conservative defaults as the bash version
- **Custom Protection**: Supports both file-based and inline JSON protection configurations
- **Output**: Produces the same KEY=VALUE output format for CI/CD integration
- **Error Handling**: Same exit codes (0 for success, 2 for validation errors, 3 for API errors)

### Examples

#### Basic usage with environment variables

```powershell
$env:console_url = "https://ziap.zimperium.com"
$env:client_id = "your-client-id"
$env:client_secret = "your-client-secret"

./zshieldpro_protect.ps1 -AppFile "build/*.apk" -TeamName "My Team" -GroupName "Production"
```

#### Using command-line parameters

```powershell
./zshieldpro_protect.ps1 `
  -ConsoleUrl "https://ziap.zimperium.com" `
  -ClientId "your-client-id" `
  -ClientSecret "your-client-secret" `
  -AppFile "../build/*.aab" `
  -TeamName "Development" `
  -GroupName "Test Group" `
  -OutputFile "./protected/"
```

#### Processing with signing certificate

```powershell
./zshieldpro_protect.ps1 `
  -ConsoleUrl "https://ziap.zimperium.com" `
  -ClientId "your-client-id" `
  -ClientSecret "your-client-secret" `
  -AppFile "app.apk" `
  -CertificateFile "path/to/cert.der" `
  -OutputFile "./protected/"
```
