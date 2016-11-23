$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$resutl = . "$here\$sut" -envfile $envfile -action t


Describe "code" {
    It  "should install hbase" {
        $myenv = New-EnvForExec $envfile | Decorate-Env

        $envvs = $myenv.software.configContent.asHt("envvs")

        if ($envvs.HBASE_PID_DIR) {
            if ($envvs.HBASE_PID_DIR | Test-AbsolutePath) {
                $piddir = $envvs.HBASE_PID_DIR
            } else {
                $piddir = $myenv.installDir | Join-Path -ChildPath $envvs.HBASE_PID_DIR
            }
        }

        if ($envvs.HBASE_LOG_DIR) {
            if ($envvs.HBASE_LOG_DIR | Test-AbsolutePath) {
                $logdir = $envvs.HBASE_LOG_DIR
            } else {
                $logdir = $myenv.installDir | Join-Path -ChildPath $envvs.HBASE_LOG_DIR
            }
        }

        $piddir | Should Be "/opt/hbase/hbasepiddir"
        $logdir | Should Be "/opt/hbase/hbaselogdir"

        $myenv.InstallDir | Should Be "/opt/hbase"

        ($myenv.software.configContent.asHt("envvs").GetEnumerator() | measure).Count | Should Be 2

        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/hbase-1.2.4-bin.tar.gz"

        Test-Path $tgzFile -PathType Leaf | Should Be $True

        $myenv.getUploadedFile("hbase-.*\.tar\.gz") | Should Be "/opt/easyinstaller/hbase-1.2.4-bin.tar.gz"
        $myenv.tgzFile = $tgzFile

        ($myenv.software.textfiles).length | Should Be 7

        # all name should start with etc
        ($myenv.software.textfiles | Where-Object {$_.name -match "^conf/"}).Count | Should Be $myenv.software.textfiles.length

        $myenv.resultFile | Should Be "/opt/easyinstaller/results/hbase-CentOs7-ps-1.2.4/easyinstaller-result.json"

        Install-Hbase $myenv

        $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json
        $resultJson | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Sort-Object | Write-Output -NoEnumerate | Should Be "env", "info"

        $di = Get-HbaseDirInfomation $myenv

        if ($myenv.piddir | Join-Path  -ChildPath "hadoop-hdfs-namenode.pid" | Test-Path) {
            stop-hbase $myenv
        }

        start-hbase $myenv

        $myenv.piddir | Join-Path  -ChildPath "hadoop-hdfs-namenode.pid" | Test-Path | Should Be $True

        stop-hbase $myenv stop
        $myenv.piddir | Join-Path  -ChildPath "hadoop-hdfs-namenode.pid" | Test-Path | Should Be $False
    }
}
