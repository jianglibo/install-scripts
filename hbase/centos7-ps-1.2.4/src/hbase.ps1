# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
# server must has a hostname

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

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

    if (($myenv.box.hostname -eq $myenv.box.ip) -and ("Master" -in $myenv.myRoles)) {
        Write-Error "Hbase Master must has a hostname"
    }

    $masterBox = $myenv.boxGroup.boxes | Where-Object {($_.roles -split ",") -contains "Master"} | Select-Object -First 1
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
    $h.hbaseDaemon = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/hbase-daemon.sh$"} | Select-Object -First 1 -ExpandProperty FullName
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

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Run-Tar $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        return
    }
    Write-ConfigFiles -myenv $myenv | Out-Null
}


function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}

    $DirInfo = Get-HbaseDirInfomation -myenv $myenv

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.hbaseDir | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    # process regionservers
    $myenv.regionServerBoxes | Select-Object -ExpandProperty hostname | Out-File -FilePath $DirInfo.regionserversFile -Encoding ascii

    $myenv.logdir,$myenv.piddir | New-Directory | Centos7-Chown -user $myenv.user

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        Centos7-SetHostName -hostname $myenv.box.hostname
    }

    if("Master" -in $myenv.myRoles) {
        Centos7-FileWall -ports $myenv.software.configContent.firewall.Master
    }

    if("RegionServer" -in $myenv.myRoles) {
        Centos7-FileWall -ports $myenv.software.configContent.firewall.RegionServer
    }

    $resultHash.env.HBASE_LOG_DIR = $myenv.logdir
    $resultHash.env.HBASE_PID_DIR = $myenv.piddir

    $myenv.software.configContent.asHt("envvs").GetEnumerator() | Where-Object {$_.Key -notin "HBASE_LOG_DIR", "HBASE_PID_DIR"} | ForEach-Object {
        $resultHash.env[$_.Key] = $_.Value
    }

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.user -envfile $envfile -code $PSCommandPath) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile
}

function start-hbase {
    Param($myenv)
    expose-env $myenv
    $h = Get-HbaseDirInfomation $myenv
    if ("Master" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} start master" -f $h.hbaseDaemon,$h.hbaseConfDir) -user $myenv.user
    } elseif ("RegionServer" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} start regionserver" -f $h.hbaseDaemon,$h.hbaseConfDir) -user $myenv.user
    }
}

function stop-hbase {
    Param($myenv)
    expose-env $myenv
    $h = Get-HbaseDirInfomation $myenv
    if ("Master" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} master stop" -f $h.hbasebin,$h.hbaseConfDir) -user $myenv.user
    } elseif ("RegionServer" -in $myenv.myRoles) {
        Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} --config {1} regionserver stop" -f $h.hbasebin,$h.hbaseConfDir) -user $myenv.user
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

$myenv = New-EnvForExec $envfile | Decorate-Env

switch ($action) {
    "install" {
        Install-Hbase $myenv
    }
    "start-hbase" {
        start-hbase $myenv
    }
    "stop-hbase" {
        stop-hbase $myenv
    }
    "t" {
        # do nothing
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success
