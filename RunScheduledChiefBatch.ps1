param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$SecretFile
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Test-Path -LiteralPath $SecretFile)) { throw "Encrypted scheduler secret file not found: $SecretFile" }
$encryptedSecret = (Get-Content -LiteralPath $SecretFile -Raw).Trim()
$secureSecret = ConvertTo-SecureString -String $encryptedSecret
$secretPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
try { $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPtr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPtr) }
if ([string]::IsNullOrWhiteSpace($secret) -or $secret.Length -lt 32) { throw 'Decrypted HMAC secret is invalid.' }
$uri = [Uri]$Url
if ($uri.Scheme -ne 'https' -or $uri.Query -ne '?task=scheduledChiefBatch') { throw 'URL must be HTTPS and end with ?task=scheduledChiefBatch.' }
$epoch = [DateTime]::SpecifyKind([DateTime]'1970-01-01T00:00:00', [DateTimeKind]::Utc)
$timestamp = [string][Math]::Floor(([DateTime]::UtcNow - $epoch).TotalSeconds)
$nonce = [Guid]::NewGuid().ToString('N')
$lf = [string][char]10
$canonical = 'POST' + $lf + $uri.AbsolutePath + '?task=scheduledChiefBatch' + $lf + $timestamp + $lf + $nonce
$keyBytes = [Text.Encoding]::UTF8.GetBytes($secret)
$hmac = New-Object System.Security.Cryptography.HMACSHA256
try {
    $hmac.Key = $keyBytes
    $hash = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))
    $signature = ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}
finally { $hmac.Dispose() }
$headers = @{
    'X-INSPEC-Timestamp' = $timestamp
    'X-INSPEC-Nonce' = $nonce
    'X-INSPEC-Signature' = $signature
}
try {
    $response = Invoke-WebRequest -Uri $Url -Method Post -Headers $headers -Body '{}' -ContentType 'application/json' -UseBasicParsing -TimeoutSec 21600
    $result = $response.Content | ConvertFrom-Json
    if (-not $result.success) { throw "INSPEC rejected the scheduled batch: $($result.message)" }
    $result.result | Format-List | Out-String | Write-Output
    if ($result.result.status -eq 'PARTIAL') {
        Write-Warning 'Scheduler completed with errors. Review INSPEC_SchedulerRunLog and INSPEC_SchedulerSectionLog.'
        exit 1
    }
}
catch { Write-Error $_; exit 1 }
finally { $secret = $null; $secureSecret = $null; $keyBytes = $null }
