# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [parameter(Mandatory=$true)]
    $action
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1


<#
XmlDocument doc = new XmlDocument();
doc.LoadXml("<book genre='novel' ISBN='1-861001-57-5'>" +
            "<title>Pride And Prejudice</title>" +
            "</book>");
#>
# doc.DocumentElement.AppendChild(elem);

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
    Param([xml]$doc, [System.Xml.XmlElement]$parent, [String]$name, $value, $descprition)
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
    $myenv
}

function Get-HadoopDirInfomation {
    Param($myenv)
    $h = @{}
    $h.hadoopDaemon=(Get-ChildItem $myenv.InstallDir -Recurse -Filter | Where-Object {($_.FullName -replace "\\", "/") -match "/sbin/hadoop-daemon.sh"}).FullName
    $h.etcHadoop = Join-Path -Path $h.hadoopDaemon -ChildPath "../etc/hadoop"
    $h.coreSite = Join-Path $h.etcHadoop -ChildPath "core-site.xml"
    $h.hdfsSite = Join-Path $h.etcHadoop -ChildPath "hdfs-site.xml"
    $h.yarnSite = Join-Path $h.etcHadoop -ChildPath "yarn-site.xml"
    $h.mapredSite = Join-Path $h.etcHadoop -ChildPath "mapred-site.xml"
    $h    
}

function Install-Hd {
    Param($myenv)
    if (!(Test-Path $myenv.InstallDir)) {
        New-Item -Path $myenv.InstallDir -ItemType Directory | Out-Null
    }

    $tgzFile = $myenv.getUploadedFile("hadoop-.*\.tar\.gz")
    if (Test-Path $tgzFile -PathType Leaf) {
        Run-Tar $tgzFile -DestFolder $myenv.InstallDir
    } else {
        return
    }
    $h = Get-HadoopDirInfomation -myenv $myenv

    [xml]$coreSiteDoc = Get-Content $h.coreSite


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
        Install-Hd $myenv
        break
    }
    default {
        Change-Status -myenv $myenv -action $action
    }
}

"@@success@@"
