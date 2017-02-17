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
        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/apache-phoenix-4.9.0-HBase-1.2-bin.tar.gz"
        $myenv.getUploadedFile("apache-phoenix-.*\.tar\.gz") | Should Be "/easy-installer/apache-phoenix-4.9.0-HBase-1.2-bin.tar.gz"
        $myenv.tgzFile = $tgzFile

        $tgzFile | Write-HostIfInTesting
        Test-Path $tgzFile -PathType Leaf | Should Be $True
        { Install-Phoenix $myenv } | Should Throw "`$myenv.boxGroup.installResults.hbase.dirInfo.hbaseDir is null."

        $fakeHbaseDir = "/easy-installer/fakeHbaseDir"

        if (-not (Test-Path -PathType Container $fakeHbaseDir)) {
            New-Item -Path $fakeHbaseDir -ItemType Directory
        }
        $fakeLibDir = $fakeHbaseDir | Join-Path -ChildPath "lib"

        if (Test-Path -Type Container $fakeLibDir) {
            Remove-Item -Path $fakeLibDir -Force
        }
        $v = Get-ChainedHashTable "installResults.hbase.dirInfo.hbaseDir" -VariableToSet $fakeHbaseDir

        $myenv.boxGroup.installResults = $v.installResults

        { Install-Phoenix $myenv } | Should Throw "cannot find hbase lib directory"

        New-Item -Path $fakeLibDir -Type Directory

        $myenv.InstallDir | Should Be "/opt/tmp"

        Install-Phoenix $myenv

        Get-ChildItem $fakeLibDir -Recurse | Select-Object -First 1 -ExpandProperty fullname | Should MatchExactly "-server.jar$"

        if (Test-Path -PathType Leaf $fakeHbaseDir) {
            Remove-Item -Path $fakeHbaseDir -Force -Recurse
        }
    }
     It "should work like Pester" {
         $v = Get-ChainedHashTable "`$a.b.c.d.e.f" -VariableToSet "hello"
         $v.a.b.c.d.e.f | Should Be "hello"
         "a" | Should beoftype "string"
         "a" | Should beexactly "a"
         # throw { abc } | Should Throw
     }
}
