# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [parameter(Mandatory=$true)]
    $action,
    [string]
    $codefile
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

if (! $codefile) {
    $codefile = $MyInvocation.MyCommand.Path
}

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


function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)

    $nameNodeBox = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "NameNode"} | Select-Object -First 1
    $resourceManagerBox = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "ResourceManager"} | Select-Object -First 1

    $myenv | Add-Member -MemberType NoteProperty -Name defaultFS -Value ("hdfs://{0}:{1}" -f $nameNodeBox.hostname, $myenv.software.configContent.ports.namenode.api)
    $myenv | Add-Member -MemberType NoteProperty -Name resourceManagerHostName -Value $resourceManagerBox.hostname

    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("hadoop-.*\.tar\.gz"))
    $myenv
}

function Get-HadoopDirInfomation {
    Param($myenv)
    $h = @{}
    $h.hadoopDaemon = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/sbin/hadoop-daemon.sh"} | Select-Object -First 1 | Select-Object -ExpandProperty FullName
    $h.yarnDaemon = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/sbin/yarn-daemon.sh"} | Select-Object -First 1 | Select-Object -ExpandProperty FullName
    $h.hdfsCmd = Join-Path -Path $h.hadoopDaemon -ChildPath "../../bin/hdfs"
    $h.etcHadoop = Join-Path -Path $h.hadoopDaemon -ChildPath "../../etc/hadoop"
    $h.coreSite = Join-Path $h.etcHadoop -ChildPath "core-site.xml"
    $h.hdfsSite = Join-Path $h.etcHadoop -ChildPath "hdfs-site.xml"
    $h.yarnSite = Join-Path $h.etcHadoop -ChildPath "yarn-site.xml"
    $h.mapredSite = Join-Path $h.etcHadoop -ChildPath "mapred-site.xml"

    if (! (Test-Path $h.mapredSite)) {
        Join-Path $h.etcHadoop -ChildPath "mapred-site.xml.template" | Copy-Item -Destination $h.mapredSite | Out-Null
    }
    $h    
}

function Format-Hdfs {
    Param($myenv)
    $h = Get-HadoopDirInfomation $myenv
    $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json
    if (! $resultJson.dfsFormatted) {
        $h.hdfsCmd, "namenode", $myenv.software.configContent.dfsClusterName  -join " " | Invoke-Expression
        $resultJson.dfsFormatted = $True
        $resultJson | ConvertTo-Json | Out-File -FilePath $myenv.resultFile -Encoding ascii
    }
}

# in /sbin/hadoop-daemon.sh there has code block calling hadoop-env.sh, we can do so 
function start-dfs {
    Param($myenv)
    $h = Get-HadoopDirInfomation $myenv
    if ("NameNode" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} --script hdfs start namenode" -f $h.hadoopDaemon,$h.etcHadoop) -user "hdfs"
#        $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs start namenode
#        $HADOOP_PREFIX/sbin/hadoop-daemon.sh --config $HADOOP_CONF_DIR --script hdfs stop namenode
    } elseif ("DataNode" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} --script hdfs start datanode" -f $h.hadoopDaemon,$h.etcHadoop) -user "hdfs"
#        $HADOOP_PREFIX/sbin/hadoop-daemons.sh --config $HADOOP_CONF_DIR --script hdfs start datanode
#        $HADOOP_PREFIX/sbin/hadoop-daemons.sh --config $HADOOP_CONF_DIR --script hdfs stop datanode
    }
}

function start-yarn {
    Param($myenv)
    $h = Get-HadoopDirInfomation $myenv
    if ("ResourceManager" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} start resourcemanager" -f $h.yarnDaemon,$h.etcHadoop) -user "yarn"
#        $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR start resourcemanager
#        $HADOOP_YARN_HOME/sbin/yarn-daemon.sh --config $HADOOP_CONF_DIR stop resourcemanager
    } elseif ("NodeManager" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} start nodemanager" -f $h.yarnDaemon,$h.etcHadoop) -user "yarn"
#        $HADOOP_YARN_HOME/sbin/yarn-daemons.sh --config $HADOOP_CONF_DIR start nodemanager
#        $HADOOP_YARN_HOME/sbin/yarn-daemons.sh --config $HADOOP_CONF_DIR stop nodemanager
    }
}

function Install-Hadoop {
    Param($myenv)
    $resultHash = @{}
    $resultHash.env = @{}

    $hdfsDirs = @()
    $yarnDirs = @()

    if (!(Test-Path $myenv.InstallDir)) {
        New-Item -Path $myenv.InstallDir -ItemType Directory | Out-Null
    }

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Run-Tar $myenv.tgzFile -DestFolder $myenv.InstallDir
    } else {
        return
    }
    $h = Get-HadoopDirInfomation -myenv $myenv

    # process core-site.xml
    [xml]$coreSiteDoc = Get-Content $h.coreSite
    $myenv.software.configContent.coreSite | ForEach-Object {
        if ($_.Name -eq "fs.defaultFS") {
            Set-HadoopProperty -doc $coreSiteDoc -name $_.Name -value $myenv.defaultFS
        } elseif($_.Value){
            Set-HadoopProperty -doc $coreSiteDoc -name $_.Name -value $_.Value
        }
    }
    Save-Xml -doc $coreSiteDoc -FilePath $h.coreSite -encoding ascii

    
    # process hdfs-site.xml
    [xml]$hdfsSiteDoc = Get-Content $h.hdfsSite
    $myenv.software.configContent.hdfsSite | ForEach-Object {
        if ($_.Value) {
            Set-HadoopProperty -doc $hdfsSiteDoc -name $_.Name -value $_.Value
        }
        switch ($_.Name) {
            "dfs.namenode.name.dir" { if($_.Value) {$hdfsDirs += $_.Value }}
            "dfs.datanode.data.dir" { if($_.Value) {$hdfsDirs += $_.Value }}
        }
    }
    Save-Xml -doc $hdfsSiteDoc -FilePath $h.hdfsSite -encoding ascii


    # process yarn-site.xml
    [xml]$yarnSiteDoc = Get-Content $h.yarnSite
    $myenv.software.configContent.yarnSite | ForEach-Object {
        $n = $_.Name
        switch ($n) {
            "yarn.resourcemanager.address" {
                Set-HadoopProperty -doc $yarnSiteDoc -name $n -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.api)
            }
            "yarn.resourcemanager.scheduler.address" {
                Set-HadoopProperty -doc $yarnSiteDoc -name $n -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.scheduler)
            }
            "yarn.resourcemanager.resource-tracker.address" {
                Set-HadoopProperty -doc $yarnSiteDoc -name $n -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.resourceTracker)
            }
            "yarn.resourcemanager.admin.address" {
                Set-HadoopProperty -doc $yarnSiteDoc -name $n -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.admin)
            }
            "yarn.resourcemanager.webapp.address" {
                Set-HadoopProperty -doc $yarnSiteDoc -name $n -value ("{0}:{1}" -f $myenv.resourceManagerHostName, $myenv.software.configContent.ports.resourcemanager.webapp)
            }
            "yarn.resourcemanager.hostname" {
                Set-HadoopProperty -doc $yarnSiteDoc -name $n -value $myenv.resourceManagerHostName
            }
            default {
                if ($_.Value) {
                   Set-HadoopProperty -doc $yarnSiteDoc -name $n -value $_.Value
                }
                switch ($n) {
                    "yarn.nodemanager.local-dirs" { if($_.Value) {$yarnDirs += $_.Value }}
                    "yarn.nodemanager.log-dirs" { if($_.Value) {$yarnDirs += $_.Value }}
                    "yarn.nodemanager.remote-app-log-dir" { if($_.Value) {$yarnDirs += $_.Value }}
                }
            }
        }
    }
    Save-Xml -doc $yarnSiteDoc -FilePath $h.yarnSite -encoding ascii


    # process mapred-site.xml
    [xml]$mapredSiteDoc = Get-Content $h.mapredSite
    $myenv.software.configContent.mapredSite | ForEach-Object {
        if ($_.Value) {
            Set-HadoopProperty -doc $mapredSiteDoc -name $_.Name -value $_.Value
        }
    }
    Save-Xml -doc $mapredSiteDoc -FilePath $h.mapredSite -encoding ascii

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii

    $user = $myenv.software.runas | Trim-All

    if ("NameNode" -in $myenv.myRoles) {

    }

    if ("ResourceManager" -in $myenv.myRoles) {

    }

    if ("DataNode" -in $myenv.myRoles) {

    }
}

function Change-Status {
    Param($myenv, [String]$action)
    if (Test-Path $myenv.resultFile) {
        $result = Get-Content $myenv.resultFile | ConvertFrom-Json
        $result.executable, $action -join " " | Invoke-Expression
    }
}

$myenv = New-EnvForExec $envfile | Decorate-Env

switch ($action) {
    "install" {
        Install-Hadoop $myenv
    }
    "start-dfs" {

    }
    "start-yarn" {

    }
    default {
        Change-Status -myenv $myenv -action $action
    }
}

"@@success@@"
