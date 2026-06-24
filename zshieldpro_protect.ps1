#!/usr/bin/env pwsh
# zshield_protect.ps1
# Upload files to zShield Pro, wait for protection, and download protected artifacts.
# Supports processing multiple files one by one.
# Usage: see -Help or README in repo.

param(
    [string]$ConsoleUrl,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$AppFile,
    [string]$TeamName = "Default",
    [string]$GroupName = "Default Group",
    [string]$ProtectionJsonFile,
    [string]$ProtectionJson,
    [string]$CertificateFile,
    [string]$OutputFile,
    [int]$TimeoutMinutes = 60,
    [int]$PollIntervalSeconds = 30,
    [switch]$Help
)

# Require PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7 or higher is required. Current version: $($PSVersionTable.PSVersion)"
    exit 2
}

$ErrorActionPreference = 'Stop'

# Script configuration
$SCRIPT_NAME = Split-Path -Leaf $MyInvocation.MyCommand.Definition

# Defaults
$max_files = 5
$network_retry_count = 3
$network_retry_max_time = 120

# Function: Print with timestamp
function Print {
    param([string]$Message)
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Host "$timestamp $Message" -ForegroundColor Gray
}

# Function: Error with timestamp
function Err {
    param([string]$Message)
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Host "$timestamp ERROR: $Message" -ForegroundColor Red
}

# Function: Show help
function Show-Help {
    @"
Usage: $SCRIPT_NAME [options]

Options:
  -ConsoleUrl <URL>               zShield console url (required or env console_url)
  -ClientId <ID>                  API client id (required or env client_id)
  -ClientSecret <SECRET>          API client secret (required or env client_secret)
  -AppFile <PATTERN>              Glob pattern matching input files (required, max $max_files, extensions: .apk, .aab, .zip)
  -TeamName <NAME>                Team name (default: $TeamName)
  -GroupName <NAME>               Group name (default: $GroupName)
  -ProtectionJsonFile <FILE>      Protection JSON file (optional)
  -ProtectionJson <JSON>          Protection JSON inline (optional)
  -CertificateFile <FILE>         Signing certificate file (optional, DER format)
  -OutputFile <FILE>              Output filename or folder for downloaded artifact (optional)
  -TimeoutMinutes <N>             Wait timeout in minutes (default: $TimeoutMinutes)
  -PollIntervalSeconds <N>        Poll interval seconds (default: $PollIntervalSeconds)
  -Help                           Show this help

Environment fallback names: console_url, client_id, client_secret

Example:
  ./$SCRIPT_NAME -ConsoleUrl https://ziap.zimperium.com -ClientId abc -ClientSecret secret `
    -AppFile "./build/*.apk" -TeamName "My Team" -GroupName "My Group" -OutputFile ./protected/

"@ | Write-Host
}

if ($Help) {
    Show-Help
    exit 0
}

# Environment variable fallbacks
if (-not $PSBoundParameters.ContainsKey('ConsoleUrl')) {
    $console_url = $env:console_url -or $env:CONSOLE_URL
}
if (-not $PSBoundParameters.ContainsKey('ClientId')) {
    $client_id = $env:client_id -or $env:CLIENT_ID
}
if (-not $PSBoundParameters.ContainsKey('ClientSecret')) {
    $client_secret = $env:client_secret -or $env:CLIENT_SECRET
}

# Validate required parameters
if (-not $ConsoleUrl -or -not $ClientId -or -not $ClientSecret -or -not $AppFile) {
    Err "Missing required parameter."
    Show-Help
    exit 2
}

# Normalize and validate URL
if ($ConsoleUrl -notmatch '^https?://') {
    Err "console_url must include scheme (https://...). Got: $ConsoleUrl"
    exit 2
}
$base_url = $ConsoleUrl.TrimEnd('/')

Print "Starting zShield protect flow against $base_url"

# Function: Retry wrapper for web requests
# Wrapper to implement retry logic with exponential backoff
function Invoke-WebRequestWithRetry {
    param(
        [string]$Uri,
        [string]$Method = "Get",
        [hashtable]$Headers,
        [object]$Body,
        [string]$ContentType,
        [string]$OutFile,
        [int]$MaxRetries = 3,
        [int]$MaxTime = 120
    )
    
    $retryCount = 0
    $startTime = Get-Date
    
    while ($retryCount -lt $MaxRetries) {
        try {
            $params = @{
                Uri = $Uri
                Method = $Method
                UseBasicParsing = $true
                ErrorAction = 'Stop'
            }
            
            if ($Headers) { $params['Headers'] = $Headers }
            if ($Body) { $params['Body'] = $Body }
            if ($ContentType) { $params['ContentType'] = $ContentType }
            if ($OutFile) { $params['OutFile'] = $OutFile }
            
            $response = Invoke-WebRequest @params
            return $response
        }
        catch {
            $retryCount++
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            
            if ($elapsed -gt $MaxTime) {
                throw "Request failed after ${elapsed} seconds: $_"
            }
            
            if ($retryCount -lt $MaxRetries) {
                $backoff = [Math]::Pow(2, $retryCount - 1)
                Write-Host "Retry $retryCount/$MaxRetries after ${backoff}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $backoff
            }
            else {
                throw $_
            }
        }
    }
}

# Function: Login
# Authenticate with zShield API and obtain access token
function Invoke-Login {
    Print "Authenticating..."
    $body = @{
        clientId = $ClientId
        secret = $ClientSecret
    } | ConvertTo-Json

    try {
        $response = Invoke-WebRequestWithRetry -Uri "$base_url/api/auth/v1/api_keys/login" `
            -Method Post `
            -ContentType 'application/json' `
            -Body $body `
            -MaxRetries $network_retry_count `
            -MaxTime $network_retry_max_time
        
        $resp = $response.Content | ConvertFrom-Json
        $script:token = $resp.accessToken
        
        if (-not $script:token) {
            Err "Login failed: $($response.Content)"
            return $false
        }
        Print "Authentication successful"
        return $true
    }
    catch {
        Err "Authentication request failed: $_"
        return $false
    }
}

# Function: Find matching files
# Find files matching a glob pattern, filter by valid extensions, and validate count
function Find-MatchingFiles {
    param([string]$Pattern)
    
    $files = @()
    $valid_extensions = @('.apk', '.aab', '.zip')
    
    # Expand glob pattern
    try {
        $expanded = @(Resolve-Path -Path $Pattern -ErrorAction SilentlyContinue)
    }
    catch {
        $expanded = @()
    }
    
    if ($expanded.Count -eq 0) {
        Err "No files found matching pattern: $Pattern"
        return $null
    }
    
    if ($expanded.Count -gt $max_files) {
        Err "Pattern matched $($expanded.Count) files, max is $max_files. Narrow the pattern."
        return $null
    }
    
    # Filter by extension
    foreach ($f in $expanded) {
        $ext = [System.IO.Path]::GetExtension($f.Path)
        if ($valid_extensions -contains $ext) {
            $files += $f.Path
        }
    }
    
    if ($files.Count -eq 0) {
        Err "No valid files found. Files must have .apk, .aab, or .zip extensions."
        return $null
    }
    
    return $files
}

# Function: Resolve team ID
# Resolve team name to team ID by querying the teams API with pagination
function Resolve-TeamId {
    param([string]$TeamName)
    
    Print "Resolving team id for '$TeamName'..."
    $all_teams = @()
    $page = 0
    $size = 100
    
    while ($true) {
        try {
            $response = Invoke-WebRequestWithRetry -Uri "$base_url/api/auth/public/v1/teams?page=$page&size=$size" `
                -Method Get `
                -Headers @{ Authorization = "Bearer $script:token" } `
                -MaxRetries $network_retry_count `
                -MaxTime $network_retry_max_time
            
            $resp = $response.Content | ConvertFrom-Json
            $all_teams += $resp.content
            
            $totalElements = $resp.totalElements
            if ($all_teams.Count -ge $totalElements -or $resp.content.Count -lt $size) {
                break
            }
            $page++
        }
        catch {
            Err "Failed to list teams page $page"
            return $null
        }
    }
    
    $team_id = ($all_teams | Where-Object { $_.name -eq $TeamName } | Select-Object -First 1).id
    
    if (-not $team_id) {
        Err "Team '$TeamName' not found."
        return $null
    }
    
    Print "Resolved team '$TeamName' -> $team_id"
    return $team_id
}

# Function: Resolve group ID
# Resolve group name to group ID with team scoping preference
function Resolve-GroupId {
    param([string]$GroupName, [string]$TeamId)
    
    Print "Resolving group id for '$GroupName' (team id: $TeamId)..."
    
    try {
        $response = Invoke-WebRequestWithRetry -Uri "$base_url/api/mtd-policy/public/v1/groups" `
            -Method Get `
            -Headers @{ Authorization = "Bearer $script:token" } `
            -MaxRetries $network_retry_count `
            -MaxTime $network_retry_max_time
        
        $groups = $response.Content | ConvertFrom-Json
    }
    catch {
        Err "Failed to list groups"
        return $null
    }
    
    # Find matches
    $matched_groups = $groups | Where-Object { $_.name -eq $GroupName }
    
    if ($matched_groups.Count -eq 0) {
        Err "Group '$GroupName' not found."
        return $null
    }
    
    # Prefer team-scoped match
    foreach ($m in $matched_groups) {
        if ($m.team -and $m.team.id -eq $TeamId) {
            Print "Resolved team-scoped group '$GroupName' -> $($m.id)"
            return $m.id
        }
    }
    
    # Try global
    $global_matches = $groups | Where-Object { $_.name -eq $GroupName -and -not $_.team }
    
    if ($global_matches.Count -eq 1) {
        Print "Resolved global group '$GroupName' -> $($global_matches[0].id)"
        return $global_matches[0].id
    }
    
    Err "Ambiguous or inaccessible group '$GroupName' for team $TeamId"
    return $null
}

# Function: Build protection request
# Build JSON payload for protection request with team/group injection
function Build-ProtectionRequest {
    param([string]$TeamId, [string]$GroupId)
    
    $json = $null
    
    if ($ProtectionJsonFile) {
        if (-not (Test-Path $ProtectionJsonFile)) {
            Err "Protection JSON file not found: $ProtectionJsonFile"
            return $null
        }
        $json = Get-Content $ProtectionJsonFile -Raw | ConvertFrom-Json
    }
    elseif ($ProtectionJson) {
        $json = $ProtectionJson | ConvertFrom-Json
    }
    else {
        # Default protection settings
        $json = @{
            description = "CI zShield Pro protection"
            signatureVerification = $false
            staticDexEncryption = $false
            resourceEncryption = $false
            metadataEncryption = $false
            codeObfuscation = $false
            runtimeProtection = $true
            autoScanBuild = $true
        }
    }
    
    # Inject teamId and groupId
    $json | Add-Member -MemberType NoteProperty -Name "teamId" -Value $TeamId -Force | Out-Null
    $json | Add-Member -MemberType NoteProperty -Name "groupId" -Value $GroupId -Force | Out-Null
    
    return $json | ConvertTo-Json -Depth 10
}

# Function: Submit protect request
# Submit file and protection config to zShield for processing
function Submit-Protect {
    param([string]$FilePath, [string]$ReqJson, [string]$CertPath)
    
    Print "Submitting protection job for $FilePath"
    
    try {
        # Validate certificate file if provided
        if ($CertPath) {
            if (-not (Test-Path $CertPath)) {
                Err "Certificate file not found: $CertPath"
                return $null
            }
            if (-not $CertPath.EndsWith('.der', [StringComparison]::OrdinalIgnoreCase)) {
                Err "Certificate file must be in DER format (.der extension): $CertPath"
                return $null
            }
        }
        
        # Create multipart form data
        $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
        
        # Add file
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
        $multipartContent.Add($fileContent, "file", [System.IO.Path]::GetFileName($FilePath)) | Out-Null
        
        # Add JSON with application/json content type
        $jsonContent = [System.Net.Http.StringContent]::new($ReqJson, [System.Text.Encoding]::UTF8, "application/json")
        $multipartContent.Add($jsonContent, "appProtectionRequest") | Out-Null
        
        # Add certificate if provided
        if ($CertPath) {
            $certStream = [System.IO.File]::OpenRead($CertPath)
            $certContent = [System.Net.Http.StreamContent]::new($certStream)
            $certContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/x-x509-ca-cert")
            $multipartContent.Add($certContent, "certificateFile", [System.IO.Path]::GetFileName($CertPath)) | Out-Null
        }
        
        # Send request using HttpClient with retry logic
        $httpClient = [System.Net.Http.HttpClient]::new()
        $httpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $script:token)
        $httpClient.Timeout = [TimeSpan]::FromSeconds(120)
        
        $response = $null
        $retryCount = 0
        $startTime = Get-Date
        
        while ($retryCount -lt $network_retry_count) {
            try {
                $response = $httpClient.PostAsync("$base_url/api/zapp/public/v1/builds/protect", $multipartContent).GetAwaiter().GetResult()
                $response.EnsureSuccessStatusCode() | Out-Null
                break
            }
            catch {
                $retryCount++
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                
                if ($elapsed -gt $network_retry_max_time) {
                    throw "Request failed after ${elapsed} seconds: $_"
                }
                
                if ($retryCount -lt $network_retry_count) {
                    $backoff = [Math]::Pow(2, $retryCount - 1)
                    Write-Host "Retry $retryCount/$network_retry_count after ${backoff}s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $backoff
                }
                else {
                    throw $_
                }
            }
        }
        
        # Dispose
        $fileStream.Dispose() | Out-Null
        if ($CertPath) { $certStream.Dispose() | Out-Null }
        $httpClient.Dispose() | Out-Null
        
        $resp = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        $buildId = [string]$resp.buildId
        
        if (-not $buildId) {
            Err "Protect response missing buildId: $resp"
            return $null
        }
        
        Print "Submitted, buildId=$buildId"
        return $buildId
    }
    catch {
        Err "Submit protect request failed: $_"
        return $null
    }
}

# Function: Get build status
# Fetch current status of a build from zShield API
function Get-Build {
    param([string]$BuildId)
    
    try {
        $response = Invoke-WebRequestWithRetry -Uri "$base_url/api/zapp/public/v1/builds/$BuildId" `
            -Method Get `
            -Headers @{ Authorization = "Bearer $script:token" } `
            -MaxRetries $network_retry_count `
            -MaxTime $network_retry_max_time
        
        return $response.Content | ConvertFrom-Json
    }
    catch {
        Err "Failed to get build $BuildId"
        return $null
    }
}

# Function: Wait until ready
# Poll build status until protection is complete or timeout
function Wait-UntilReady {
    param([string]$BuildId)
    
    $start = Get-Date
    $timeout = New-TimeSpan -Minutes $TimeoutMinutes
    
    while ($true) {
        $now = Get-Date
        if (($now - $start) -gt $timeout) {
            Err "Timed out waiting for protected artifact after $TimeoutMinutes minutes. Protected file will be available from the console."
            return $null
        }
        
        $resp = Get-Build $BuildId
        if (-not $resp) {
            return $null
        }
        
        $state = $resp.state
        $protectedUrl = $resp.protectedUrl
        
        $urlStatus = if ($protectedUrl) { 'present' } else { 'pending' }
        Print "state=$state protectedUrl=$urlStatus"
        
        if ($protectedUrl -and $protectedUrl -ne "null") {
            return $resp
        }
        
        if ($state -eq "FAILED" -or $state -eq "ERRORED") {
            Err "zShield build failed: $($resp | ConvertTo-Json)"
            return $null
        }
        
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

# Function: Get protected link
# Get signed download URL for the protected artifact
function Get-ProtectedLink {
    param([string]$BuildId)
    
    try {
        $response = Invoke-WebRequestWithRetry -Uri "$base_url/api/zapp/public/v1/builds/$BuildId/protected" `
            -Method Get `
            -Headers @{ 
                Authorization = "Bearer $script:token"
                Accept = "application/json"
            } `
            -MaxRetries $network_retry_count `
            -MaxTime $network_retry_max_time
        
        $resp = $response.Content | ConvertFrom-Json
        $url = $resp.url
        
        if (-not $url) {
            Err "Unexpected /protected response: $($response.Content)"
            return $null
        }
        
        return $resp
    }
    catch {
        Err "Failed to /protected: $_"
        return $null
    }
}

# Function: Get signed URL
# Download the protected artifact from signed URL and validate it
function Get-SignedUrl {
    param(
        [string]$SignedUrl,
        [string]$InputFile,
        [string]$ServerName,
        [string]$OutputFile
    )
    
    Print "Downloading protected artifact to $OutputFile"
    
    try {
        Invoke-WebRequestWithRetry -Uri $SignedUrl `
            -OutFile $OutputFile `
            -MaxRetries $network_retry_count `
            -MaxTime $network_retry_max_time
    }
    catch {
        Err "Signed URL download failed: $_"
        return $null
    }
    
    # Validate downloaded file
    $fileInfo = Get-Item $OutputFile
    $size = $fileInfo.Length
    Print "Download complete: $OutputFile ($size bytes)"
    
    # Check magic PK (zip header)
    $bytes = [System.IO.File]::ReadAllBytes($OutputFile)
    $magic = "{0:x2}{1:x2}" -f $bytes[0], $bytes[1]
    
    if ($magic -ne "504b") {
        Err "Downloaded file does not start with PK (zip). magic=$magic"
        return $null
    }
    
    if ($size -lt 10000) {
        Err "Downloaded file is unexpectedly small ($size bytes)"
        return $null
    }
    
    return $OutputFile
}

############################
# Main
############################

# Login
if (-not (Invoke-Login)) {
    exit 3
}

# Find matching files
$files = Find-MatchingFiles $AppFile
if (-not $files) {
    exit 3
}

if ($files -isnot [array]) {
    $files = @($files)
}

Print "Matched input files: $($files -join ', ')"

# Determine output handling
$use_directory = $false
$exact_filename_provided = $false
if ($OutputFile) {
    if ((Test-Path $OutputFile -PathType Container) -or $OutputFile.EndsWith('/')) {
        $output_dir = $OutputFile.TrimEnd('/')
        $use_directory = $true
    }
    else {
        if ($files.Count -gt 1) {
            Err "--OutputFile must be a directory when processing multiple files"
            exit 2
        }
        $output_file = $OutputFile
        $use_directory = $false
        $exact_filename_provided = $true
    }
}
else {
    if ($files.Count -eq 1) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($files[0])
        $ext = [System.IO.Path]::GetExtension($files[0]).TrimStart('.')
        $output_file = "${baseName}_zshield_protected.${ext}"
        $use_directory = $false
    }
    else {
        $output_dir = "."
        $use_directory = $true
    }
}

# Resolve team ID
$team_id = Resolve-TeamId $TeamName
if (-not $team_id) {
    exit 3
}
Print "Team id: $team_id"

# Resolve group ID
$group_id = Resolve-GroupId $GroupName $team_id
if (-not $group_id) {
    exit 3
}
Print "Group id: $group_id"

# Build protection request
$protection_json = Build-ProtectionRequest $team_id $group_id
if (-not $protection_json) {
    exit 3
}

# Process each file
foreach ($file_path in $files) {
    Print "Processing file: $file_path"
    
    if ($use_directory) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file_path)
        $ext = [System.IO.Path]::GetExtension($file_path).TrimStart('.')
        $output_file = Join-Path $output_dir "${baseName}_zshield_protected.${ext}"
    }
    
    # Create output directory if needed
    $output_dir_path = Split-Path -Path $output_file -Parent
    if (-not (Test-Path $output_dir_path)) {
        New-Item -ItemType Directory -Path $output_dir_path -Force | Out-Null
    }
    
    # Submit protection job
    $build_id = Submit-Protect $file_path $protection_json $CertificateFile
    if (-not $build_id) {
        exit 3
    }
    Print "Build id: $build_id"
    
    # Update output filename to include build ID, unless exact filename was provided
    if ($exact_filename_provided -ne $true) {
        $output_dir_part = Split-Path -Path $output_file -Parent
        $output_name = Split-Path -Path $output_file -Leaf
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($output_name)
        $ext = [System.IO.Path]::GetExtension($output_name).TrimStart('.')
        $output_file = Join-Path $output_dir_part "${baseName}_${build_id}.${ext}"
    }
    
    # Poll until ready
    $poll_resp = Wait-UntilReady $build_id
    if (-not $poll_resp) {
        exit 3
    }
    Print "Build ready"
    
    # Get protected link
    $protected_resp = Get-ProtectedLink $build_id
    if (-not $protected_resp) {
        exit 3
    }
    
    $protected_url = $protected_resp.url
    $protected_name = $protected_resp.name
    
    Print "Protected artifact name: $($protected_name -or '<unknown>')"
    Print "Protected artifact signed URL: $($protected_url.Substring(0, [Math]::Min(80, $protected_url.Length)))..."
    
    # Download protected artifact
    $downloaded_path = Get-SignedUrl $protected_url $file_path $protected_name $output_file
    if (-not $downloaded_path) {
        exit 3
    }
    
    Print "Finished processing $file_path. Protected file: $downloaded_path"
    
    # Output KEY=VALUE lines for CI to capture
    Write-Host "BUILD_ID=$build_id"
    Write-Host "PROTECTED_URL=$protected_url"
    Write-Host "PROTECTED_FILE=$downloaded_path"
}

exit 0
