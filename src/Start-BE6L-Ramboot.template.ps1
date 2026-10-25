<#
BE6L Pro: stock .16/.18/.22/.40/.51/.57/.62/.67 -> XWRT initramfs through Ethernet.
Single file, Windows PowerShell 5.1 or PowerShell 7. No Python/OpenSSL/TTL.
Default: detect the stock version before choosing the Telnet password.
Wireless is disabled in the embedded RAM device tree. No flash writes.
#>
[CmdletBinding()]
param(
    [string]$RouterIP = '192.168.0.1',
    [ValidateSet('Auto','16','18','22','40','51','57','62','67')][string]$Firmware = 'Auto',
    [string]$NewRouterIP = '192.168.15.1',
    [switch]$CheckFiles,
    [switch]$CheckOnly,
    [switch]$LoadOnly
)
$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Remote = '/tmp/cdx-ramboot'

function Write-Status([string]$Message) {
    Write-Host $Message
    if ($script:LogFile) {
        [IO.File]::AppendAllText($script:LogFile, $Message + "`n", $script:Utf8)
    }
}
function Save-Json($Value, [string]$Path) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), $script:Utf8)
}
function Get-ByteHash([byte[]]$Bytes, [string]$Algorithm = 'SHA256') {
    $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try { return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
function Read-EmbeddedFiles {
    Add-Type -AssemblyName System.IO.Compression
    $zipBytes = [Convert]::FromBase64String($script:EmbeddedZip)
    if ((Get-ByteHash $zipBytes) -ne $script:EmbeddedZipSHA256) { throw '内嵌数据包校验失败，尚未访问路由器。' }
    $memory = [IO.MemoryStream]::new($zipBytes, $false)
    $archive = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $manifestEntry = $archive.GetEntry('manifest.json')
        $reader = [IO.StreamReader]::new($manifestEntry.Open(), [Text.Encoding]::UTF8)
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        $files = @{}
        foreach ($item in $manifest.files) {
            $entry = $archive.GetEntry($item.local)
            if (-not $entry) { throw ('缺少内嵌文件：' + $item.local) }
            $source = $entry.Open()
            $target = [IO.MemoryStream]::new()
            try { $source.CopyTo($target); $bytes = $target.ToArray() }
            finally { $source.Dispose(); $target.Dispose() }
            if ($bytes.Length -ne $item.size -or (Get-ByteHash $bytes) -ne $item.sha256) {
                throw ('内嵌文件校验失败：' + $item.local)
            }
            $files[$item.local] = $bytes
        }
        return [pscustomobject]@{ Manifest = $manifest; Files = $files }
    } finally { $archive.Dispose(); $memory.Dispose() }
}
function Invoke-Http($Session, [string]$Path, [string]$Body = $null, [int]$Timeout = 8000) {
    $request = [Net.HttpWebRequest]::Create($Session.Base + $Path)
    $request.Proxy = $null
    $request.CookieContainer = $Session.Cookies
    $request.Timeout = $Timeout
    $request.ReadWriteTimeout = $Timeout
    $request.UserAgent = 'Mozilla/5.0 BE6L-RAM-Boot'
    $request.Referer = $Session.Base + '/login.html'
    $request.Headers['Origin'] = $Session.Base
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.Method = 'POST'
        $request.ContentType = 'application/json'
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        $upload = $request.GetRequestStream()
        try { $upload.Write($bytes,0,$bytes.Length) } finally { $upload.Dispose() }
    }
    $response = $request.GetResponse()
    try {
        $reader = [IO.StreamReader]::new($response.GetResponseStream(),[Text.Encoding]::UTF8)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
}
function Open-VendorSession([string]$Address, [string]$Password) {
    $session = [pscustomobject]@{ Base = 'http://' + $Address; Cookies = [Net.CookieContainer]::new(); Token = ''; Key = $null }
    $null = Invoke-Http $session '/login.html'
    $hash = (Get-ByteHash ([Text.Encoding]::UTF8.GetBytes($Password)) 'MD5').ToUpperInvariant()
    $body = @{ userName = 'admin'; password = $hash } | ConvertTo-Json -Compress
    $auth = (Invoke-Http $session '/login/Auth' $body) | ConvertFrom-Json
    if (-not $auth.stok -or -not $auth.sign) { throw '原厂网页登录失败，请检查管理密码。' }
    $session.Token = [string]$auth.stok
    $session.Key = [Text.Encoding]::ASCII.GetBytes([string]$auth.sign)
    return $session
}
function Get-VendorInfo($Session) {
    $reply = (Invoke-Http $Session ('/;stok=' + $Session.Token + '/goform/getModules?modules=systemCfg,deviceVersionList')) | ConvertFrom-Json
    if (-not $reply.data) { return $reply }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $Session.Key
        $aes.IV = [Text.Encoding]::ASCII.GetBytes('EU5H62G9ICGRNI43')
        $decryptor = $aes.CreateDecryptor()
        try {
            $cipher = [Convert]::FromBase64String([string]$reply.data)
            $plain = $decryptor.TransformFinalBlock($cipher,0,$cipher.Length)
            return ([Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json)
        } finally { $decryptor.Dispose() }
    } finally { $aes.Dispose() }
}
function Select-FirmwareProfile($Info, [string]$Address, [string]$Expected = 'Auto') {
    $version = [string]$Info.systemCfg.softVersion
    $model = [string]$Info.systemCfg.productName
    if (-not $model) {
        $node = @($Info.deviceVersionList | Where-Object { $_.ip -eq $Address -and $_.nodeType -eq 'controller' })
        if ($node.Count -eq 1) { $model = [string]$node[0].devModel }
    }
    if ($model -ne 'BE6LProV1.0') { throw ('设备型号不符：' + $model + '；尚未尝试 Telnet 登录。') }
    if ($version -notmatch '^V16\.03\.60\.(16|18|22|40|51|57|62|67)(?:_|$)') { throw ('尚未支持此固件：' + $version + '；尚未尝试 Telnet 登录。') }
    $number = $Matches[1]
    if ($Expected -ne 'Auto' -and $Expected -ne $number) {
        throw ('版本不符：当前 ' + $version + '，指定了 .' + $Expected + '；尚未尝试 Telnet 登录。')
    }
    $seeds = @{ '16' = '4rKSbd1m_5756'; '18' = 'bXoUsD_5885'; '22' = 'dLFPTO_6096'; '40' = 'b9NwNY_7173'; '51' = 'TxVqqk5_7730'; '57' = 'zkiB5A_8383'; '62' = 'HZJb9q_8765'; '67' = 'dgQnqW_10379' }
    $seed = $seeds[$number]
    return [pscustomobject]@{ Version = $version; Number = $number; Model = $model; Seed = $seed }
}
function Get-RouterMac([string]$Address) {
    $table = & arp.exe -a $Address 2>$null
    $pattern = '^\s*' + [regex]::Escape($Address) + '\s+((?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2})\s+'
    foreach ($line in $table) {
        if ($line -match $pattern) { return $Matches[1].Replace('-',':').ToLowerInvariant() }
    }
    throw '未能从网卡 ARP 表读取路由器 MAC；请确认电脑通过网线与路由器在同一网段。'
}
function Get-RootPassword([string]$Mac, [string]$Seed) {
    if ($Mac -notmatch '^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$') { throw 'MAC 格式不正确。' }
    $parts = $Mac.Split(':')
    return [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($parts[4] + $Seed + $parts[5]))
}
function Initialize-Transport {
    if ('Be6l.TelnetSession' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Threading;
namespace Be6l {
 public sealed class CommandResult { public string Output; public int ExitCode; }
 public sealed class TelnetSession : IDisposable {
  private TcpClient client; private NetworkStream stream; private int state; private int optionCommand;
  public TelnetSession(string ip,int port,int timeout) {
   client=new TcpClient(); var pending=client.BeginConnect(ip,port,null,null);
   try { if(!pending.AsyncWaitHandle.WaitOne(timeout)) throw new TimeoutException("Telnet connection timeout"); client.EndConnect(pending); }
   catch { client.Close(); throw; } finally { pending.AsyncWaitHandle.Close(); }
   stream=client.GetStream(); stream.WriteTimeout=3000;
  }
  public void WriteLine(string value) { var b=Encoding.UTF8.GetBytes(value+"\n"); stream.Write(b,0,b.Length); }
  private void Decode(byte[] raw,int count,MemoryStream text) {
   for(int i=0;i<count;i++) { byte b=raw[i];
    if(state==0) { if(b==255)state=1;else text.WriteByte(b); }
    else if(state==1) {
     if(b==255){text.WriteByte(b);state=0;}
     else if(b>=251&&b<=254){optionCommand=b;state=2;}
     else if(b==250)state=3;else state=0;
    } else if(state==2) {
     if(optionCommand==251||optionCommand==253) {
      byte reply=optionCommand==253?(byte)252:((b==1||b==3)?(byte)253:(byte)254);
      var response=new byte[]{255,reply,b};stream.Write(response,0,3);
     } state=0;
    } else if(state==3) {if(b==255)state=4;}
    else if(state==4) {state=b==240?0:3;}
   }
  }
  public string ReadUntil(string pattern,int timeout) {
   var watch=Stopwatch.StartNew();var buffer=new byte[4096];
   using(var text=new MemoryStream()) {
    while(watch.ElapsedMilliseconds<timeout) {
     if(stream.DataAvailable) {
      int count=stream.Read(buffer,0,buffer.Length);if(count==0)throw new IOException("Telnet closed");
      Decode(buffer,count,text);var output=Encoding.UTF8.GetString(text.ToArray()).Replace("\r","");
      if(Regex.IsMatch(output,pattern,RegexOptions.Multiline|RegexOptions.IgnoreCase))return output;
     } else {
      if(client.Client.Poll(0,SelectMode.SelectRead)&&client.Client.Available==0)throw new IOException("Telnet closed");
      Thread.Sleep(10);
     }
    }
    throw new TimeoutException("Timed out waiting for Telnet response");
   }
  }
  public CommandResult Command(string command,int timeout) {
   string marker="CDX_"+Guid.NewGuid().ToString("N");
   WriteLine(command+"; printf '\\n"+marker+":%s\\n' \"$?\"");
   string output=ReadUntil("^"+marker+":([0-9]+)$",timeout);
   var match=Regex.Match(output,"^"+marker+":([0-9]+)$",RegexOptions.Multiline);
   return new CommandResult{Output=output,ExitCode=int.Parse(match.Groups[1].Value)};
  }
  public void Dispose(){if(stream!=null)stream.Dispose();if(client!=null)client.Close();}
 }
 public static class Tftp {
  private static int U16(byte[] b,int offset){return(b[offset]<<8)|b[offset+1];}
  private static byte[] Exchange(UdpClient socket,ref IPEndPoint peer,byte[] packet,int expected,bool initial) {
   for(int attempt=0;attempt<10;attempt++) {
    socket.Send(packet,packet.Length,peer);var watch=Stopwatch.StartNew();
    while(watch.ElapsedMilliseconds<1000) {
     socket.Client.ReceiveTimeout=Math.Max(1,1000-(int)watch.ElapsedMilliseconds);
     IPEndPoint source=new IPEndPoint(IPAddress.Any,0);byte[] answer;
     try {answer=socket.Receive(ref source);}catch(SocketException e){if(e.SocketErrorCode==SocketError.TimedOut)break;throw;}
     if(!source.Address.Equals(peer.Address)||(!initial&&source.Port!=peer.Port)||answer.Length<2)continue;
     int opcode=U16(answer,0);
     if(opcode==5)throw new IOException("TFTP: "+Encoding.ASCII.GetString(answer,4,Math.Max(0,answer.Length-4)).TrimEnd('\0'));
     if(initial&&opcode==6){peer=source;return answer;}
     if(opcode==4&&answer.Length>=4&&U16(answer,2)==expected){peer=source;return answer;}
    }
   }throw new TimeoutException("TFTP ACK timeout, block "+expected);
  }
  public static void Upload(string ip,int port,string name,byte[] data) {
   using(var socket=new UdpClient(AddressFamily.InterNetwork)) {
    IPEndPoint peer=new IPEndPoint(IPAddress.Parse(ip),port);
    byte[] fields=Encoding.ASCII.GetBytes(name+"\0octet\0blksize\0"+"1468\0tsize\0"+data.Length+"\0");
    byte[] request=new byte[fields.Length+2];request[1]=2;Buffer.BlockCopy(fields,0,request,2,fields.Length);
    byte[] answer=Exchange(socket,ref peer,request,0,true);int size=512;
    if(U16(answer,0)==6) {
     string[] opts=Encoding.ASCII.GetString(answer,2,answer.Length-2).TrimEnd('\0').Split('\0');
     for(int i=0;i+1<opts.Length;i+=2)if(opts[i].Equals("blksize",StringComparison.OrdinalIgnoreCase))size=int.Parse(opts[i+1]);
     if(size<8||size>1468)throw new IOException("Invalid TFTP block size");
    }
    int offset=0,block=1,lastProgress=0;
    while(true) {
     int count=Math.Min(size,data.Length-offset);byte[] packet=new byte[count+4];packet[1]=3;packet[2]=(byte)(block>>8);packet[3]=(byte)block;
     Buffer.BlockCopy(data,offset,packet,4,count);Exchange(socket,ref peer,packet,block,false);
     offset+=count;block=(block+1)&65535;
     if(offset-lastProgress>=4*1024*1024){lastProgress=offset;Console.WriteLine("  "+name+": "+offset+" / "+data.Length+" bytes");}
     if(count<size)break;
    }
   }
  }
 }
}
'@
}
function Invoke-Remote($Session, [string]$Command, [int]$Timeout = 15000) {
    $result = $Session.Command($Command,$Timeout)
    if ($script:LogFile) {
        [IO.File]::AppendAllText($script:LogFile, '$ ' + $Command + "`n" + $result.Output + "`n", $script:Utf8)
    }
    return $result
}
function Test-RamLayout([string]$Output, [long]$Needed) {
    if ($Output -notmatch '(?m)^armv7l$') { throw '路由器不是已验证的 ARM32 系统。' }
    if ($Output -notmatch '(?m)^CDX_KEXEC_DISABLED=0$') { throw '原厂内核未开放 kexec_load。' }
    $ranges = [regex]::Matches($Output,'(?m)^([0-9a-f]+)-([0-9a-f]+) : System RAM$')
    foreach ($segment in @(@(0x80088000L,0x801fffffL),@(0x80200000L,0x81688fffL),@(0x86ee3000L,0x86ee5fffL))) {
        $valid = $false
        foreach ($range in $ranges) {
            if ([Convert]::ToInt64($range.Groups[1].Value,16) -le $segment[0] -and [Convert]::ToInt64($range.Groups[2].Value,16) -ge $segment[1]) { $valid = $true }
        }
        if (-not $valid) { throw '内存范围与已验证的设备不符；尚未上传启动文件。' }
    }
    $space = [regex]::Match($Output,'(?m)^\S+\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+/tmp$')
    if (-not $space.Success -or [long]$space.Groups[1].Value * 1024 -lt $Needed) {
        throw '/tmp 剩余空间不足或无法读取。请先正常重启原厂系统再试；脚本不会自动删除其他文件。'
    }
}
function Wait-Xwrt([string]$Address, [string]$Directory) {
    $session = [pscustomobject]@{ Base = 'http://' + $Address; Cookies = [Net.CookieContainer]::new() }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lastReport = -20
    while ($watch.Elapsed.TotalSeconds -lt 150) {
        $board = $null
        try {
            $login = @{ jsonrpc='2.0'; id=1; method='call'; params=@(('0'*32),'session','login',@{username='admin';password='admin';timeout=30}) } | ConvertTo-Json -Depth 6 -Compress
            $reply = (Invoke-Http $session '/ubus' $login 2000) | ConvertFrom-Json
            if ($reply.result[0] -ne 0 -or -not $reply.result[1].ubus_rpc_session) { throw 'RPC not ready' }
            $query = @{ jsonrpc='2.0'; id=2; method='call'; params=@($reply.result[1].ubus_rpc_session,'system','board',@{}) } | ConvertTo-Json -Depth 6 -Compress
            $result = (Invoke-Http $session '/ubus' $query 2000) | ConvertFrom-Json
            if ($result.result[0] -ne 0) { throw 'RPC not ready' }
            $board = $result.result[1]
        } catch { }
        if ($board) {
            if ($board.board_name -ne 'tenda,be6l-pro' -or $board.rootfs_type -ne 'initramfs') { throw '网络已恢复，但设备型号或根文件系统不是预期的 initramfs。' }
            Save-Json $board (Join-Path $Directory 'xwrt-board.json')
            return $board
        }
        if ($watch.Elapsed.TotalSeconds - $lastReport -ge 20) {
            Write-Status ('等待 XWRT 启动及电脑更新网段：' + [int]$watch.Elapsed.TotalSeconds + ' 秒')
            $lastReport = $watch.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    }
    throw ('150 秒内未能从网络确认 initramfs。请检查电脑是否获得 192.168.15.x 地址，或访问 http://' + $Address + '/。')
}
function Invoke-Ramboot {
    $telnet = $null
    $serverPid = $null
    $runDirectory = $null
    try {
        $ip = [Net.IPAddress]::Parse($RouterIP)
        if ($ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw '请输入 IPv4 地址。' }
        $payload = Read-EmbeddedFiles
        Write-Status '内嵌的六个启动文件 SHA256 校验通过。'
        if ($CheckFiles) { return 0 }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $runDirectory = Join-Path (Join-Path $PSScriptRoot 'ramboot-logs') $stamp
        $null = New-Item -ItemType Directory -Path $runDirectory -Force
        $script:LogFile = Join-Path $runDirectory 'run.log'
        Write-Status '启动流程只使用网线，不访问 TTL，不刷写固件。'
        $password = $env:BE6L_WEB_PASSWORD
        if (-not $password) {
            $secure = Read-Host '请输入原厂网页管理密码' -AsSecureString
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
        }
        $web = Open-VendorSession $RouterIP $password
        $password = $null
        $info = Get-VendorInfo $web
        $profile = Select-FirmwareProfile $info $RouterIP $Firmware
        Write-Status ('自动识别：' + $profile.Version + '，型号 ' + $profile.Model + '。')
        Save-Json $info (Join-Path $runDirectory 'stock-info.json')
        $enabled = Invoke-Http $web '/goform/telnet'
        if ($enabled -notmatch 'load telnetd success') {
            $enabled = Invoke-Http $web ('/;stok=' + $web.Token + '/goform/telnet')
            if ($enabled -notmatch 'load telnetd success') { throw '原厂接口未确认开启 Telnet。' }
        }
        $mac = Get-RouterMac $RouterIP
        Initialize-Transport
        $telnet = [Be6l.TelnetSession]::new($RouterIP,23,5000)
        $null = $telnet.ReadUntil('login:\s*$',5000)
        $telnet.WriteLine('root')
        $null = $telnet.ReadUntil('Password:\s*$',5000)
        $telnet.WriteLine((Get-RootPassword $mac $profile.Seed))
        $answer = $telnet.ReadUntil('Login incorrect|(?:^|\n)[^\n]*#\s*$',8000)
        if ($answer -match 'Login incorrect') { throw ('已识别 ' + $profile.Version + '，但对应的 Telnet 密码被拒绝；没有上传或装载文件。') }
        $uid = Invoke-Remote $telnet "/bin/busybox grep '^Uid:' /proc/self/status"
        if ($uid.Output -notmatch 'Uid:\s+0\s+0\s+0\s+0') { throw '未能核验 Telnet root 权限。' }
        Write-Status ('Telnet root 登录成功，使用 .' + $profile.Number + ' 对应的密码算法。')
        $probe = Invoke-Remote $telnet 'uname -m; cat /proc/iomem; echo CDX_KEXEC_DISABLED=$(cat /proc/sys/kernel/kexec_load_disabled); df -k /tmp'
        $needed = 1MB
        foreach ($item in $payload.Manifest.files) { $needed += [long]$item.size }
        Test-RamLayout $probe.Output $needed
        Write-Status '内核接口、内存范围和临时盘空间检查通过。'
        if ($CheckOnly) {
            Save-Json @{ result='preflight_passed'; stock_version=$profile.Version; model=$profile.Model; serial_access=$false } (Join-Path $runDirectory 'result.json')
            Write-Status '检查完成，未上传文件，也未切换系统。'
            return 0
        }
        $started = Invoke-Remote $telnet ('mkdir -p '+$script:Remote+'; busybox udpsvd -E '+$RouterIP+' 6969 /bin/busybox tftpd -c '+$script:Remote+' >'+$script:Remote+'/transfer.log 2>&1 </dev/null & echo CDX_TFTP_PID=$!')
        if ($started.Output -notmatch '(?m)^CDX_TFTP_PID=([0-9]+)$') { throw '未能启动内存文件接收器。' }
        $serverPid = [int]$Matches[1]
        if ($serverPid -le 1) { throw '接收器进程号不正确。' }
        $names = @('kexec','libz.so.1','ld-musl-arm.so.1','openwrt-kernel','kexec-split-loader','openwrt-ramonly.dtb')
        for ($i=0; $i -lt $names.Count; $i++) {
            $item = $payload.Manifest.files[$i]
            Write-Status ('上传至路由器内存：' + $names[$i])
            [Be6l.Tftp]::Upload($RouterIP,6969,$names[$i],$payload.Files[$item.local])
        }
        $hashes = Invoke-Remote $telnet ('cd '+$script:Remote+'; busybox md5sum '+($names -join ' '))
        for ($i=0; $i -lt $names.Count; $i++) {
            $pattern = '(?m)^'+$payload.Manifest.files[$i].md5+'\s+'+[regex]::Escape($names[$i])+'$'
            if ($hashes.Output -notmatch $pattern) { throw ('路由器端校验不一致：'+$names[$i]) }
        }
        $null = Invoke-Remote $telnet ('kill '+$serverPid)
        $serverPid = $null
        Write-Status '路由器端六个文件校验通过，开始分段装载。'
        $loaded = Invoke-Remote $telnet ('cd '+$script:Remote+'; chmod 755 kexec ld-musl-arm.so.1 kexec-split-loader; ln -sf ld-musl-arm.so.1 libc.so; ./kexec-split-loader; echo CDX_LOAD_ERRNO=$?; echo CDX_LOADED=$(cat /sys/kernel/kexec_loaded)')
        if ($loaded.Output -notmatch '(?m)^CDX_LOAD_ERRNO=0$' -or $loaded.Output -notmatch '(?m)^CDX_LOADED=1$') { throw '原厂内核未成功接受 RAM 镜像。' }
        if ($LoadOnly) {
            Write-Status 'RAM 镜像装载成功，尚未切换系统。'
            Save-Json @{ result='loaded'; stock_version=$profile.Version; serial_access=$false } (Join-Path $runDirectory 'result.json')
            return 0
        }
        Write-Status '通过 Telnet 切换至 RAM 中的 XWRT initramfs。'
        $returned = $null
        try { $returned = Invoke-Remote $telnet ('cd '+$script:Remote+'; sync; ./ld-musl-arm.so.1 --library-path '+$script:Remote+' ./kexec -d -e') 10000 }
        catch { Write-Status '原 Telnet 会话在系统切换期间结束，开始从网络验证新系统。' }
        if ($null -ne $returned) { throw ('kexec 返回而没有切换系统，返回码：'+$returned.ExitCode) }
        $telnet.Dispose(); $telnet = $null
        $board = Wait-Xwrt $NewRouterIP $runDirectory
        Save-Json @{ result='initramfs_verified'; stock_version=$profile.Version; model=$profile.Model; kernel=$board.kernel; kernel_switch_transport='telnet'; serial_access=$false; wireless_disabled=$true } (Join-Path $runDirectory 'result.json')
        Write-Status ('成功：网络确认 rootfs_type=initramfs，Linux '+$board.kernel+'。')
        Write-Status ('管理页：http://'+$NewRouterIP+'/  账号/密码：admin/admin')
        Write-Status ('无线暂时禁用；重启后回到原厂 '+$profile.Version+'。')
        return 0
    } catch {
        Write-Status ('停止：'+$_.Exception.Message)
        if ($runDirectory) { Save-Json @{ result='stopped'; error=$_.Exception.Message } (Join-Path $runDirectory 'result.json') }
        return 1
    } finally {
        if ($serverPid -and $telnet) { try { $null = Invoke-Remote $telnet ('kill '+$serverPid) } catch { } }
        if ($telnet) { $telnet.Dispose() }
        if ($runDirectory) { Write-Status ('日志：'+$runDirectory) }
    }
}

$script:EmbeddedZipSHA256 = '__PAYLOAD_SHA256__'
$script:EmbeddedZip = @'
__PAYLOAD_BASE64__
'@
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Ramboot) }
