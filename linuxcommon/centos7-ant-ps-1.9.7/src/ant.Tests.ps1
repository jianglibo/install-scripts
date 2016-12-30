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
    It "should install mvn" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        $tn = "apache-ant-1.9.7-bin.tar.gz";
        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/$tn"
        Write-Host $tgzFile
        Test-Path $tgzFile -PathType Leaf | Should Be $True
        $myenv.tgzFile = $tgzFile
        install-ant $myenv
    }
}