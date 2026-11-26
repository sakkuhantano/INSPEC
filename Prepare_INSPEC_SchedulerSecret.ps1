param([Parameter(Mandatory=$true)][string]$SecretFile)
$ErrorActionPreference = 'Stop'
$bytes = New-Object byte[] 32
$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$secret = [Convert]::ToBase64String($bytes)
$secure = ConvertTo-SecureString -String $secret -AsPlainText -Force
$encrypted = ConvertFrom-SecureString -SecureString $secure
$directory = Split-Path -Parent $SecretFile
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
[System.IO.File]::WriteAllText($SecretFile, $encrypted)
Write-Output 'Copy this one-time value to live Web.config appSettings INSPECSchedulerHmacSecret:'
Write-Output $secret
Write-Output 'DPAPI file can only be decrypted by the Windows account that generated it.'
Write-Output 'Run as SQL Server Agent service account or configured CmdExec proxy account.'
