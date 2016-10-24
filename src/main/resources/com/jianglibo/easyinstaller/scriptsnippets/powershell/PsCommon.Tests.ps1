$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "PsCommon" {
    It "does something useful" {
        $true | Should Be $true
    }
    It "should handle out context" {
        $twoReached = $False
        (1,2,3 | ForEach-Object {if ($_ -gt 1) {$twoReached = $True; $_}} | ForEach-Object {if ($twoReached) {$_}}).Count | Should Be 2
    }
    It "scriptmethod parameters" {
        $oo = New-Object -TypeName PSObject
        $oo | Add-Member -MemberType ScriptMethod -Name appp -Value {
             Param([String]$fileToWrite)
             $fileToWrite
        }
        $oo.appp("abaac") | Should Be "abaac" 
    }
    It "should addKv commentKv work" {
        $kvf = New-SectionKvFile -FilePath (Join-Path $here -ChildPath "fixtures\NetworkManager.conf")
        $ht = [HashTable]$kvf.blockHt;

        $kvf.blockHt.Count | Should Be 2

        $kvf.blockHt["[main]"] -contains "plugins=ifcfg-rh" | Should Be $True

        $kvf.addKv("a", 1, "[main]")
        $kvf.blockHt["[main]"] -contains "a=1" | Should Be $True

        $kvf.blockHt["[main]"].Count | Should Be 3
        $kvf.addKv("a", 1, "[main]")
        $kvf.blockHt["[main]"].Count | Should Be 3

        $kvf.commentKv("x", "[main]")
        $kvf.blockHt["[main]"].Count | Should Be 3

        $kvf.commentKv("a", "[main]")
        $kvf.blockHt["[main]"] -contains "a=1" | Should Be $False
        $kvf.blockHt["[main]"] -contains "#a=1" | Should Be $True

        $kvf.addKv("a", 2, "[main]")
        $kvf.blockHt["[main]"] -contains "a=1" | Should Be $False
        $kvf.blockHt["[main]"] -contains "#a=1" | Should Be $False
        $kvf.blockHt["[main]"] -contains "a=2" | Should Be $True
        $kvf.blockHt["[main]"].Count | Should Be 3


    }
    It "should write to file work" {
        $kvf = New-SectionKvFile -FilePath (Join-Path $here -ChildPath "fixtures\NetworkManager.conf")
        $ht = [HashTable]$kvf.blockHt;
        $ht.Keys | Should Be @("[main]", "[logging]")

        ([Array]$kvf.prefix).Count| Should Be 12

        $tmpf = (New-TemporaryFile).ToString()

        $kvf.writeToFile($tmpf)

        $line2 = Get-Content $tmpf | Select-Object -First 2

        $line2 | Should Be @("# Configuration file for NetworkManager.", "#")
        Remove-Item -Path $tmpf
    }
}
