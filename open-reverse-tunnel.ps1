param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "bridge.conf"),
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration not found: $ConfigPath`nCopy bridge.conf.example to bridge.conf and edit it first."
}

$config = @{}
foreach ($rawLine in Get-Content -LiteralPath $ConfigPath) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) {
        throw "Invalid configuration line: $rawLine"
    }
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
$tunnelHost = Get-RequiredConfig "TARGET_TUNNEL_HOST"
$remotePortText = Get-RequiredConfig "REVERSE_TUNNEL_PORT"

$clusterPort = 0
$remotePort = 0
if (-not [int]::TryParse($clusterPortText, [ref]$clusterPort) -or
    $clusterPort -lt 1 -or $clusterPort -gt 65535) {
    throw "Invalid CLUSTER_PORT in ${ConfigPath}: $clusterPortText"
}
if (-not [int]::TryParse($remotePortText, [ref]$remotePort) -or
    $remotePort -lt 1 -or $remotePort -gt 65535) {
    throw "Invalid REVERSE_TUNNEL_PORT in ${ConfigPath}: $remotePortText"
}

if ($ValidateOnly) {
    Write-Host "Configuration is valid: $ConfigPath"
    Write-Host "Relay: ${relayUser}@${relayHost}"
    Write-Host "Cluster endpoint: ${clusterHost}:$clusterPort"
    Write-Host "Reverse tunnel endpoint: ${tunnelHost}:$remotePort"
    exit 0
}

Write-Host "Checking cluster SSH endpoint $clusterHost`:$clusterPort ..."
$probe = Test-NetConnection -ComputerName $clusterHost -Port $clusterPort -WarningAction SilentlyContinue
if (-not $probe.TcpTestSucceeded) {
    throw "Cannot reach $clusterHost`:$clusterPort. Connect the required VPN/network or start the cluster container first."
}

$forward = "${tunnelHost}:${remotePort}:${clusterHost}:${clusterPort}"
Write-Host "Opening reverse tunnel on ${relayHost}:${tunnelHost}:$remotePort"
Write-Host "Keep this window open. Press Ctrl+C to close the tunnel."

$sshArgs = @(
    "-NT",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-R", $forward,
    "${relayUser}@${relayHost}"
)

& ssh @sshArgs
if ($LASTEXITCODE -ne 0) {
    throw "ssh tunnel exited with code $LASTEXITCODE"
}
