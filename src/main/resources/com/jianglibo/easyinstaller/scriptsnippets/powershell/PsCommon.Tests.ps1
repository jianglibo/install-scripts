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
    It "should run string" {
        Invoke-StringCode -execute tclsh -content 'puts "abc"' | Should Be "abc"
        $c = @'
        set n [expr 1 + 1]
        puts $n
'@
    Invoke-StringCode -execute tclsh -content $c | Should Be "2"
    }
    It "should alter resultFile" {
        $tmp = New-TemporaryFile
        "{}" | Out-File -FilePath $tmp -Encoding ascii
        Set-ResultFileItem -resultFile $tmp -keys a,b,c -value 55
        $rh = Get-Content $tmp | ConvertFrom-Json
        $rh.a.b.c | Should Be 55
        $rh.value | Should Be $null

        "{}" | Out-File -FilePath $tmp -Encoding ascii
        Set-ResultFileItem -resultFile $tmp -keys a 55
        $rh = Get-Content $tmp | ConvertFrom-Json
        $rh.a | Should Be 55

        "{}" | Out-File -FilePath $tmp -Encoding ascii
        Set-ResultFileItem -resultFile $tmp -keys a 55
        $rh = Get-Content $tmp | ConvertFrom-Json
        $rh.a | Should Be 55

        "" | Out-File -FilePath $tmp -Encoding ascii
        Set-ResultFileItem -resultFile $tmp -keys a 55
        $rh = Get-Content $tmp | ConvertFrom-Json
        $rh.a | Should Be 55

#        "" | Out-File -FilePath notexistsfile -Encoding ascii
        Set-ResultFileItem -resultFile $tmp -keys a 55
        $rh = Get-Content $tmp | ConvertFrom-Json
        $rh.a | Should Be 55
        $rh.value | Should Be $null
        Remove-Item $tmp -Force
    }
    It "should addKv commentKv work" {
        $kvf = New-SectionKvFile -FilePath (Join-Path $here -ChildPath "fixtures\NetworkManager.conf")
        $ht = [HashTable]$kvf.blockHt;

        $kvf.blockHt.Count | Should Be 2

        $mains = "[main]";

        $kvf.blockHt[$mains] -contains "plugins=ifcfg-rh" | Should Be $True

        $kvf.addKv("a", 1, $mains)
        $kvf.blockHt[$mains] -contains "a=1" | Should Be $True

        $kvf.blockHt[$mains].Count | Should Be 3
        $kvf.addKv("a", 1, $mains)
        $kvf.blockHt[$mains].Count | Should Be 3

        $kvf.commentKv("x", $mains)
        $kvf.blockHt[$mains].Count | Should Be 3

        $kvf.commentKv("a", $mains)
        $kvf.blockHt[$mains] -contains "a=1" | Should Be $False
        $kvf.blockHt[$mains] -contains "#a=1" | Should Be $True

        $kvf.addKv("a", 2, $mains)
        $kvf.blockHt[$mains] -contains "a=1" | Should Be $False
        $kvf.blockHt[$mains] -contains "#a=1" | Should Be $False
        $kvf.blockHt[$mains] -contains "a=2" | Should Be $True
        $kvf.blockHt[$mains].Count | Should Be 3

        Add-SectionKv -parsedSectionFile $kvf -section $mains -key "uuu" -value "xxx"

        $kvf.blockHt[$mains].Count | Should Be 4
        Disable-SectionKeyValue -parsedSectionFile $kvf -section $mains -key "uuu"
        $kvf.blockHt[$mains].Count | Should Be 4
        Get-SectionValueByKey -parsedSectionFile $kvf -section $mains -key "uuu" | Should Be $null

        Add-SectionKv -parsedSectionFile $kvf -section $mains -key "uuu"
        $kvf.blockHt[$mains].Count | Should Be 4
        Get-SectionValueByKey -parsedSectionFile $kvf -section $mains -key "uuu" | Should Be "xxx"

        Disable-SectionKeyValue -parsedSectionFile $kvf -section $mains -key "notexists"
        $kvf.blockHt[$mains].Count | Should Be 4
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

    It "should handle ip addr" {
        $ipaddrout = Join-Path -Path $here -ChildPath "fixtures\ipaddr.txt"
        (Get-Content $ipaddrout | ForEach-Object -Begin {$curg = $null} -Process {
            if($_ -match "^\d+:\s*(\w+):") {
                $curg = $Matches[1]
            }
            @{gp=$curg;value=$_}
        } -End {$ht} | Group-Object -AsHashTable -AsString -Property {$_["gp"]}).Count | Should Be 3
    }

    It "can handle kvFile" {
        $cf = Join-Path -Path $here -ChildPath "fixtures\dnsmasq.conf"
        $kvf = New-KvFile -FilePath $cf
        Test-Path $cf | Should Be $True
        ($kvf.lines).count | Should Be 666

        $kvf.addKv("a", "b")
        ($kvf.lines).count | Should Be 667

        $kvf.commentKv("a");
        ($kvf.lines).count | Should Be 667

        ($kvf.lines | Where-Object {$_ -eq "#a=b"}).count | Should Be 1
    }

    It "Should handle select object" {
        1,2,3 | Select-Object @{N="k";E={$_ + 1}} | Select-Object -ExpandProperty k | Write-Output -NoEnumerate | Should Be @(2,3,4)
    }

    It "should handle addHost" {
        $fixture = Join-Path -Path $here -ChildPath "fixtures\hosts"
        $hf = New-HostsFile -FilePath $fixture
        $hf.FilePath -cmatch "hosts$" | Should Be $True
        $hf.lines.count | Should Be 2

        $hf.addHost("192.168.33.10", "hello.cc")
        $hf.lines.count | Should Be 3
        $hf.addHost("192.168.33.10", "hello.cc")
        $hf.lines.count | Should Be 3

        $hf.lines | Select-String -Pattern "\s+hello.cc" | Write-Output -NoEnumerate | Should Be @("192.168.33.10 hello.cc")

        $hf.addHost("192.168.33.10", "hello.dd")
        $hf.lines | Select-String -Pattern "\s+hello.cc" | Write-Output -NoEnumerate | Should Be @("192.168.33.10 hello.cc hello.dd")

        $hf.addHost("192.168.33.10", "hello.dd").addHost("192.168.33.10", "hello.dd").addHost("192.168.33.10", "hello.dd")
        $hf.lines | Select-String -Pattern "\s+hello.cc" | Write-Output -NoEnumerate | Should Be @("192.168.33.10 hello.cc hello.dd")
    }

    It "should handle varagrs" {
        function t-f {
            Param($ports)
            if ($ports -is [String]) {
                $ports = $ports -split "[^\d]+"
            }
            $ports -join ","
        }

        t-f "1,2,3" | Should Be "1,2,3"
        t-f 1,2,3 | Should Be "1,2,3"
        t-f "1.2.3" | Should Be "1,2,3"
    }

    It "should handle envforexec" {
        $fixture = Join-Path -Path $here -ChildPath "fixtures/envforcodeexec.json"
        $efe = New-EnvForExec $fixture
        $efe.getType().Name | Write-Host
        $efe.getType().Name | Should  Be "pscustomobject"

        $efe.remoteFolder | Should  Be "/opt/easyinstaller"

        $p1 = $efe.remoteFolder | Join-Path -ChildPath "zookeeper-3.4.9.tar.gz"

        $efe.getUploadedFile() | Should Be $p1

        [Boolean]$efe.getUploadedFile("akb") | Should Be $False

        $p1 = $efe.remoteFolder | Join-Path -ChildPath "zookeeper-3.4.9.tar.gz"
        [Boolean]$efe.getUploadedFile("akb") | Should Be $False

        $efe.software.configContent | Should Be $True

        $efe.software.configContent.zkports | Should Be "2888,3888"

        $kvary = ([HashTable]$efe.software.configContent.asHt("zkconfig")).GetEnumerator() | ForEach-Object {"{0}={1}" -f $_.Key, $_.Value}

        $kvary -contains "initLimit=5" | Should Be $True

        $efe.software.fullName | Should Be "zookeeper-CentOs7-3.4.9"

        $efe.resultFolder -replace "\\","/" | Should Be "/opt/easyinstaller/results/zookeeper-CentOs7-3.4.9"

        Test-Path $efe.resultFolder  -PathType Container | Should Be $True

    }

    It "should inert a line" {
        $tmp = New-TemporaryFile

        Set-Content -Path $tmp -Value 'a', 'ZOOBINDIR="${ZOOBINDIR:-/usr/bin}"', 'b', 'c'

        (Get-Content $tmp).Count | Should Be 4

        Add-Lines $tmp "^ZOOBINDIR=" "hello"
        $c = Get-Content $tmp
        $c[1] | Should Be "hello"
        $c.Count | Should Be 5

        Test-Path ($tmp.FullName + ".origin") -PathType Leaf | Should Be $True

        Set-Content -Path $tmp -Value 'a', 'ZOOBINDIR="${ZOOBINDIR:-/usr/bin}"', 'b', 'c'
        Add-Lines -FilePath $tmp "^ZOOBINDIR=" -lines "hello","1","2" -after
        $c = Get-Content $tmp
        $c[2] | Should Be "hello"
        $c.Count | Should Be 7

        Remove-Item $tmp
    }

    It "about replace" {
        "abc" -replace "a","b" | Should Be "bbc"
        "0ab1c2" -replace "[a-z]+","b" | Should Be "0b1b2"
    }

    It "should by reference" {
        function t-t {
            Param($ht)
            $ht.newkey = "123"
        }

        $outht = @{x=5}
        t-t $outht

        $outht.newkey | Should Be "123"
    }

    It "should Out-File work" {
        $t = New-TemporaryFile
        @(1,2,3) | Out-File -FilePath $t
        Get-Content $t | Write-Output -NoEnumerate | Should Be @(1,2,3)
    }

    It "is more about function" {
        function Get-Pipeline {
          process {"The value is: $_"}
        }
        1,2 | Get-Pipeline |Write-Output -NoEnumerate| Should Be @("The value is: 1", "The value is: 2")

        function Get-PipelineBeginEnd {
          begin {"Begin: The input is $input"}
          end {"End:   The input is $input" }
       }

       1,2 | Get-PipelineBeginEnd | Write-Output -NoEnumerate | Should Be @("Begin: The input is ","End:   The input is 1 2")
    }

    It "should handle remain args" {
        function t-t {
            Param([int]$i, [string]$s, [parameter(ValueFromRemainingArguments)]$others)
            $others
        }

        (t-t 1 "s" 1 2 3 4).length | Should Be 4
        (t-t 1 "s" 1 2 3 4).getType() | Should Be "System.Object[]"
        (t-t 1 "s" 1,2,3,4).length | Should Be 4
        (t-t 1 "s" 1,2,3,4).getType() | Should Be "System.Object[]"
    }

    It "handle new-ExecuteLine" {
        New-ExecuteLine "bash" -envfile "/abcc" | Should Be 'bash /abcc -envfile /abcc -action $1'
        New-ExecuteLine "powershell -File {code} -envfile {envfile} -action {action}" -envfile "/abcc.Ps1.env" | Should Be 'powershell -File /abcc.Ps1 -envfile /abcc.Ps1.env -action $1'

        New-ExecuteLine "bash" -envfile "/abcc" -code "/abcccode" | Should Be 'bash /abcccode -envfile /abcc -action $1'
        New-ExecuteLine "powershell -File {code} -envfile {envfile} -action {action}" -envfile "/abcc.Ps1.env" -code "/abcccode.Ps1" | Should Be 'powershell -File /abcccode.Ps1 -envfile /abcc.Ps1.env -action $1'

    }

    It "shoud split coloncomma" {
        Parse-RunAs -content "" | Should Be ""
        Parse-RunAs -content "a" | Should Be "a"

        (Parse-RunAs -content "a:").Count | Should Be 1
        (Parse-RunAs -content "a:").a | Should Be ""

        (Parse-RunAs -content "a:b").Count | Should Be 1
        (Parse-RunAs -content "a:b").a | Should Be "b"

        (Parse-RunAs -content "a:b,c:d").Count | Should Be 2
        (Parse-RunAs -content "a:b,c:d").a | Should Be "b"
        (Parse-RunAs -content "a:b,c:d").c | Should Be "d"

        ("a:b,c:d" | Parse-RunAs).c | Should Be "d"
    }

    It "should handle write-textfile" {
        $tmp = New-TemporaryFile
        $myf = $tmp | Split-Path -Parent | Join-Path -ChildPath "hello"

        # out-file will auto append newline.
        "a","b","c" | Out-File -FilePath $myf
        (Get-Content -Path $myf | Measure-Object).Count | Should Be 3
        (Get-Content -Path $myf) -join "," | Should Be "a,b,c"

        # out-file will auto append newline.
        "a","b","c" | Out-File -FilePath $myf -NoNewline
        (Get-Content -Path $myf | Measure-Object).Count | Should Be 1
        (Get-Content -Path $myf) -join "," | Should Be "abc"

        # if inputobject is a string contains newline, even there is -NoNewline option, newline in the string is still keeped.
         "a`rb`rc" | Out-File -FilePath $myf -NoNewline
        (Get-Content -Path $myf | Measure-Object).Count | Should Be 3
        (Get-Content -Path $myf) -join "," | Should Be "a,b,c"

        [PSCustomObject]@{name=$myf;content="abc"} | Write-TextFile
        Get-Content -Path $myf | Write-Output -NoEnumerate | Should Be "abc"

        [PSCustomObject]@{name=$myf;content="abc`r`nde`tf"} | Write-TextFile
        (Get-Content -Path $myf | Measure-Object).Count  |  Should Be 2
        (Get-Content -Path $myf)[0] | Should Be "abc"

        Remove-Item $tmp
        Remove-Item $myf
    }

    It "should handle newline" {
        $abc = Join-Path $here -ChildPath "fixtures\abc.txt"
        (Get-Content $abc).GetType() | Should Be "System.Object[]"
        "abc`ndef".GetType() | Should Be "string"

        ("abc`r`ndef" | ForEach-Object {$_}).getType() | Should Be "string"
        ("abc\r\ndef" | ForEach-Object {$_}).getType() | Should Be "string"

        ("abc`rabc`r`nabc`n" -split '\r?\n|\r\n?').Length | Should Be 4
    }

    It "should test absolute path" {
        "abc" | Test-AbsolutePath | Should Be $False

        "/abc" | Test-AbsolutePath | Should Be $True

        "c:\abc" | Test-AbsolutePath | Should Be $True
    }

    It "should handle varargs" {
        $r = Select-FirstTrueValue "" $False $null 1 | Should Be 1
        $r = Select-FirstTrueValue "" $False $null 0 | Should Be $Null

        Select-IfElse -condition "" "a" "b" | Should Be "b"

        Select-IfElse -condition 1 "a" "b" | Should Be "a"

        Select-IfElse -condition 0 "a" "b" | Should Be "b"
    }

    It "should parse return value" {

    $c = @"
    a
        ------RETURN_TO_CLIENT_BEGIN------xs
        {
            "h": {
                b: 55
            }

        }

        uv------RETURN_TO_CLIENT_END------
    b
"@
    $v =  $c | ConvertFrom-ReturnToClientInstallResult
    $v | Write-Host
    $v.h.b | Should Be 55
    }

    It "should equal array" {
        1,2,3 | Should Be 3,1,2
    }
}
