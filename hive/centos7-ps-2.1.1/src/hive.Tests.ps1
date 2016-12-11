# $here = Split-Path -Parent $MyInvocation.MyCommand.Path
$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$resutl = . "$here\$sut" -envfile $envfile -action t


Describe "code" {
    It  "should install hive" {
        $myenv = New-EnvForExec $envfile | Decorate-Env
        $myenv.InstallDir | Should Be "/opt/hive"

        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/apache-hive-2.1.1-bin.tar.gz"

        Test-Path $tgzFile -PathType Leaf | Should Be $True

        $myenv.getUploadedFile("apache-hive-.*\.tar\.gz") | Should Be "/easy-installer/apache-hive-2.1.1-bin.tar.gz"

        $myenv.tgzFile = $tgzFile

        Remove-Item $myenv.resultFile -Force

        ([array]($myenv.software.textfiles)).Count | Should Be 1

        # all name should start with etc
        [array]$tfs = $myenv.software.textfiles | Where-Object {$_.name -match "^conf/"}
        $tfs.Count | Should Be $myenv.software.textfiles.length

        Install-Hive $myenv

        init-schema $myenv

        start-hiveserver $myenv

        $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json

<#
        $resultJson | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Sort-Object | Write-Output -NoEnumerate | Should Be "dfsFormatted", "env", "info"

        $di = Get-HadoopDirInfomation $myenv
        $coreSite =  Get-Item $di.coreSite
        $hdfsSite = Get-Item $di.hdfsSite
        $yarnSite = Get-Item $di.yarnSite
        $mapredSite = Get-Item $di.mapredSite
        
        [xml]$coreSiteDoc = Get-Content $coreSite

        $pnames = $coreSiteDoc.configuration.property | Select-Object -ExpandProperty Name | Write-Output -NoEnumerate

        $pnames | Should Be "fs.defaultFS", "io.file.buffer.size", "ha.zookeeper.quorum", "ha.zookeeper.session-timeout.ms"

        if ($myenv.yarnpiddir | Join-Path  -ChildPath "yarn-yarn-resourcemanager.pid" | Test-Path) {
            start-yarn $myenv stop
        }

        if ($myenv.dfspiddir | Join-Path  -ChildPath "hadoop-hdfs-namenode.pid" | Test-Path) {
            start-dfs $myenv stop
        }

        start-dfs $myenv start
        start-yarn $myenv start

        $myenv.dfspiddir | Join-Path  -ChildPath "hadoop-hdfs-namenode.pid" | Test-Path | Should Be $True
        $myenv.yarnpiddir | Join-Path  -ChildPath "yarn-yarn-resourcemanager.pid" | Test-Path | Should Be $True

        start-yarn $myenv stop
        $myenv.yarnpiddir | Join-Path  -ChildPath "yarn-yarn-resourcemanager.pid" | Test-Path | Should Be $False

        start-dfs $myenv stop
        $myenv.dfspiddir | Join-Path  -ChildPath "hadoop-hdfs-namenode.pid" | Test-Path | Should Be $False
#>
    }
}
