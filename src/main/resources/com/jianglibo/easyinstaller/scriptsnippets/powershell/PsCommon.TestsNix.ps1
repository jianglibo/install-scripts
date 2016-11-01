﻿$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.TestsNix\.', '.'
. "$here\$sut"

. "$here\Centos7Util.ps1"

Describe "PsCommon" {

    It "should save to xml" {
        [xml]$doc = "<a></a>"

        $tf = New-TemporaryFile
        Save-Xml -doc $doc -FilePath $tf -encoding ascii

        (Get-Content $tf) -match "<a>" | Should Be $True
        (Get-Content $tf) -match "utf-8" | Should Be $True
        (Get-Content $tf) -match "utf-16" | Should Be $null
        Remove-Item $tf
    }
}
