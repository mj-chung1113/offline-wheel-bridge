param(
    [Parameter(Mandatory = $true)]
    [string]$RelayUser,

    [Parameter(Mandatory = $true)]
    [string]$RelayHost,

    [Parameter(Mandatory = $true)]
    [string]$ClusterHost,

    [Parameter(Mandatory = $true)]
    [int]$ClusterPort,

    [int]$RemotePort = 44000
)

$ErrorActionPreference = "Stop"

Write-Host "Checking cluster SSH endpoint $ClusterHost`:$ClusterPort ..."
$probe = Test-NetConnection -ComputerName $ClusterHost -Port $ClusterPort -WarningAction SilentlyContinue
if (-not $probe.TcpTestSucceeded) {
    throw "Cannot reach $ClusterHost`:$ClusterPort. Connect the required VPN/network or start the cluster container first."
}

$forward = "127.0.0.1:${RemotePort}:${ClusterHost}:${ClusterPort}"
Write-Host "Opening reverse tunnel on ${RelayHost}:127.0.0.1:$RemotePort"
Write-Host "Keep this window open. Press Ctrl+C to close the tunnel."

$sshArgs = @(
    "-NT",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-R", $forward,
    "${RelayUser}@${RelayHost}"
)

& ssh @sshArgs
if ($LASTEXITCODE -ne 0) {
    throw "ssh tunnel exited with code $LASTEXITCODE"
}
