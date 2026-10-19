$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot
$template = [IO.File]::ReadAllText((Join-Path (Split-Path $testRoot -Parent) 'src/Start-BE6L-Ramboot.template.ps1'),[Text.Encoding]::UTF8)
. ([scriptblock]::Create($template))
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$info16 = [pscustomobject]@{ systemCfg = [pscustomobject]@{ softVersion='V16.03.60.16_cn'; productName='BE6LProV1.0' }; deviceVersionList=@() }
$info51 = [pscustomobject]@{ systemCfg = [pscustomobject]@{ softVersion='V16.03.60.51_cn'; productName='' }; deviceVersionList=@([pscustomobject]@{ip='192.168.0.1';nodeType='controller';devModel='BE6LProV1.0'}) }
$profile16 = Select-FirmwareProfile $info16 '192.168.0.1'
$profile51 = Select-FirmwareProfile $info51 '192.168.0.1'
Assert-True ($profile16.Number -eq '16' -and $profile16.Seed -eq '4rKSbd1m_5756') '.16 automatic selection failed'
Assert-True ($profile51.Number -eq '51' -and $profile51.Seed -eq 'TxVqqk5_7730') '.51 automatic selection failed'
$rejected = $false
try { $null = Select-FirmwareProfile $info51 '192.168.0.1' '16' } catch { $rejected = $true }
Assert-True $rejected 'Explicit version mismatch must stop before Telnet'
$info51.systemCfg.softVersion = 'V16.03.60.62XD'
$rejected = $false
try { $null = Select-FirmwareProfile $info51 '192.168.0.1' } catch { $rejected = $true }
Assert-True $rejected 'Unknown version must stop before Telnet'
$info51.systemCfg.softVersion = 'V16.03.60.51_cn'
$password = Get-RootPassword '02:00:00:00:15:e0' $profile51.Seed
Assert-True ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($password)) -eq '15TxVqqk5_7730e0') '.51 password differs from the verified device input'
$password16 = Get-RootPassword '02:00:00:00:15:e0' $profile16.Seed
Assert-True ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($password16)) -eq '154rKSbd1m_5756e0') '.16 password differs from the verified device input'
$logPath = Join-Path $testRoot 'fixtures/stock-probe.txt'
$probe = [IO.File]::ReadAllText($logPath).Replace("`r",'')
Test-RamLayout $probe 25000000
$rejected = $false
try { Test-RamLayout ($probe.Replace('80040000-801fffff : System RAM','80040000-8007ffff : System RAM')) 25000000 } catch { $rejected = $true }
Assert-True $rejected 'Incompatible RAM range must be rejected'
Initialize-Transport
Assert-True ($null -ne ('Be6l.TelnetSession' -as [type])) 'Built-in transport compilation failed'
Write-Host 'PASS: automatic .16/.51 selection, mismatch/unknown rejection, .51 password, RAM ranges, transport compilation.'
