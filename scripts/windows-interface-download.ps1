param(
    [Parameter(Mandatory = $true)][string]$InterfaceAlias,
    [Parameter(Mandatory = $true)][ipaddress]$SourceAddress,
    [Parameter(Mandatory = $true)][ipaddress]$ServerAddress,
    [ValidateRange(1, 10000000)][int]$Bytes = 1000000
)

# A bounded HTTPS forwarding probe for multi-homed Windows hosts.
# IP_UNICAST_IF pins only this socket to the chosen adapter. This script
# does not change the Windows default route or any adapter configuration.
$ErrorActionPreference = 'Stop'
$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
if ($adapter.Status -ne 'Up') { throw "Adapter is not up: $InterfaceAlias" }
$assigned = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -eq $SourceAddress.ToString() }
if (-not $assigned) { throw "Source address is not assigned to $InterfaceAlias" }

$before = Get-NetAdapterStatistics -Name $InterfaceAlias
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$socket = [System.Net.Sockets.Socket]::new(
    [System.Net.Sockets.AddressFamily]::InterNetwork,
    [System.Net.Sockets.SocketType]::Stream,
    [System.Net.Sockets.ProtocolType]::Tcp)
$tls = $null
$rawBytes = 0L
$statusLine = ''

try {
    # Windows IP_UNICAST_IF = 31; the interface index is in network order.
    $indexBytes = [System.BitConverter]::GetBytes(
        [System.Net.IPAddress]::HostToNetworkOrder([int]$adapter.ifIndex))
    $socket.SetSocketOption(
        [System.Net.Sockets.SocketOptionLevel]::IP,
        [System.Net.Sockets.SocketOptionName]31,
        $indexBytes)
    $socket.Bind([System.Net.IPEndPoint]::new($SourceAddress, 0))
    $socket.ReceiveTimeout = 30000
    $socket.SendTimeout = 30000
    $socket.Connect([System.Net.IPEndPoint]::new($ServerAddress, 443))

    $stream = [System.Net.Sockets.NetworkStream]::new($socket, $true)
    $tls = [System.Net.Security.SslStream]::new($stream, $false)
    $tls.ReadTimeout = 30000
    $tls.WriteTimeout = 30000
    $tls.AuthenticateAsClient('speed.cloudflare.com')

    $request = "GET /__down?bytes=$Bytes HTTP/1.1`r`nHost: speed.cloudflare.com`r`nAccept-Encoding: identity`r`nConnection: close`r`n`r`n"
    $payload = [System.Text.Encoding]::ASCII.GetBytes($request)
    $tls.Write($payload, 0, $payload.Length)
    $tls.Flush()

    $buffer = [byte[]]::new(32768)
    $first = $tls.Read($buffer, 0, $buffer.Length)
    if ($first -le 0) { throw 'No HTTP response' }
    $rawBytes += $first
    $firstText = [System.Text.Encoding]::ASCII.GetString($buffer, 0, [Math]::Min($first, 256))
    $statusLine = ($firstText -split "`r`n", 2)[0]
    while (($count = $tls.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $rawBytes += $count
    }
} finally {
    if ($tls) { $tls.Dispose() } else { $socket.Dispose() }
    $timer.Stop()
}

$after = Get-NetAdapterStatistics -Name $InterfaceAlias
[pscustomobject]@{
    Interface = $InterfaceAlias
    InterfaceIndex = $adapter.ifIndex
    Source = $SourceAddress.ToString()
    Destination = $ServerAddress.ToString()
    HttpStatus = $statusLine
    RequestedBytes = $Bytes
    ReceivedHttpBytes = $rawBytes
    AdapterRxDelta = $after.ReceivedBytes - $before.ReceivedBytes
    AdapterTxDelta = $after.SentBytes - $before.SentBytes
    Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
}
