# $here = Split-Path -Parent $MyInvocation.MyCommand.Path
$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$I_AM_IN_TESTING = $True

$resutl = . "$here\$sut" -envfile $envfile -action t

Describe "code" {
    It  "should install hive" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        $myenv.InstallDir | Should Be "/opt/hive"

        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/apache-hive-2.1.1-bin.tar.gz"

        Test-Path $tgzFile -PathType Leaf | Should Be $True

        $myenv.getUploadedFile("apache-hive-.*\.tar\.gz") | Should Be "/easy-installer/apache-hive-2.1.1-bin.tar.gz"

        $myenv.tgzFile = $tgzFile

        stop-hiveserver HiveServer2

        remove-metadb $myenv

<#
        if (Test-Path $myenv.resultFile) {
            $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json
            Remove-Item $myenv.resultFile -Force
            try {
                if ($resultJson.info.metadb -is [string]) {
                    $dbpath = $resultJson.info.metadb -replace "^([^;]+);.*",'$1' | Split-Path -Parent
                } else {
                    $dbpath = $resultJson.info.metadb.fullName -replace "^([^;]+);.*",'$1' | Split-Path -Parent
                }
                
                if (Test-Path $dbpath) {
                    Remove-Item -Path $dbpath -Recurse -Force
                }
            }
            catch {}
        }
#>
        
        ([array]($myenv.software.textfiles)).Count | Should Be 1

        # all name should start with etc
        [array]$tfs = $myenv.software.textfiles | Where-Object {$_.name -match "^conf/"}
        $tfs.Count | Should Be $myenv.software.textfiles.length

        $installResults = Install-Hive $myenv | ConvertFrom-ReturnToClientInstallResult

        $installResults.hive.info.metadb | Should Be "/opt/hive/metaStoreFolder/metastore_db"

        Initialize-HiveSchema $myenv

        start-hiveserver $myenv
    }
}
