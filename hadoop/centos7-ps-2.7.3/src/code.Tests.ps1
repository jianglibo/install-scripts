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

        $o.configuration | Should Be $true
        ($o.configuration.property | Where-Object Name -EQ "hadoop.tmp.dir").value = "/abc"

        $tf = New-TemporaryFile

        $o.Save($tf)
        # mata of xml should be remain.
        (Get-Content $tf | Out-String) -match "<\?xml-styleshee" | Should Be $true
        
        # value should be changed.
        (([xml](Get-Content $tf)).configuration.property | Where-Object Name -EQ "hadoop.tmp.dir").value | Should Be "/abc"
    }

    <#
    <?xml version="1.0" encoding="utf-8"?>
    <Racine>
    <Machine IP="128.200.1.1">
        Mach1<Adapters>Network</Adapters>
    </Machine>
    </Racine>
    #>
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
        Add-HadoopProperty -parent $configuration  -name "hadoop.common.configuration.version" -value 0.23.0 -descprition "version of this configuration file"
        $tf = New-TemporaryFile
        $xmlDoc.Save($tf)
        (Get-Content $tf | Out-String) -match "<name>hadoop\.common\.configuration\.version</name>" | Should Be $true
        Remove-Item -Path $tf

        [xml]$xmlDoc = @"
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
</configuration>
"@
        Add-HadoopProperty -doc $xmlDoc  -name "hadoop.common.configuration.version" -value 0.23.0 -descprition "version of this configuration file"
        $tf = New-TemporaryFile
        $xmlDoc.Save($tf)
        (Get-Content $tf | Out-String) -match "<name>hadoop\.common\.configuration\.version</name>" | Should Be $true
        Remove-Item -Path $tf
    }

    It "should handle core-site.xml" {
        $dxml = Join-Path -Path $here -ChildPath "../fixtures/etc/hadoop/core-site.xml"
        [xml]$o = Get-Content $dxml

        $o.configuration | Should Be $false

    }
}
