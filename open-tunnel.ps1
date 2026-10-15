param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "bridge.conf"),
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration not found: $ConfigPath`nCopy bridge.conf.example to bridge.conf and edit required values."
}

$config = @{}
foreach ($rawLine in Get-Content -LiteralPath $ConfigPath) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) { throw "Invalid configuration line: $rawLine" }
    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    $config[$key] = $value
}

function Get-RequiredConfig([string]$Name) {
    $value = $config[$Name]
    if ([string]::IsNullOrWhiteSpace($value) -or $value.StartsWith("[")) {
        throw "Set $Name in $ConfigPath before running this script."
    }
    return $value
}

$relayUser = Get-RequiredConfig "RELAY_USER"
$relayHost = Get-RequiredConfig "RELAY_HOST"
$clusterHost = Get-RequiredConfig "CLUSTER_HOST"
$clusterPortText = Get-RequiredConfig "CLUSTER_PORT"
$tunnelHost = Get-RequiredConfig "TUNNEL_HOST"
$tunnelPortText = Get-RequiredConfig "TUNNEL_PORT"

$clusterPort = 0
$tunnelPort = 0
if (-not [int]::TryParse($clusterPortText, [ref]$clusterPort) -or
    $clusterPort -lt 1 -or $clusterPort -gt 65535) {
    throw "Invalid CLUSTER_PORT: $clusterPortText"
}
if (-not [int]::TryParse($tunnelPortText, [ref]$tunnelPort) -or
    $tunnelPort -lt 1 -or $tunnelPort -gt 65535) {
    throw "Invalid TUNNEL_PORT: $tunnelPortText"
}

if ($ValidateOnly) {
    Write-Host "Configuration is valid: $ConfigPath"
    Write-Host "Windows -> cluster: ${clusterHost}:$clusterPort"
    Write-Host "Relay tunnel endpoint: ${tunnelHost}:$tunnelPort"
    exit 0
}

Write-Host "Checking cluster SSH endpoint ${clusterHost}:$clusterPort ..."
$probe = Test-NetConnection -ComputerName $clusterHost -Port $clusterPort -WarningAction SilentlyContinue
if (-not $probe.TcpTestSucceeded) {
    throw "Cannot reach ${clusterHost}:$clusterPort. Check the container and network/VPN."
}

$forward = "${tunnelHost}:${tunnelPort}:${clusterHost}:${clusterPort}"
Write-Host "Opening reverse tunnel through ${relayUser}@${relayHost}"
Write-Host "Relay can reach the cluster at ${tunnelHost}:$tunnelPort"
Write-Host "Keep this window open. Press Ctrl+C to close the tunnel."

& ssh `
    -NT `
    -o ExitOnForwardFailure=yes `
    -o ServerAliveInterval=30 `
    -o ServerAliveCountMax=3 `
    -R $forward `
    "${relayUser}@${relayHost}"

if ($LASTEXITCODE -ne 0) {
    throw "SSH tunnel exited with code $LASTEXITCODE"
}
