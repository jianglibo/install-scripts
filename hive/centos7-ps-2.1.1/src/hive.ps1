# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

Get-Command java

function ConvertTo-DecoratedEnv {
    Param([parameter(ValueFromPipeline=$True)]$myenv)

    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("apache-hive-.*\.tar\.gz"))

    $superGroup = Select-FirstTrueValue $myenv.boxGroup.installResults.hadoop.superusergroup "hadoop"

    $user = $myenv.software.runas
    if (!$user) {
        $user = @{user="hive";group=$superGroup}
    } else {
        $user.group = $superGroup
    }
    $myenv | Add-Member -MemberType NoteProperty -Name user -Value $user
    $myenv
}

function Get-HiveDirInfomation {
    Param($myenv)
    $h = @{}
    $h.hiveExecutable = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/hive$"} | Select-Object -First 1 -ExpandProperty FullName
    $h.hiveHome = $h.hiveExecutable | Split-Path -Parent | Split-Path -Parent
    $h.hiveSite = $h.hiveHome | Join-Path -ChildPath "conf/hive-site.xml"
    $h
}

function Install-Hive {
    Param($myenv)

    if ("HIVE_SERVER" -notin $myenv.myRoles) {
        Write-Output "this box has'nt a role of HIVE_SERVER, skipping installation"
        return
    }

    stop-hiveserver -myenv $myenv

    $myenv.InstallDir | New-Directory

    $myenv.InstallDir | Join-Path -ChildPath "pidFolder" | New-Directory | Invoke-Chown -user $myenv.user.user -group $myenv.user.group

    $myenv.InstallDir | Join-Path -ChildPath "logFolder" | New-Directory | Invoke-Chown -user $myenv.user.user  -group $myenv.user.group

    New-LinuxUser -username $myenv.user.user -groupname $myenv.user.group

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        Write-Error ($myenv.tgzFile + " doesn't exists.")
    }
    Write-ConfigFiles -myenv $myenv
}


function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.envvs = @{}
    $resultHash.info = @{}

    $returnToClient = @{}
    $returnToClient.hive = @{}
    $returnToClient.hive.info = @{}

    $DirInfo = Get-HiveDirInfomation -myenv $myenv

    $resultHash.envvs.HIVE_HOME = $DirInfo.hiveHome

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.hiveHome | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    # process hive-site.xml
    [xml]$hiveSiteDoc = Get-Content $DirInfo.hiveSite

    $zkKey = "hive.zookeeper.quorum"

    if (! (Test-HadoopProperty -doc $hiveSiteDoc -name $zkKey)) {
        $zkurls = ($myenv.boxGroup.boxes | Where-Object {$_.roles -match "ZOOKEEPER"} | Select-Object -ExpandProperty hostname) -join ","
        if ($zkurls) {
            Set-HadoopProperty -doc $hiveSiteDoc -name $zkKey -value $zkurls
        }
    }

    $loglocKey = "hive.server2.logging.operation.log.location"

    if (! (Test-HadoopProperty -doc $hiveSiteDoc -name $loglocKey)) {
        $logloc = ($myenv.InstallDir | Join-Path -ChildPath "operation_logs" | New-Directory)
        Invoke-Chown -user $myenv.user.user -group $myenv.user.group -Path $logloc
        Set-HadoopProperty -doc $hiveSiteDoc -name $loglocKey -value "$logloc"
    }

    $thriftPort = Get-HadoopProperty -doc $hiveSiteDoc -name "hive.server2.thrift.port"
    $webuiPort = Get-HadoopProperty -doc $hiveSiteDoc -name "hive.server2.webui.port"
    $thriftHttpPort = Get-HadoopProperty -doc $hiveSiteDoc -name "hive.server2.thrift.http.port"

    $metaStoreKey = "javax.jdo.option.ConnectionURL"

    $metaStoreDb = Get-HadoopProperty -doc $hiveSiteDoc -name $metaStoreKey

    $urlPrefix = "jdbc:derby:;databaseName="
    $urlPostfix = ";create=true"

    $isAbsolute = $False
    if ($metaStoreDb) {
        if ($metaStoreDb -match "^(.*databaseName=)([^;]+)(;.*)$") {
            $urlPrefix = $Matches[1]
            $dbname = $Matches[2]
            $urlPostfix = $Matches[3]
        } else {
           "Unknown metastore url: $metaStoreDb" | Write-Error
        }
        if (Test-AbsolutePath $dbname) {
            $isAbsolute = $True
        }
    } else {
        $dbname = "metastore_db"
    }
    if (!$isAbsolute) {
        $dbname = $myenv.InstallDir | Join-Path -ChildPath "metaStoreFolder" | Join-Path -ChildPath $dbname
    }
    if ($dbname -match "::") {
        $dbname = $dbname -replace ".*::(.*)$",'$1'
    }
    $dbFolder = $dbname | Split-Path -Parent

    $dbFolder | New-Directory | Out-Null
    Invoke-Chown -user $myenv.user.user -group $myenv.user.group -Path $dbFolder

    $metaStoreDb = $urlPrefix,$dbname,$urlPostfix -join ""
    Set-HadoopProperty -doc $hiveSiteDoc -name $metaStoreKey -value $metaStoreDb

    $resultHash.info.metadb = $dbname

    $returnToClient.hive.info.metadb = $dbname

    Update-FirewallItem -ports $thriftPort,$thriftHttpPort,$webuiPort

    Save-Xml -doc $hiveSiteDoc -FilePath $DirInfo.hiveSite -encoding ascii

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        Set-HostName -hostname $myenv.box.hostname
    }

    $resultHash.dirInfo = $DirInfo

    $resultHash.pidFile = $myenv.InstallDir | Join-Path -ChildPath "pidFolder" | Join-Path -ChildPath "hive.pid"
    $resultHash.logFile = $myenv.InstallDir | Join-Path -ChildPath "logFolder" | Join-Path -ChildPath "hive.log"

    $envvs = $myenv.software.configContent.asHt("envvs")
    if ($envvs) {
        $envvs.GetEnumerator() | ForEach-Object {$resultHash.envvs[$_.Key] = $_.Value}
    }

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.software.runner -envfile $envfile -code $PSCommandPath) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile

    $dfscmds = "mkdir -p /tmp/hive", "chmod 777 /tmp/hive"
    Invoke-DfsCmd -hadoopCmd $myenv.boxGroup.installResults.hadoop.dirInfo.hadoopCmd -dfslines $dfscmds -user $myenv.boxGroup.installResults.hadoop.user.hdfs.user -group $myenv.boxGroup.installResults.hadoop.user.hdfs.group

    Initialize-HiveSchema -myenv $myenv

    Write-ReturnToClient -returnToClient $returnToClient
}

function remove-hive {
    Param($myenv)
}

function Initialize-HiveSchema {
    Param($myenv)
    Start-ExposeEnv $myenv
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    if (!$rh.info.initSchema.completed) {
        $scmd = "{0} -dbType derby -initSchema --verbose" -f  ($rh.dirInfo.hiveHome | Join-Path -ChildPath "bin/schematool")
        Start-RunUser -shell "/bin/bash" -scriptcmd $scmd -user $myenv.user.user -group $myenv.user.group
        Set-ResultFileItem -resultFile $myenv.resultFile -keys "info","initSchema","completed" -value $True
    }
}

function start-hiveserver {
    Param($myenv)
    Start-ExposeEnv $myenv
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    $scmd = $rh.dirInfo.hiveHome | Join-Path -ChildPath "bin/hiveserver2"
    Start-Nohup -scriptcmd $scmd -user $myenv.user.user -group $myenv.user.group  -NICENESS 0 -logfile $rh.logFile -pidfile $rh.pidFile
}

function stop-hiveserver {
    Param($myenv)
    Start-ExposeEnv $myenv
    $done = $False
    if ($myenv.resultFile -and (Test-Path $myenv.resultFile)) {
        $rh = Get-Content $myenv.resultFile | ConvertFrom-Json

        if (Test-Path $rh.pidFile) {
            $pidcontent = Get-Content $rh.pidFile
            if ($pidcontent -and $pidcontent.Trim()) {
                Stop-Process -Id $pidcontent
                Remove-Item $rh.pidFile -Force
                $done = $True
            }
        }
    }
    if (!$done) {
        $rh.pidFile + " doesn't exists"
        Stop-LinuxProcessByKill -namePtn "HiveServer2"
    }
}


function remove-metadb {
    Param($myenv)
    Start-ExposeEnv $myenv
    if ($myenv.resultFile -and (Test-Path $myenv.resultFile)) {
        $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
        stop-hiveserver -myenv $myenv

        if (Test-Path $rh.info.metadb -PathType Container) {
            Remove-Item -Path $rh.info.metadb -Recurse -Force
        } else {
            $rh.info.metadb + " is not a directory"
        }
    }
}

function Start-ExposeEnv {
    Param($myenv)
    if ($myenv.resultFile -and (Test-Path $myenv.resultFile)) {
        $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
        Add-AsHtScriptMethod $rh
        $envhash =  $rh.asHt("envvs")
        $envhash.GetEnumerator() | ForEach-Object {
            Set-Content -Path "env:$($_.Key)" -Value $_.Value
        }
    }

    if (!$envhash.javahome) {
        Set-Content -Path "env:JAVA_HOME" -Value (Get-JavaHome)
    }
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

if ("HIVE_SERVER" -notin $myenv.myRoles) {
    if (!$I_AM_IN_TESTING) {
        Write-Error "not a HIVE_SERVER"
    }
}

switch ($action) {
    "install" {
        Install-Hive $myenv
    }
    "start-hiveserver" {
        start-hiveserver $myenv
    }
    "stop-hiveserver" {
        stop-hiveserver $myenv
    }
    "remove-metadb" {
        remove-metadb $myenv
    }
    "t" {
        # do nothing
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
