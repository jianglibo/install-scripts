$here = $PSScriptRoot
$sut = (Split-Path -Leaf $PSCommandPath) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve
$commonPath = $here | Join-Path -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath
. ($here | Join-Path -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve
$resutl = . "$here\$sut" -envfile $envfile -action t

$I_AM_IN_TESTING = $True

Describe "code" {
    It "should install oss" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        $tn = "nexus-3.2.0-01-unix.tar.gz";
        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/$tn"
        Write-Host $tgzFile
        Test-Path $tgzFile -PathType Leaf | Should Be $True
        $myenv.tgzFile = $tgzFile
        install-oss $myenv
        $pf = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object Name -Match "nexus.properties" | Select-Object -First 1 
        Get-Content $pf | Where-Object {$_ -match "I Should sit in my place."} | Should Be $True
    }
}