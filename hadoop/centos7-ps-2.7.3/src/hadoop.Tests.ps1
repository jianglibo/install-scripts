﻿$here = Split-Path -Parent $MyInvocation.MyCommand.Path
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

        $myenv.InstallDir | Should Be "/opt/hadoop"

        ($myenv.software.configContent.asHt("envvs").GetEnumerator() | measure).Count | Should Be 3

        $tgzFile = Join-Path $here -ChildPath "../../../tgzFolder/hadoop-2.7.3.tar.gz"

        Test-Path $tgzFile -PathType Leaf | Should Be $True

        $myenv.getUploadedFile("hadoop-.*\.tar\.gz") | Should Be "/opt/easyinstaller/hadoop-2.7.3.tar.gz"
        $myenv.tgzFile = $tgzFile

        ($myenv.software.textfiles).length | Should Be 30

        $DirInfo = Get-HadoopDirInfomation -myenv $myenv

        $DirInfo.hadoopDir | Should Be "/opt/hadoop/hadoop-2.7.3"

        # all name should start with etc
        ($myenv.software.textfiles | Where-Object {$_.name -match "^etc/"}).Count | Should Be $myenv.software.textfiles.length

#        $hdfssite = $myenv.software.textfiles | Where-Object name -Like "*hdfs-site.xml"
#        $hdfssite.content | Should Be "abc"
#        [xml]$hdfssite.configuration | Should Be $True
        
#        Test-Path -Path  $hdfssite.name | Should Be $True

#        $myenv.software.configContent.coreSite | Select-Object -ExpandProperty Name | Write-Output -OutVariable +snames

#        $snames -contains "fs.defaultFS" | Should Be $true
#        $snames -contains "io.file.buffer.size" | Should Be $true

        Install-Hadoop $myenv

        $di = Get-HadoopDirInfomation $myenv
        $coreSite =  Get-Item $di.coreSite
        $hdfsSite = Get-Item $di.hdfsSite
        $yarnSite = Get-Item $di.yarnSite
        $mapredSite = Get-Item $di.mapredSite

    
        [xml]$coreSiteDoc = Get-Content $coreSite

        $pnames = $coreSiteDoc.configuration.property | Select-Object -ExpandProperty Name | Write-Output -NoEnumerate

        $pnames | Should Be "fs.defaultFS", "io.file.buffer.size"

        Get-Content -Path "env:ABC" | Should Be "uvw"

    }
}