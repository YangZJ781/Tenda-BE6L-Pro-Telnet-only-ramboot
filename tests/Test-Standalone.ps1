$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot
$template = [IO.File]::ReadAllText((Join-Path (Split-Path $testRoot -Parent) 'src/Start-BE6L-Ramboot.template.ps1'),[Text.Encoding]::UTF8)
. ([scriptblock]::Create($template))
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$info16 = [pscustomobject]@{ systemCfg = [pscustomobject]@{ softVersion='V16.03.60.16_cn'; productName='BE6LProV1.0' }; deviceVersionList=@() }
$info51 = [pscustomobject]@{ systemCfg = [pscustomobject]@{ softVersion='V16.03.60.51_cn'; productName='' }; deviceVersionList=@([pscustomobject]@{ip='192.168.0.1';nodeType='controller';devModel='BE6LProV1.0'}) }
$info62 = [pscustomobject]@{ systemCfg = [pscustomobject]@{ softVersion='V16.03.60.62_cn'; productName='' }; deviceVersionList=@([pscustomobject]@{ip='192.168.0.1';nodeType='controller';devModel='BE6LProV1.0'}) }
$profile16 = Select-FirmwareProfile $info16 '192.168.0.1'
$profile51 = Select-FirmwareProfile $info51 '192.168.0.1'
$profile62 = Select-FirmwareProfile $info62 '192.168.0.1'
Assert-True ($profile16.Number -eq '16' -and $profile16.Seed -eq '4rKSbd1m_5756') '.16 automatic selection failed'
Assert-True ($profile51.Number -eq '51' -and $profile51.Seed -eq 'TxVqqk5_7730') '.51 automatic selection failed'
Assert-True ($profile62.Number -eq '62' -and $profile62.Seed -eq 'HZJb9q_8765') '.62 automatic selection failed'
$explicit62 = Select-FirmwareProfile $info62 '192.168.0.1' '62'
Assert-True ($explicit62.Number -eq '62') '.62 explicit selection failed'
$rejected = $false
try { $null = Select-FirmwareProfile $info62 '192.168.0.1' '51' } catch { $rejected = $true }
Assert-True $rejected '.62 must reject a .51 override before Telnet'
$rejected = $false
try { $null = Select-FirmwareProfile $info51 '192.168.0.1' '16' } catch { $rejected = $true }
Assert-True $rejected 'Explicit version mismatch must stop before Telnet'
$info51.systemCfg.softVersion = 'V16.03.60.62XD'
$rejected = $false
try { $null = Select-FirmwareProfile $info51 '192.168.0.1' } catch { $rejected = $true }
Assert-True $rejected 'Unknown version must stop before Telnet'
$info51.systemCfg.softVersion = 'V16.03.60.63_cn'
$rejected = $false
try { $null = Select-FirmwareProfile $info51 '192.168.0.1' } catch { $rejected = $true }
Assert-True $rejected 'Unverified .63 must stop before Telnet'
$info51.systemCfg.softVersion = 'V16.03.60.51_cn'
$password = Get-RootPassword '02:00:00:00:15:e0' $profile51.Seed
Assert-True ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($password)) -eq '15TxVqqk5_7730e0') '.51 password differs from the verified device input'
$password16 = Get-RootPassword '02:00:00:00:15:e0' $profile16.Seed
Assert-True ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($password16)) -eq '154rKSbd1m_5756e0') '.16 password differs from the verified device input'
$password62 = Get-RootPassword '02:00:00:00:ab:cd' $profile62.Seed
Assert-True ($password62 -eq 'YWJIWkpiOXFfODc2NWNk') '.62 password differs from the fixed Base64 fixture'
$additional = @(
    @('18','bXoUsD_5885','YWJiWG9Vc0RfNTg4NWNk'),
    @('22','dLFPTO_6096','YWJkTEZQVE9fNjA5NmNk'),
    @('40','b9NwNY_7173','YWJiOU53TllfNzE3M2Nk'),
    @('57','zkiB5A_8383','YWJ6a2lCNUFfODM4M2Nk'),
    @('67','dgQnqW_10379','YWJkZ1FucVdfMTAzNzljZA==')
)
foreach ($fixture in $additional) {
    $number = $fixture[0]
    $info = [pscustomobject]@{ systemCfg=[pscustomobject]@{softVersion=('V16.03.60.'+$number+'_cn');productName=''};deviceVersionList=@([pscustomobject]@{ip='192.168.0.1';nodeType='controller';devModel='BE6LProV1.0'}) }
    $profile = Select-FirmwareProfile $info '192.168.0.1'
    Assert-True ($profile.Number -eq $number -and $profile.Seed -eq $fixture[1]) ('.'+$number+' selection failed')
    Assert-True ((Get-RootPassword '02:00:00:00:ab:cd' $profile.Seed) -eq $fixture[2]) ('.'+$number+' fixed password fixture failed')
    Assert-True ((Select-FirmwareProfile $info '192.168.0.1' $number).Number -eq $number) ('.'+$number+' explicit selection failed')
    $rejected = $false
    try { $null = Select-FirmwareProfile $info '192.168.0.1' '62' } catch { $rejected = $true }
    Assert-True $rejected ('.'+$number+' must reject a .62 override')
}
$logPath = Join-Path $testRoot 'fixtures/stock-probe.txt'
$probe = [IO.File]::ReadAllText($logPath).Replace("`r",'')
Test-RamLayout $probe 25000000
$rejected = $false
try { Test-RamLayout ($probe.Replace('80040000-801fffff : System RAM','80040000-8007ffff : System RAM')) 25000000 } catch { $rejected = $true }
Assert-True $rejected 'Incompatible RAM range must be rejected'
Initialize-Transport
Assert-True ($null -ne ('Be6l.TelnetSession' -as [type])) 'Built-in transport compilation failed'
Write-Host 'PASS: all eight firmware profiles, explicit selection, mismatch/unknown rejection, fixed password fixtures, RAM ranges, transport compilation.'
