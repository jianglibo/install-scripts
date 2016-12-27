# $here = Split-Path -Parent $MyInvocation.MyCommand.Path
$here = $PSScriptRoot
$sut = (Split-Path -Leaf $PSCommandPath) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve
$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath
. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\LinuxUtil.ps1" -Resolve)

$envfile = $here | Split-Path -Parent | Join-Path -ChildPath fixtures/envforcodeexec.json -Resolve

$I_AM_IN_TESTING = $True

$resutl = . "$here\$sut" -envfile $envfile -action t

Describe "code" {
    It  "should build oozie by tar" {
        return
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

        $fn = "oozie-4.3.0.tar.gz"

        $myenv.InstallDir | Should Be "/opt/oozie-build"

        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/$fn"

        Test-Path $tgzFile -PathType Leaf | Should Be $True

        $myenv.getUploadedFile("oozie-.*\.tar\.gz") | Should Be "/easy-installer/$fn"

        $myenv.tgzFile = $tgzFile

        Start-BuildOozieTar $myenv

        $Error.Count | Should Be 0
    }

    It  "should build oozie by git" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

        Start-BuildOozieGit $myenv

        $Error.Count | Should Be 0
    }
}
