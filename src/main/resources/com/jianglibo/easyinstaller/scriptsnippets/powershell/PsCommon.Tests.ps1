# https://technet.microsoft.com/en-us/library/hh847828.aspx
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "PsCommon" {
    It "should handler Property" {
        $a = [PSCustomObject]@{a=1}
        $a.psobject.Properties | Where-Object MemberType -EQ "NoteProperty" | ForEach-Object {"{0}={1}" -f $_.Name, $_.Value} | Should Be "a=1"
    }
    It "should format string" {
        #place holder

        "{0}.{1}" -f "a","b" | Should Be "a.b"

        #currency
        ("{0:C2}" -f 181 | Out-String) -match ".{1}181\.00" | Should Be $True

        #Float
        "{0:F2}" -f 1.8292 | Should Be "1.83"

        #percent
        "{0:P}" -f 1.8292 | Should Be "182.92%"
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
        $fixture = Join-Path -Path $here -ChildPath "fixtures\envforcodeexec.json"
        $efe = New-EnvForExec $fixture

        $efe.jsonObj.getType().Name | Should  Be "pscustomobject"

        $efe.jsonObj.remoteFolder | Should  Be "/opt/easyinstaller"

        $p1 = $efe.jsonObj.remoteFolder | Join-Path -ChildPath "zookeeper-3.4.9.tar.gz"
        $efe.getUploadedFile() | Should Be $p1

        [Boolean]$efe.getUploadedFile("akb") | Should Be $False

        $p1 = $efe.jsonObj.remoteFolder | Join-Path -ChildPath "zookeeper-3.4.9.tar.gz"
        [Boolean]$efe.getUploadedFile("akb") | Should Be $False

        $efe.softwareConfig.jsonObj | Should Be $True

        $efe.softwareConfig.jsonObj.zkports | Should Be "2888,3888"

        #$efe.softwareConfig.asHt("zkconfig").getType() | Should Be System.Collections.Specialized.OrderedDictionary

        $ht = ([HashTable]$efe.softwareConfig.asHt("zkconfig"))
        $ht.initLimit | Should Be "5"
        $ht["initLimit"] | Should Be "5"
    }

    
    It "should swith right" {
        $v = "start"
        switch ("fourteen") 
            {
                1 {$v = "It is one."; Break}
                2 {$v = "It is two."; Break}
                3 {$v = "It is three."; Break}
                4 {$v = "It is four."; Break}
                3 {$v = "Three again."; Break}
                "fo*" {$v = "That's too many."}
            }
        $v | Should Be "start"

        switch -Regex ("fourteen") 
            {
                1 {$v = "It is one."; Break}
                2 {$v = "It is two."; Break}
                3 {$v = "It is three."; Break}
                4 {$v = "It is four."; Break}
                3 {$v = "Three again."; Break}
                "fo*" {$v = "That's too many."}
            }
        $v | Should Be "That's too many."
     }

     It "should save outVariable" {
        Write-Output "hello" -OutVariable ss
        Write-Output "hello" -OutVariable ss
        Write-Output "hello" -OutVariable ss
        $ss | Should Be "hello"

        Write-Output "hello" -OutVariable +ss
        Write-Output "hello" -OutVariable +ss
        Write-Output "hello" -OutVariable +ss

        $ss | Should Be @("hello", "hello", "hello", "hello")
    }
    It "should be run in linux" {
        $ep = "Variable:isLinux"
        if (Test-Path $ep) {
            if (Get-Item $ep) { "yes" }
        }
    }
    It "should create custom object" {
        $obj = [PSCustomObject]@{
            Property1 = 'one'
            Property2 = 'two'
            Property3 = 'three'
        }

        $obj | Get-Member | select -ExpandProperty TypeName|  Should Be "System.Management.Automation.PSCustomObject"

        $obj = New-Object PSObject
        Add-Member -InputObject $obj -MemberType NoteProperty -Name customproperty -Value ""

        $obj | Get-Member | select -ExpandProperty TypeName|  Should Be "System.Management.Automation.PSCustomObject"
    }
    It "should try catch error" {
        $w = try { nosenceword}  catch { "ehlo"}
        $w | Should Be "ehlo"
    }
    It "should all be false" {
        $(if ("") {"space"} else {"True"}) | Should Be "True"
        0 -eq $false | Should Be $True
        -not 0 | Should Be $True
        -not 1 | Should Be $False
        $true -eq 2 | Should Be $True
        2 -eq $true | Should Be $False
        -not "" | Should Be $True
        "" -eq $false | Should Be $False
        $false -eq "" | Should Be $True

    }

    It "is about function" {
    # https://technet.microsoft.com/en-us/library/hh847829.aspx
        function Get-Pipeline 
          { 
              process {"The value is: $_"} 
          }
       1,2,4 | Get-Pipeline | Write-Output -NoEnumerate | Should Be @("The value is: 1","The value is: 2","The value is: 4")

       $ov = 55
       function Use-var {
            process {$ov}
       }
       1,2,4 | Use-var | Should Be 55

        function Get-PipelineInput
          {
              process {"Processing:  $input " }
              end {"End:   The input is: $input" }
          }  

     1,2,4 | Get-PipelineInput | Select-Object -Last 1 | Should Be "End:   The input is: "
    }
}
