# $here = Split-Path -Parent $MyInvocation.MyCommand.Path
$here = $PSScriptRoot
$sut = (Split-Path -Leaf $PSCommandPath) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\LinuxUtil.ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$resutl = . "$here\$sut" -envfile $envfile -action t

$I_AM_IN_TESTING = $True

Describe "code" {
    It  "should install phoenix" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        $tgzFile = Join-Path $here -ChildPath "../../../apache-phoenix-4.9.0-HBase-1.2-bin.tar.gz"
        Test-Path $tgzFile -PathType Leaf | Should Be $True
        Install-Phoenix $myenv
    }
}
