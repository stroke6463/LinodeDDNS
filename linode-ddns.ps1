# Path to config file (adjust if needed)
$configPath = "C:\DDNS\linode-ddns-config.json"

# Load config
if (-not (Test-Path $configPath)) {
    Throw "Config file not found at $configPath"
}
$config = Get-Content $configPath | ConvertFrom-Json

# Extract parameters
$apiToken   = $config.ApiToken
$domainName = $config.DomainName
$recordName = $config.RecordName
$ttl        = $config.Ttl
$outLog     = $config.OutputLog

function Get-PublicIP {
    (Invoke-RestMethod -Uri 'https://api.ipify.org?format=text').Trim()
}

function Get-DomainId {
    Invoke-RestMethod -Method Get `
      -Uri "https://api.linode.com/v4/domains?label=$domainName" `
      -Headers @{ Authorization = "Bearer $apiToken" } |
      Select-Object -Expand data |
      Where-Object domain -eq $domainName |
      Select-Object -Expand id
}

function Get-Record {
    param($domainId)
    Invoke-RestMethod -Method Get `
      -Uri "https://api.linode.com/v4/domains/$domainId/records" `
      -Headers @{ Authorization = "Bearer $apiToken" } |
      Select-Object -Expand data |
      Where-Object { $_.type -eq 'A' -and $_.name -eq $recordName }
}

function Update-Record {
    param($domainId, $record)
    $body = @{ type='A'; name=$recordName; target=$targetIP; ttl_sec=$ttl } | ConvertTo-Json
    Invoke-RestMethod -Method Put `
      -Uri "https://api.linode.com/v4/domains/$domainId/records/$($record.id)" `
      -Headers @{ Authorization = "Bearer $apiToken"; 'Content-Type' = 'application/json' } `
      -Body $body
}

# --- Main workflow ---

Start-Transcript -Path $outLog

$targetIP = Get-PublicIP
Write-Host "Current external IP: $targetIP"

$domainId = Get-DomainId
if (-not $domainId) { Throw "Domain $domainName not found or unreachable." }

$record = Get-Record -domainId $domainId
if (-not $record) { Throw "A record '$recordName.$domainName' was not found in domain." }

if ($record.target -ne $targetIP) {
    Write-Host "IP has changed from $($record.target) => $targetIP. Updating..." 
    Update-Record -domainId $domainId -record $record
    Write-Host "Done." 
} else {
    Write-Host "No change - record is already up to date."
}

Stop-Transcript
