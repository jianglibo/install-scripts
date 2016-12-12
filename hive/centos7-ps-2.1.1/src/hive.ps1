# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)

    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("apache-hive-.*\.tar\.gz"))
    $users = $myenv.software.runas
    # piddir and logdir
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

    $myenv.InstallDir | New-Directory

    $myenv.InstallDir | Join-Path -ChildPath "pidFolder" | New-Directory | Centos7-Chown -user $myenv.software.runas

    $myenv.InstallDir | Join-Path -ChildPath "logFolder" | New-Directory | Centos7-Chown -user $myenv.software.runas

    $superGroup = Choose-FirstTrueValue $myenv.boxGroup.installResults.hadoop.superusergroup "supergroup"

    Centos7-UserManager -username $myenv.software.runas -group $superGroup -action add

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Run-Tar $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        Write-Error ($myenv.tgzFile + " doesn't exists.")
    }
    Write-ConfigFiles -myenv $myenv | Out-Null
}


function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.envvs = @{}
    $resultHash.info = @{}
    $yarnDirs = @()

    $DirInfo = Get-HiveDirInfomation -myenv $myenv

    $resultHash.envvs.HIVE_HOME = $DirInfo.hiveHome

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.hiveHome | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    # process hive-site.xml
    [xml]$hiveSiteDoc = Get-Content $DirInfo.hiveSite

    $zkKey = "hive.zookeeper.quorum"

    if (! (Test-HadoopProperty -doc $hiveSiteDoc -name $zkKey)) {
        $zkurls = ($myenv.boxGroup.boxes | ? {$_.roles -match "ZOOKEEPER"} | Select-Object -ExpandProperty hostname) -join ","
        if ($zkurls) {
            Set-HadoopProperty -doc $hiveSiteDoc -name $zkKey -value $zkurls
        }
    }

    $loglocKey = "hive.server2.logging.operation.log.location"

    if (! (Test-HadoopProperty -doc $hiveSiteDoc -name $loglocKey)) {
        $logloc = ($myenv.InstallDir | Join-Path -ChildPath "operation_logs" | New-Directory)
        Centos7-Chown -user $myenv.software.runas -Path $logloc
        Set-HadoopProperty -doc $hiveSiteDoc -name $loglocKey -value "$logloc"
    }

    $thriftPort = Get-HadoopProperty -doc $hiveSiteDoc -name "hive.server2.thrift.port"
    $webuiPort = Get-HadoopProperty -doc $hiveSiteDoc -name "hive.server2.webui.port"
    $thriftHttpPort = Get-HadoopProperty -doc $hiveSiteDoc -name "hive.server2.thrift.http.port"

    $metaStoreKey = "javax.jdo.option.ConnectionURL"

    $metaStoreDb = Get-HadoopProperty -doc $hiveSiteDoc -name $metaStoreKey

    $newdbname = "metastore_db"
    $done = $False

    if ($metaStoreDb) {
        $dbname = $metaStoreDb -replace "^.*databaseName=([^;]+;.*$)",'$1'
        if (Test-AbsolutePath $dbname) {
            $done = $True
        }
        $newdbname = $dbname
    }

    if (!$done) {
        $metaFolder = ($myenv.InstallDir | Join-Path -ChildPath "metaStoreFolder" | New-Directory)
        Centos7-Chown -user $myenv.software.runas -Path $metaFolder
        $newdbname = $metaFolder | Join-Path -ChildPath $newdbname
        Write-Host $newdbname
        $metaStoreDb = "jdbc:derby:;databaseName=$newdbname;create=true"
        Set-HadoopProperty -doc $hiveSiteDoc -name $metaStoreKey -value $metaStoreDb
    }

    $resultHash.info.metadb = $newdbname

    Centos7-FileWall -ports $thriftPort,$thriftHttpPort,$webuiPort

    Save-Xml -doc $hiveSiteDoc -FilePath $DirInfo.hiveSite -encoding ascii

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        Centos7-SetHostName -hostname $myenv.box.hostname
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
}

function remove-hive {
    Param($myenv)

}

function init-schema {
    Param($myenv)
    expose-env $myenv
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    if (!$rh.info.initSchema.completed) {
        $scmd = "{0} -dbType derby -initSchema --verbose" -f  ($rh.dirInfo.hiveHome | Join-Path -ChildPath "bin/schematool")
        Centos7-Run-User -shell "/bin/bash" -scriptcmd $scmd -user $myenv.software.runas
        Alter-ResultFile -resultFile $myenv.resultFile -keys "info","initSchema","completed" -value $True
    }
}

function start-hiveserver {
    Param($myenv)
    expose-env $myenv
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    $scmd = $rh.dirInfo.hiveHome | Join-Path -ChildPath "bin/hiveserver2"
    Centos7-Nohup -scriptcmd $scmd -user $myenv.software.runas -NICENESS 0 -logfile $rh.logFile -pidfile $rh.pidFile
}

function stop-hiveserver {
    Param($myenv)
    expose-env $myenv
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    if (Test-Path $rh.pidFile) {
        $pidcontent = Get-Content $rh.pidFile
        if ($pidcontent) {
            Stop-Process -Id $pidcontent
            Remove-Item $rh.pidFile -Force
        }       
    } else {
        Write-Error ($rh.pidFile + " doesn't exists")
    }
}

function expose-env {
    Param($myenv)
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    Add-AsHtScriptMethod $rh
    $envhash =  $rh.asHt("envvs")
    $envhash.GetEnumerator() | ForEach-Object {
        Set-Content -Path "env:$($_.Key)" -Value $_.Value
    }

    if (!$envhash.javahome) {
        Set-Content -Path "env:JAVA_HOME" -Value (Get-JavaHome)
    }
}

$myenv = New-EnvForExec $envfile | Decorate-Env

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
    "t" {
        # do nothing
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success
