﻿Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

Get-Command java | Out-Null

function ConvertTo-DecoratedEnv {
    Param([parameter(ValueFromPipeline=$True)]$myenv)

    if (($myenv.box.hostname -eq $myenv.box.ip) -and ("HbaseMaster" -in $myenv.myRoles)) {
        Write-Error "Hbase Master must has a hostname"
    }

    $masterBox = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "HbaseMaster"} | Select-Object -First 1
    $regionServerBoxes = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "RegionServer"}

    $myenv | Add-Member -MemberType NoteProperty -Name masterBox -Value $masterBox
    $myenv | Add-Member -MemberType NoteProperty -Name regionServerBoxes -Value $regionServerBoxes


    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("hbase-.*\.tar\.gz"))

    # piddir and logdir
    $envvs = $myenv.software.configContent.asHt("envvs")
    $myenv | Add-Member -MemberType NoteProperty -Name user -Value $myenv.software.runas
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

    $myenv | Add-Member -MemberType NoteProperty -Name logdir -Value $logdir
    $myenv | Add-Member -MemberType NoteProperty -Name piddir -Value $piddir
    $myenv
}

function Get-HbaseDirInfomation {
    Param($myenv)
    $h = @{}
    $hbversion = $myenv.tgzFile -replace ".*?(\d+\.\d+\.\d+).*",'$1'

    [array]$hdaemons = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "${hbversion}.*/bin/hbase-daemon.sh$"}

    if ($hdaemons.Count -ne 1) {
        "Expected exactly 1 hbase-daemon.sh in installing directory, But found " + $hdaemons.Count | Write-Error
    }
    $h.hbaseDaemon = $hdaemons | Select-Object -First 1 -ExpandProperty FullName

    $h.hbasebin = $h.hbaseDaemon | Split-Path -Parent | Join-Path -ChildPath hbase

    $h.hbaseDir = $h.hbaseDaemon | Split-Path -Parent | Split-Path -Parent
    $h.hbaseConfDir = $h.hbaseDir | Join-Path -ChildPath conf
    $h.regionserversFile = $h.hbaseConfDir | Join-Path  -ChildPath regionservers
    $h.hbaseSite = $h.hbaseConfDir | Join-Path  -ChildPath hbase-site.xml
    $h
}

function Install-Hbase {
    Param($myenv)
    $myenv.InstallDir | New-Directory | Out-Null

    Switch-HbaseStatus $myenv -action "stop"

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir
    } else {
        $myenv.tgzFile + " Doesn't exists." | Write-Error
    }
    Write-ConfigFiles -myenv $myenv
}


function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}

    $returnToClient = @{}
    $returnToClient.hbase = @{}

    $DirInfo = Get-HbaseDirInfomation -myenv $myenv

    
    $returnToClient.hbase.dirInfo = $DirInfo
    $returnToClient.hbase.user = $myenv.software.runas

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.hbaseDir | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    # process hbase-site.xml
    [xml]$hbaseSiteDoc = Get-Content $DirInfo.hbaseSite

    $rootDirKey = "hbase.rootdir"

    if (! (Test-HadoopProperty -doc $hbaseSiteDoc -name $rootDirKey)) {
        $hadoopNameNode = $myenv.boxGroup.boxes | Where-Object {$_.roles -match "NameNode"} | Select-Object -First 1 -ExpandProperty hostname

        if (! $hadoopNameNode) {
            Write-Error "There's no $rootDirKey in hbase-site.xml, and can't imagin from boxgroups"
        }
        $hdfsPort = $myenv.software.configContent.ports.namenode.api
        Set-HadoopProperty -doc $hbaseSiteDoc -name $rootDirKey -value (("hdfs://{0}:{1}/user/" + $myenv.user.user) -f $hadoopNameNode,$hdfsPort)
    }

    $zkKey = "hbase.zookeeper.quorum"
    if (! (Test-HadoopProperty -doc $hbaseSiteDoc -name $zkKey)) {
        $zkurls = ($myenv.boxGroup.boxes | Where-Object {$_.roles -match "ZOOKEEPER"} | Select-Object -ExpandProperty hostname) -join ","
        if ($zkurls) {
            Set-HadoopProperty -doc $hbaseSiteDoc -name $zkKey -value $zkurls
        } else {
            Write-Error "There's no $zkKey in hbase-site.xml, and can't imagin from boxgroups"
        }
    }

     Save-Xml -doc $hbaseSiteDoc -FilePath $DirInfo.hbaseSite -encoding ascii

    # process regionservers
    $myenv.regionServerBoxes | Select-Object -ExpandProperty hostname | Out-File -FilePath $DirInfo.regionserversFile -Encoding ascii

    $myenv.logdir,$myenv.piddir | New-Directory | Invoke-Chown -user $myenv.user.user -group $myenv.user.group

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        Set-HostName -hostname $myenv.box.hostname
    }

    if("HbaseMaster" -in $myenv.myRoles) {
        Update-FirewallItem -ports $myenv.software.configContent.firewall.Master
        Write-ReturnToClient -returnToClient $returnToClient
    }

    if("RegionServer" -in $myenv.myRoles) {
        Update-FirewallItem -ports $myenv.software.configContent.firewall.RegionServer
    }

    $resultHash.env.HBASE_LOG_DIR = $myenv.logdir
    $resultHash.env.HBASE_PID_DIR = $myenv.piddir

    $myenv.software.configContent.asHt("envvs").GetEnumerator() | Where-Object {$_.Key -notin "HBASE_LOG_DIR", "HBASE_PID_DIR"} | ForEach-Object {
        $resultHash.env[$_.Key] = $_.Value
    }

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.user.user -envfile $envfile -code $PSCommandPath) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile
}

function Switch-HbaseStatus {
    Param($myenv,$action="start")
    Start-ExposeEnv $myenv
    $h = Get-HbaseDirInfomation $myenv
    if ("HbaseMaster" -in $myenv.myRoles) {
        Start-RunUser -shell "/bin/bash" -scriptcmd ("{0} --config {1} {2} master" -f $h.hbaseDaemon,$h.hbaseConfDir,$action) -user $myenv.user.user -group $myenv.user.group
    } elseif ("RegionServer" -in $myenv.myRoles) {
        Start-RunUser -shell "/bin/bash" -scriptcmd ("{0} --config {1} {2} regionserver" -f $h.hbaseDaemon,$h.hbaseConfDir,$action) -user $myenv.user.user -group $myenv.user.group
    }
}

# function stop-hbase {
#     Param($myenv)
#     if (Test-Path $myenv.resultFile) {
#         Start-ExposeEnv $myenv
#         $h = Get-HbaseDirInfomation $myenv
        
#         if ("HbaseMaster" -in $myenv.myRoles) {
#             $runUserResult = Start-RunUser -shell "/bin/bash" -scriptcmd ("{0} --config {1} stop master stop" -f $h.hbaseDaemon,$h.hbaseConfDir) -user $myenv.user.user -group $myenv.user.group
#         } elseif ("RegionServer" -in $myenv.myRoles) {
#             $runUserResult = Start-RunUser -shell "/bin/bash" -scriptcmd ("{0} --config {1} stop regionserver" -f $h.hbaseDaemon,$h.hbaseConfDir) -user $myenv.user.usre -group $myenv.user.group
#         }
#         $notrunning = $runUserResult | Where-Object {$_ -match "org.apache.hadoop.hbase.MasterNotRunningException"} | Select-Object -First 1
#         if ($notrunning) {
#             "Hbase didn't run on this server."
#         } else {
#             $runUserResult
#         }
#     }
# }

function Start-ExposeEnv {
    Param($myenv)
    if (Test-Path $myenv.resultFile) {
        $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
        Add-AsHtScriptMethod $rh
        $envhash =  $rh.asHt("env")
        $envhash.GetEnumerator() | ForEach-Object {
            Set-Content -Path "env:$($_.Key)" -Value $_.Value
        }

        if (!$envhash.javahome) {
            Set-Content -Path "env:JAVA_HOME" -Value (Get-JavaHome)
        }
    }
}

function Get-HbaseConfiguration {
    Param($myenv)
    if("HbaseMaster" -in $myenv.myRoles) {
        $DirInfo = Get-HbaseDirInfomation -myenv $myenv
        $returnToDownload = @{}
        $zipedFile = $DirInfo.hbaseDir | Split-Path -Parent | Join-Path -ChildPath "hbaseConfig.zip"
        Compress-Archive -Path $DirInfo.hbaseConfDir -DestinationPath $zipedFile -CompressionLevel Fastest -Force
        $files = @()
        $files += @{name=(Split-Path $zipedFile -Leaf);fullName="$zipedFile"}
        $returnToDownload.files = $files
        Write-DownloadToClient -returnToDownload $returnToDownload
    }
}
$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "install" {
        Install-Hbase $myenv
    }
    "restart" {
        Switch-HbaseStatus $myenv -action "restart"
    }
    "start" {
        Switch-HbaseStatus $myenv -action "start"
    }
    "stop" {
        Switch-HbaseStatus $myenv -action "stop"
    }
    "download-config" {
        Get-HbaseConfiguration $myenv
    }
    "t" {
        # do nothing
    }
    "reconfig" {
        Write-ConfigFiles -myenv $myenv
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
