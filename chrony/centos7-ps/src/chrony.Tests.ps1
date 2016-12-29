$here = $PSScriptRoot
$sut = (Split-Path -Leaf $PSCommandPath) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve
$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath
. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\LinuxUtil.ps1" -Resolve)

$envfile = $here | Split-Path -Parent | Join-Path -ChildPath fixtures/envforcodeexec.json -Resolve
$resutl = . "$here\$sut" -envfile $envfile -action t

$I_AM_IN_TESTING = $True

Describe "code" {
    It "should install chrony" {
        $myenv = New-EnvForExec $envfile
        $result = install-chrony $myenv
        $result | Should Be $True
        $result | Write-HostIfInTesting
        Get-Content -Path "/etc/chrony.conf" | Where-Object {$_ -match "I should be sit at /etc/chrony.conf"} | Should Be $True
        Get-Content -Path "/etc/chrony.conf" | Where-Object {$_ -match "^\s*allow"} | Should Be "allow a1.host.name"
    }
}