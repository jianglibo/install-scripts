$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$resutl = . "$here\$sut" -envfile $envfile -action t


Describe "code" {
    It "should handle core-default.xml" {
        $dxml = Join-Path -Path $here -ChildPath "../fixtures/core-default.xml"
        [xml]$o = Get-Content $dxml

        $o -is [xml] | Should Be $true

        $o.configuration | Should Be $true
        ($o.configuration.property | Where-Object Name -EQ "hadoop.tmp.dir").value = "/abc"

        $tf = New-TemporaryFile
        # compatibility with linux powershell
        Save-Xml -doc $o -FilePath $tf -encoding ascii
        # mata of xml should be remain.
        (Get-Content $tf | Out-String) -match "<\?xml-styleshee" | Should Be $true
        
        # value should be changed.
        (([xml](Get-Content $tf)).configuration.property | Where-Object Name -EQ "hadoop.tmp.dir").value | Should Be "/abc"
    }
    It "should create new xml document" {
        [xml]$xmlDoc = @"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
</configuration>
"@
        $xmlDoc.DocumentElement.Name | Should Be "configuration"
        $xmlDoc.configuration | Should Be $False

        if ($xmlDoc.configuration) {
            $configuration = $xmlDoc.configuration
        } else {
            $configuration = $xmlDoc.DocumentElement
        }
        Set-HadoopProperty -parent $configuration  -name "hadoop.common.configuration.version" -value 0.23.0 -descprition "version of this configuration file"
        $tf = New-TemporaryFile
        Save-Xml -doc $xmlDoc -FilePath $tf -encoding ascii
        (Get-Content $tf | Out-String) -match "<name>hadoop\.common\.configuration\.version</name>" | Should Be $true
        Remove-Item -Path $tf

        [xml]$xmlDoc = @"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
</configuration>
"@
        Set-HadoopProperty -doc $xmlDoc  -name "hadoop.common.configuration.version" -value 0.23.0 -descprition "version of this configuration file"
        $tf = New-TemporaryFile
        Save-Xml -doc $xmlDoc -FilePath $tf -encoding ascii
        (Get-Content $tf | Out-String) -match "<name>hadoop\.common\.configuration\.version</name>" | Should Be $true
        Remove-Item -Path $tf
    }

    It "should handle core-site.xml" {
        $dxml = Join-Path -Path $here -ChildPath "configfiles/etc/hadoop/core-site.xml"
        [xml]$o = Get-Content $dxml
        $o.configuration | Should Be $True
    }

    It  "should install hadoop" {
        $myenv = New-EnvForExec $envfile | Decorate-Env

        $envvs = $myenv.software.configContent.asHt("envvs")

        if ($envvs.HADOOP_PID_DIR) {
            if ($envvs.HADOOP_PID_DIR | Test-AbsolutePath) {
                $piddir = $envvs.HADOOP_PID_DIR
            } else {
                $piddir = $myenv.installDir | Join-Path -ChildPath $envvs.HADOOP_PID_DIR
            }
        }

        if ($envvs.HADOOP_LOG_DIR) {
            if ($envvs.HADOOP_LOG_DIR | Test-AbsolutePath) {
                $logdir = $envvs.HADOOP_LOG_DIR
            } else {
                $logdir = $myenv.installDir | Join-Path -ChildPath $envvs.HADOOP_LOG_DIR
            }
        }

        $piddir | Should Be "/opt/hadoop/dfspiddir"
        $logdir | Should Be "/opt/hadoop/dfslogdir"

        $myenv.InstallDir | Should Be "/opt/hadoop"

#        ($myenv.software.configContent.asHt("envvs").GetEnumerator() | measure).Count | Should Be 5

        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/hadoop-2.7.3.tar.gz"

        Test-Path $tgzFile -PathType Leaf | Should Be $True

        $myenv.getUploadedFile("hadoop-.*\.tar\.gz") | Should Be "/opt/easyinstaller/hadoop-2.7.3.tar.gz"
        $myenv.tgzFile = $tgzFile

        ($myenv.software.textfiles).length | Should Be 30

        # all name should start with etc
        ($myenv.software.textfiles | Where-Object {$_.name -match "^etc/"}).Count | Should Be $myenv.software.textfiles.length

        $myenv.resultFile | Should Be "/opt/easyinstaller/results/hadoop-CentOs7-ps-2.7.3/easyinstaller-result.json"

        $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json

        $resultJson.getType() | Should Be "System.Management.Automation.PSCustomObject"

        $resultJson | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Sort-Object | Write-Output -NoEnumerate | Should Be "dfsFormatted", "env", "info"

        $resultJson | Add-Member -MemberType NoteProperty -Name dfsFormatted -Value $True -Force

        $resultJson | Add-Member -MemberType NoteProperty -Name dfsFormatted -Value $True -Force

        $resultJson.dfsFormatted | Should Be $True

        Install-Hadoop $myenv

        $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json
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
    }

    It "should get right user" {
        $myenv = New-EnvForExec $envfile | Decorate-Env

        $users = $myenv.software.runas

        $users.getType() | Should Be "hashtable"

        $users -is "string" | Should Be $False

        if ($users -is "string") {
            $user_hdfs = $users
            $user_yarn = $users
        } else {
            $user_hdfs = $users.hdfs
            $user_yarn = $users.yarn
        }

        $user_hdfs | Should Be "hdfs"
        $user_yarn | Should Be "yarn"
    }
}
