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
$payloadBytes = 0L
$localPort = 0
$statusLine = ''

function Read-HttpLine {
    param([System.IO.Stream]$Stream)

    $line = [System.Collections.Generic.List[byte]]::new()
    while ($true) {
        $value = $Stream.ReadByte()
        if ($value -lt 0) { throw 'Unexpected end of HTTP response' }
        if ($value -eq 10) {
            if ($line.Count -gt 0 -and $line[$line.Count - 1] -eq 13) {
                $line.RemoveAt($line.Count - 1)
            }
            return [System.Text.Encoding]::ASCII.GetString($line.ToArray())
        }
        if ($line.Count -ge 8192) { throw 'HTTP response line is too long' }
        [void]$line.Add([byte]$value)
    }
}

function Read-HttpExact {
    param(
        [System.IO.Stream]$Stream,
        [long]$Count,
        [byte[]]$Buffer
    )

    $remaining = $Count
    while ($remaining -gt 0) {
        $wanted = [int][Math]::Min([long]$Buffer.Length, $remaining)
        $read = $Stream.Read($Buffer, 0, $wanted)
        if ($read -le 0) { throw 'HTTP response ended before the declared body length' }
        $remaining -= $read
    }
    return $Count
}

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

    $localPort = $socket.LocalEndPoint.Port
    $header = [System.Collections.Generic.List[byte]]::new()
    $headerComplete = $false
    while (-not $headerComplete) {
        $value = $tls.ReadByte()
        if ($value -lt 0) { throw 'No complete HTTP response header' }
        if ($header.Count -ge 16384) { throw 'HTTP response header is too large' }
        [void]$header.Add([byte]$value)
        $count = $header.Count
        if ($count -ge 4 -and
            $header[$count - 4] -eq 13 -and $header[$count - 3] -eq 10 -and
            $header[$count - 2] -eq 13 -and $header[$count - 1] -eq 10) {
            $headerComplete = $true
        }
    }

    $rawBytes = $header.Count
    $headerLines = [System.Text.Encoding]::ASCII.GetString($header.ToArray()) -split "`r`n"
    $statusLine = $headerLines[0]
    if ($statusLine -notmatch '^HTTP/\d(?:\.\d)?\s+200(?:\s|$)') {
        throw "Unexpected HTTP status: $statusLine"
    }

    $headers = @{}
    foreach ($line in $headerLines | Select-Object -Skip 1) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        $separator = $line.IndexOf(':')
        if ($separator -le 0) { throw "Malformed HTTP header: $line" }
        $name = $line.Substring(0, $separator).Trim().ToLowerInvariant()
        $value = $line.Substring($separator + 1).Trim()
        $headers[$name] = $value
    }

    $buffer = [byte[]]::new(32768)
    if ($headers.ContainsKey('content-length')) {
        $declaredBytes = [long]::Parse(
            [string]$headers['content-length'],
            [Globalization.CultureInfo]::InvariantCulture)
        if ($declaredBytes -ne $Bytes) {
            throw "Server declared $declaredBytes body bytes; expected $Bytes"
        }
        $payloadBytes = Read-HttpExact -Stream $tls -Count $declaredBytes -Buffer $buffer
        $rawBytes += $payloadBytes
    } elseif ([string]$headers['transfer-encoding'] -match '(?i)\bchunked\b') {
        $wireBodyBytes = 0L
        while ($true) {
            $chunkLine = Read-HttpLine -Stream $tls
            $wireBodyBytes += [System.Text.Encoding]::ASCII.GetByteCount($chunkLine) + 2
            $sizeText = ($chunkLine -split ';', 2)[0].Trim()
            try { $chunkBytes = [Convert]::ToInt64($sizeText, 16) }
            catch { throw "Invalid HTTP chunk size: $chunkLine" }
            if ($chunkBytes -lt 0) { throw "Invalid HTTP chunk size: $chunkLine" }
            if ($chunkBytes -eq 0) {
                while ($true) {
                    $trailer = Read-HttpLine -Stream $tls
                    $wireBodyBytes += [System.Text.Encoding]::ASCII.GetByteCount($trailer) + 2
                    if ($trailer.Length -eq 0) { break }
                }
                break
            }

            $payloadBytes += Read-HttpExact -Stream $tls -Count $chunkBytes -Buffer $buffer
            $wireBodyBytes += $chunkBytes
            $cr = $tls.ReadByte()
            $lf = $tls.ReadByte()
            if ($cr -ne 13 -or $lf -ne 10) { throw 'Malformed HTTP chunk terminator' }
            $wireBodyBytes += 2
        }
        $rawBytes += $wireBodyBytes
    } else {
        throw 'HTTP response has neither Content-Length nor chunked transfer encoding'
    }

    if ($payloadBytes -ne $Bytes) {
        throw "Received $payloadBytes payload bytes; expected $Bytes"
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
    SourcePort = $localPort
    Destination = $ServerAddress.ToString()
    HttpStatus = $statusLine
    RequestedBytes = $Bytes
    ReceivedHttpBytes = $rawBytes
    PayloadBytes = $payloadBytes
    AdapterRxDelta = $after.ReceivedBytes - $before.ReceivedBytes
    AdapterTxDelta = $after.SentBytes - $before.SentBytes
    Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
    PayloadMbitPerSec = if ($timer.Elapsed.TotalSeconds -gt 0) {
        [Math]::Round($payloadBytes * 8 / $timer.Elapsed.TotalSeconds / 1000000, 2)
    } else { 0 }
}
