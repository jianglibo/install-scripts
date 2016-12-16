# how to run this script. powershell -File /path/to/this/file.

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

Get-Command java

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)

    $nameNodeBox = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "NameNode"} | Select-Object -First 1
    $resourceManagerBox = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "ResourceManager"} | Select-Object -First 1

    $myenv | Add-Member -MemberType NoteProperty -Name defaultFS -Value ("hdfs://{0}:{1}" -f $nameNodeBox.hostname, $myenv.software.configContent.ports.namenode.api)
    $myenv | Add-Member -MemberType NoteProperty -Name resourceManagerHostName -Value $resourceManagerBox.hostname

    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("hadoop-.*\.tar\.gz"))

    $users = $myenv.software.runas

    if (!$users -or ($users -is "string")) {
        $myenv | Add-Member -MemberType NoteProperty -Name hdfsuser -Value @{user=$users;group=$users}
        $myenv | Add-Member -MemberType NoteProperty -Name yarnuser -Value @{user=$users;group=$users}
    } else {
        $myenv | Add-Member -MemberType NoteProperty -Name hdfsuser -Value $users.hdfs
        $myenv | Add-Member -MemberType NoteProperty -Name yarnuser -Value $users.yarn
    }

        # piddir and logdir
    $envvs = $myenv.software.configContent.asHt("envvs")

    if ($envvs.HADOOP_PID_DIR) {
        if ($envvs.HADOOP_PID_DIR | Test-AbsolutePath) {
            $dfspiddir = $envvs.HADOOP_PID_DIR
        } else {
            $dfspiddir = $myenv.installDir | Join-Path -ChildPath $envvs.HADOOP_PID_DIR
        }
    }

    if ($envvs.HADOOP_LOG_DIR) {
        if ($envvs.HADOOP_LOG_DIR | Test-AbsolutePath) {
            $dfslogdir = $envvs.HADOOP_LOG_DIR
        } else {
            $dfslogdir = $myenv.installDir | Join-Path -ChildPath $envvs.HADOOP_LOG_DIR
        }
    }

    if ($envvs.YARN_LOG_DIR) {
        if ($envvs.YARN_LOG_DIR | Test-AbsolutePath) {
            $yarnlogdir = $envvs.YARN_LOG_DIR
        } else {
            $yarnlogdir = $myenv.installDir | Join-Path -ChildPath $envvs.YARN_LOG_DIR
        }
    }

    if ($envvs.YARN_PID_DIR) {
        if ($envvs.YARN_PID_DIR | Test-AbsolutePath) {
            $yarnpiddir = $envvs.YARN_PID_DIR
        } else {
            $yarnpiddir = $myenv.installDir | Join-Path -ChildPath $envvs.YARN_PID_DIR
        }
    }

    $myenv | Add-Member -MemberType NoteProperty -Name dfslogdir -Value $dfslogdir
    $myenv | Add-Member -MemberType NoteProperty -Name dfspiddir -Value $dfspiddir
    $myenv | Add-Member -MemberType NoteProperty -Name yarnlogdir -Value $yarnlogdir
    $myenv | Add-Member -MemberType NoteProperty -Name yarnpiddir -Value $yarnpiddir
    $myenv
}

function Get-HadoopDirInfomation {
    Param($myenv)
    $h = @{}
    $h.hadoopDaemon = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/sbin/hadoop-daemon.sh"} | Select-Object -First 1 -ExpandProperty FullName
    $h.hadoopDir = $h.hadoopDaemon | Split-Path -Parent | Split-Path -Parent
    $h.yarnDaemon = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/sbin/yarn-daemon.sh"} | Select-Object -First 1 -ExpandProperty FullName
    $h.hdfsCmd = Join-Path -Path $h.hadoopDir -ChildPath "bin/hdfs"
    $h.hadoopCmd = Join-Path -Path $h.hadoopDir -ChildPath "bin/hadoop"
    $h.etcHadoop = Join-Path -Path $h.hadoopDir -ChildPath "etc/hadoop"
    $h.coreSite = Join-Path $h.etcHadoop -ChildPath "core-site.xml"
    $h.hdfsSite = Join-Path $h.etcHadoop -ChildPath "hdfs-site.xml"
    $h.yarnSite = Join-Path $h.etcHadoop -ChildPath "yarn-site.xml"
    $h.mapredSite = Join-Path $h.etcHadoop -ChildPath "mapred-site.xml"

    if (! (Test-Path $h.mapredSite)) {
        Join-Path $h.etcHadoop -ChildPath "mapred-site.xml.template" | Copy-Item -Destination $h.mapredSite | Out-Null
    }
    $h
}

function Install-Hadoop {
    Param($myenv)
    $myenv.InstallDir | New-Directory

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Run-Tar $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        return
    }
    Write-ConfigFiles -myenv $myenv
}


function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}
    $yarnDirs = @()
    $returnToClient = @{}
    $returnToClient.hadoop = @{}

    $DirInfo = Get-HadoopDirInfomation -myenv $myenv

    $returnToClient.hadoop.dirInfo = $DirInfo

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.hadoopDir | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    # process core-site.xml
    [xml]$coreSiteDoc = Get-Content $DirInfo.coreSite

    Set-HadoopProperty -doc $coreSiteDoc -name "fs.defaultFS" -value $myenv.defaultFS

    $zkKey = "ha.zookeeper.quorum"

    if (! (Test-HadoopProperty -doc $coreSiteDoc -name $zkKey)) {
        $zkurls = ($myenv.boxGroup.boxes | ? {$_.roles -match "ZOOKEEPER"} | Select-Object -ExpandProperty hostname) -join ","

        if ($zkurls) {
            Set-HadoopProperty -doc $coreSiteDoc -name $zkKey -value $zkurls
        } else {
            Write-Error "There's no $zkKey in core-site.xml, and can't imagin from boxgroups"
        }
    }


    Save-Xml -doc $coreSiteDoc -FilePath $DirInfo.coreSite -encoding ascii

    # process yarn-site.xml, because resourceManagerHostName is determined at runtime. it must write this way.
    [xml]$yarnSiteDoc = Get-Content $DirInfo.yarnSite

    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.resourcemanager.address" -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.api)
    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.resourcemanager.scheduler.address" -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.scheduler)
    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.resourcemanager.resource-tracker.address" -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.resourceTracker)
    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.resourcemanager.admin.address" -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.admin)
    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.resourcemanager.webapp.address" -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.webapp)
    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.resourcemanager.hostname" -value $myenv.resourceManagerHostName

    Set-HadoopProperty -doc $yarnSiteDoc -name "yarn.nodemanager.log-dirs" -value $myenv.yarnlogdir
    $myenv.yarnlogdir -replace ".*///", "/" | New-Directory | Centos7-Chown -user $myenv.yarnuser.user -group $myenv.yarnuser.group

    if ("ResourceManager" -in $myenv.myRoles -or "NodeManager" -in $myenv.myRoles) {
        $myenv.yarnlogdir -replace ".*///", "/" | New-Directory | Centos7-Chown -user $myenv.yarnuser.user -group $myenv.yarnuser.group
        $myenv.yarnpiddir -replace ".*///", "/" | New-Directory | Centos7-Chown -user $myenv.yarnuser.user -group $myenv.yarnuser.group
        ($yarnSiteDoc.configuration.property | Where-Object name -eq "yarn.nodemanager.local-dirs" | Select-Object -First 1 -ExpandProperty value) -replace ".*///", "/" | New-Directory | Centos7-Chown -user $myenv.yarnuser.user -group $myenv.yarnuser.group
    }

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        Centos7-SetHostName -hostname $myenv.box.hostname
    }

    if("ResourceManager" -in $myenv.myRoles) {
        Centos7-FileWall -ports $myenv.software.configContent.firewall.ResourceManager
    }

    if("NodeManager" -in $myenv.myRoles) {
        Centos7-FileWall -ports $myenv.software.configContent.firewall.NodeManager
    }


    Save-Xml -doc $yarnSiteDoc -FilePath $DirInfo.yarnSite -encoding ascii

    # find directory used by hdfs from hdfs-site.xml
    [xml]$hdfsSiteDoc = Get-Content $DirInfo.hdfsSite

    $returnToClient.hadoop.superusergroup = Choose-FirstTrueValue (Get-HadoopProperty -doc $hdfsSiteDoc -name "dfs.permissions.superusergroup") "supergroup"

    $namenodeDirKey = "dfs.namenode.name.dir"
    $datanodeDirKey = "dfs.datanode.data.dir"

    if (Test-HadoopProperty -doc $hdfsSiteDoc -name $namenodeDirKey) {
        $namenodeDir = ($hdfsSiteDoc.configuration.property | Where-Object name -eq $namenodeDirKey | Select-Object -First 1 -ExpandProperty value) -replace ".*///", "/"
    } else {
        $namenodeDir = $myenv.installDir | Join-Path -ChildPath "hadoop-usage" | Join-Path -ChildPath "dfs" | Join-Path -ChildPath "name"
        Set-HadoopProperty -doc $hdfsSiteDoc -name $namenodeDirKey -value "file://$namenodeDir"
    }

    if (Test-HadoopProperty -doc $hdfsSiteDoc -name $datanodeDirKey) {
        $datanodeDir = ($hdfsSiteDoc.configuration.property | Where-Object name -eq $datanodeDirKey | Select-Object -First 1 -ExpandProperty value) -replace ".*///", "/"
    } else {
        $datanodeDir = $myenv.installDir | Join-Path -ChildPath "hadoop-usage" | Join-Path -ChildPath "dfs" | Join-Path -ChildPath "data"
        Set-HadoopProperty -doc $hdfsSiteDoc -name $datanodeDirKey -value "file://$datanodeDir"
    }

    if ("NameNode" -in $myenv.myRoles) {
        $namenodeDir | New-Directory | Centos7-Chown -user $myenv.hdfsuser.user -group $myenv.hdfsuser.group
        $resultHash.info.namenodeDir = $namenodeDir
        Centos7-FileWall -ports $myenv.software.configContent.firewall.NameNode
    }

    if ("DataNode" -in $myenv.myRoles) {
        $datanodeDir | New-Directory | Centos7-Chown -user $myenv.hdfsuser.user -group $myenv.hdfsuser.group
        Centos7-FileWall -ports $myenv.software.configContent.firewall.DataNode
    }

    Save-Xml -doc $hdfsSiteDoc -FilePath $DirInfo.hdfsSite -encoding ascii

    # write profile.d
    "HADOOP_PREFIX=$($DirInfo.hadoopDir)", "export HADOOP_PREFIX" | Out-File -FilePath "/etc/profile.d/hadoop.sh" -Encoding ascii

    $myenv.dfspiddir | New-Directory | Centos7-Chown -user $myenv.hdfsuser.user -group $myenv.hdfsuser.group
    $myenv.dfslogdir | New-Directory | Centos7-Chown -user $myenv.hdfsuser.user -group $myenv.hdfsuser.group

    $resultHash.env.HADOOP_LOG_DIR = $myenv.dfslogdir
    $resultHash.env.HADOOP_PID_DIR = $myenv.dfspiddir
    $resultHash.env.YARN_LOG_DIR = $myenv.yarnlogdir
    $resultHash.env.YARN_PID_DIR = $myenv.yarnpiddir

    $resultHash.dirInfo = $DirInfo

    $resultHash.env.HADOOP_PREFIX = $DirInfo.hadoopDir

    $myenv.software.configContent.asHt("envvs").GetEnumerator() | Where-Object {$_.Key -notin "HADOOP_LOG_DIR", "HADOOP_PID_DIR", "YARN_LOG_DIR", "YARN_PID_DIR"} | ForEach-Object {
        $resultHash.env[$_.Key] = $_.Value
    }

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.software.runner -envfile $envfile -code $PSCommandPath) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile

    if ("NameNode" -in $myenv.myRoles) {
        if(($resultHash.info.namenodeDir | Get-ChildItem -Recurse).Count -lt 3) {
            Format-Hdfs $myenv $DirInfo
        }
        $R_T_C_B
        $returnToClient | ConvertTo-Json
        $R_T_C_E
    }
}

function Format-Hdfs {
    Param($myenv, $DirInfo)
    if (!$DirInfo) {
        $DirInfo = Get-HadoopDirInfomation $myenv
    }
    expose-env $myenv
    $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json
    if (! $resultJson.dfsFormatted) {
#        $DirInfo.hdfsCmd, "namenode", "-format", $myenv.software.configContent.dfsClusterName  -join " " | Invoke-Expression
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} namenode -format {1}" -f $DirInfo.hdfsCmd, $myenv.software.configContent.dfsClusterName) -user $myenv.hdfsuser.user -group $myenv.hdfsuser.group
        $resultJson | Add-Member -MemberType NoteProperty -Name dfsFormatted -Value $True -Force
        $resultJson | ConvertTo-Json | Out-File -FilePath $myenv.resultFile -Encoding ascii
    }
}

# in /sbin/hadoop-daemon.sh there has code block calling hadoop-env.sh, we can do so
function start-dfs {
    Param($myenv, [parameter(Mandatory=$True)][ValidateSet("start","stop")][string]$action)
    expose-env $myenv
    $h = Get-HadoopDirInfomation $myenv
    if ("NameNode" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} --script hdfs $action namenode" -f $h.hadoopDaemon,$h.etcHadoop) -user "hdfs"
#        $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs start namenode
#        $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs stop namenode
    } elseif ("DataNode" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} --script hdfs $action datanode" -f $h.hadoopDaemon,$h.etcHadoop) -user "hdfs"
#        $HADOOP_PREFIX/sbin/hadoop-daemons.sh --config $HADOOP_CONF_DIR --script hdfs start datanode
#        $HADOOP_PREFIX/sbin/hadoop-daemons.sh --config $HADOOP_CONF_DIR --script hdfs stop datanode
    }
}

function start-yarn {
    Param($myenv, [parameter(Mandatory=$True)][ValidateSet("start","stop")][string]$action)
    expose-env $myenv
    $h = Get-HadoopDirInfomation $myenv
    if ("ResourceManager" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} $action resourcemanager" -f $h.yarnDaemon,$h.etcHadoop) -user "yarn"
#        $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR start resourcemanager
#        $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR stop resourcemanager
    } elseif ("NodeManager" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} $action nodemanager" -f $h.yarnDaemon,$h.etcHadoop) -user "yarn"
#        $HADOOP_YARN_HOME/sbin/yarn-daemons.sh --config $HADOOP_CONF_DIR start nodemanager
#        $HADOOP_YARN_HOME/sbin/yarn-daemons.sh --config $HADOOP_CONF_DIR stop nodemanager
    }
}

function expose-env {
    Param($myenv)
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

function run-dfs {
    Param($myenv, $dfslines)
    expose-env $myenv
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    $dfslines = $dfslines -split "`n"
    $dfslines = $dfslines | % {$_.Trim()} | % {if ($_ -notmatch "^-") {"-" + $_} else {$_}} | % {"{0} fs {1}" -f $rh.dirInfo.hadoopCmd, $_}
    $dfslines
    $dfslines | % {Centos7-Run-User -shell "/bin/bash" -scriptcmd "$_"  -user $myenv.hdfsuser.user -group $myenv.hdfsuser.group}
}

$myenv = New-EnvForExec $envfile | Decorate-Env

Persist-JavaHome $myenv

switch ($action) {
    "install" {
        Install-Hadoop $myenv
    }
    "start-dfs" {
        start-dfs $myenv start
    }
    "start-yarn" {
        start-yarn $myenv start
    }
    "stop-dfs" {
        start-dfs $myenv stop
    }
    "stop-yarn" {
        start-yarn $myenv stop
    }
    "run-dfs" {
        run-dfs $myenv (Parse-Parameters $remainingArguments)
    }
    "kill-alljava" {
        Get-Process | ? Name -EQ java | Stop-Process -Force
    }
    "t" {
        # do nothing
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success

<#

function Add-TagWithTextValue {
    Param([System.Xml.XmlElement]$parent, [String]$tag, $value)
    [System.Xml.XmlElement]$elem = $parent.OwnerDocument.CreateElement($tag)
    [System.Xml.XmlText]$text = $parent.OwnerDocument.CreateTextNode($value)
    $elem.AppendChild($text) | Out-Null  # The node added.
    $parent.AppendChild($elem)
}

function Add-HadoopProperty {
    Param([xml]$doc, [System.Xml.XmlElement]$parent, [String]$name, $value, $descprition)
    [System.Xml.XmlElement]$property = $doc.CreateElement("property")
    Add-TagWithTextValue -parent $property -tag "name" -value $name
    Add-TagWithTextValue -parent $property -tag "value" -value $value
    Add-TagWithTextValue -parent $property -tag "description" -value $descprition
    $parent.AppendChild($property)
}

function Test-HadoopProperty {
    Param([xml]$doc, [System.Xml.XmlElement]$parent, [String]$name)
    if (! $doc) {
        $doc = $parent.OwnerDocument
    }
    if (! $parent) {
        if ($doc.configuration) {
            $parent = $doc.configuration
        } else {
            $parent = $doc.DocumentElement
        }
    }
    $node = $parent.ChildNodes | Where-Object {$_.Name -eq $name} | Select-Object -First 1

    if ($node) {
        if ($node.Value -and $node.Value.trim()) {
            $True
        } else {
            $False
        }
    } else {
        $False
    }
}

function Set-HadoopProperty {
    Param([xml]$doc, [System.Xml.XmlElement]$parent, [String]$name, $value, [string]$descprition)
    if (! $doc) {
        $doc = $parent.OwnerDocument
    }
    if (! $parent) {
        if ($doc.configuration) {
            $parent = $doc.configuration
        } else {
            $parent = $doc.DocumentElement
        }
    }

    # exists item.
    $node =  $parent.ChildNodes | Where-Object {$_.Name -eq $name} | Select-Object -First 1
    if ($node) {
        $node.Name = $name
        $node.Value = $value
        $node.Description = $descprition
    } else {
        Add-HadoopProperty -doc $doc -parent $parent -name $name -value $value -descprition $descprition
    }
}
#>
