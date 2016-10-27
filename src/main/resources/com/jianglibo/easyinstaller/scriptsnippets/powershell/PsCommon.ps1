<#
tar (child): ./zookeeper-3.4.9.tar.gz1: Cannot open: No such file or directory
tar (child): Error is not recoverable: exiting now
/usr/bin/tar: Child returned status 2
/usr/bin/tar: Error is not recoverable: exiting now

zookeeper-3.4.9/zookeeper-3.4.9.jar.md5
/usr/bin/tar: zookeeper-3.4.9/zookeeper-3.4.9.jar.md5: Cannot open: File exists
/usr/bin/tar: zookeeper-3.4.9: Cannot utime: Operation not permitted
/usr/bin/tar: Exiting with failure status due to previous errors

https://blogs.technet.microsoft.com/heyscriptingguy/2014/03/30/understanding-streams-redirection-and-write-host-in-powershell/
#>
function Run-Tar {
 Param
     (
       [parameter(Position=0, Mandatory=$True)]
       [String]
       $TgzFileName,
       [parameter(Mandatory=$False)]
       [String]
       $DestFolder
    )
    if ($DestFolder) { # had destFolder parameter
        if (!(Test-Path $DestFolder)) { # if not exists.
#            if ((Get-Item $DestFolder).PSIsContainer) {
            New-Item $DestFolder -ItemType Directory | Out-Null
        }
    }
    $command = "tar -zxvf $TgzFileName $(if ($DestFolder) {`" -C $DestFolder`"} else {''}) *>&1"
    $r = $command | Invoke-Expression | Where-Object {$_ -cmatch "Cannot open:.*"} | measure
    if ($r.Count -gt 0) {$false} else {$True}
}

# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Networking_Guide/sec-Using_the_Command_Line_Interface.html
function New-IpUtil {

}

function New-CentOs7Nmcli {
 Param
     (
       [parameter(Mandatory=$False)]
       [Boolean]
       $EnableNetworkManager = $True,
       [parameter(Mandatory=$False)]
       [Boolean]
       $EnableDns = $False
    )
    $nm = New-Object -TypeName PSObject
    $d = [ordered]@{NetworkManagerEnabled=$EnableNetworkManager;DnsEnabled=$EnableDns}
    $nm = $nm | Add-Member -NotePropertyMembers $d -PassThru
    
    $nm = $nm | Add-Member -MemberType ScriptMethod -Name init -Value {
        if ($this.EnableNetworkManager) {
            systemctl enable NetworkManager
        } else {
            systemctl disable NetworkManager
        }
    } -PassThru

    return $nm
}

function New-OsUtil {
    Param([ValidateSet("centos","unbuntu")][parameter(Mandatory=$True)][String]$ostype="centos")
    
    switch ($ostype) {
        "centos" {New-CentOsUtil}
    }
}

function New-CentOsUtil {
    $coul = New-Object -TypeName PSObject

    $isServiceRunning = {
        Param([parameter(Mandatory=$True)][String]$serviceName)
        [Boolean](systemctl status $serviceName | Select-Object -First 4 | Where-Object {$_ -match "\s+Active:.*\(running\)"})
    }
    $coul = $coul | Add-Member -MemberType ScriptMethod -Name isServiceRunning -Value $isServiceRunning -PassThru

    $isEnabled = {
        Param([parameter(Mandatory=$True)][String]$serviceName)
        [Boolean](systemctl is-enabled $serviceName | Where-Object {$_ -match "enabled"})
    }
    $coul = $coul | Add-Member -MemberType ScriptMethod -Name isEnabled -Value $isEnabled -PassThru

    return $coul
}

function New-KvFile {
 Param
     (
       [parameter(Mandatory=$True)]
       [String]
       $FilePath,
       [parameter(Mandatory=$False)]
       [String]
       $commentPattern = "^\s*#.*"
    )

    $kvf = New-Object -TypeName PSObject -Property @{FilePath=$FilePath;lines=Get-Content $FilePath}

    $addKv = {
        param([String]$k, [String]$v)
        $done = $False
        $lines = $this.lines | ForEach-Object {
            if ($done) {
                $_
            } else {
                if (($_ -match "^\s*$k=") -or ($_ -match "${commentPattern}$k=")) {
                    $done = $True
                    "$k=$v"
                } else {
                    $_
                }
            }
        }

        if (!$done) {
            $lines += "$k=$v"
        }
        $this.lines = $lines
    }

    $kvf = $kvf | Add-Member -MemberType ScriptMethod -Name addKv -Value $addKv -PassThru

     $commentKv = {
        param([String]$k)
        $done = $False
        $lines = $this.lines | ForEach-Object {
            if ($done) {
                $_
            } else {
                if ($_ -match "^$k=") {
                    $done = $True
                    "#$_"
                } else {
                    $_
                }
            }
        }
        if ($done) { # if changed.
            $this.lines = $lines
        }
    }

    $kvf = $kvf | Add-Member -MemberType ScriptMethod -Name commentKv -Value $commentKv -PassThru

    $writeToFile = {
        param([parameter(Position=0,Mandatory=$False)][String]$fileToWrite)
        if (!$fileToWrite) {
            $fileToWrite = $this.FilePath
        }
        Set-Content -Path $fileToWrite -Value $this.lines
    }

    $kvf = $kvf | Add-Member -MemberType ScriptMethod -Name writeToFile -Value $writeToFile -PassThru

    return $kvf
}

function New-SoftwareConfig {
    Param([String]$scstr)
    $sc = New-Object -TypeName PSObject -Property @{jsonObj=ConvertFrom-Json $scstr}

    $sc = $sc | Add-Member -MemberType ScriptMethod -Name asHt -Value {
        Param([String]$pn)
        $tob = $this.jsonObj
        ($pn -split "\W+").ForEach({
            $tob = $tob.$_
        })
        if ($tob -is [PSCustomObject]) {
            $oht = [ordered]@{}
            $tob.psobject.Properties | Where-Object MemberType -eq "NoteProperty" | ForEach-Object {$oht[$_.name]=$_.value}
            $oht
        } else {
            $tob
        }
    } -PassThru
    $sc
}

function Insert-Lines {
    Param([String]$FilePath, [String]$ptn, $lines, [switch]$after)
    $content = Get-Content $FilePath | ForEach-Object {
        if ($_ -match $ptn) {
            if (! $after) {
                @() + $lines + $_
            } else {
                ,$_ + $lines
            }
        } else {
            $_
        }
    }

    Set-Content -Path $FilePath -Value $content
}


function New-EnvForExec {
 Param
     (
       [parameter(Mandatory=$True)]
       [String]$envfile)

    $efe = New-Object -TypeName PSObject -Property @{JsonObj=Get-Content $envfile | ConvertFrom-Json}

    $efe = $efe | Add-Member -MemberType NoteProperty -Name softwareConfig -Value (New-SoftwareConfig $efe.JsonObj.software.configContent)  -PassThru

    if (! (Test-Path $efe.JsonObj.remoteFolder)) {
        New-Item -ItemType Directory $efe.JsonObj.remoteFolder
    }

    $efe = $efe | Add-Member -MemberType ScriptMethod -Name getUploadedFile -Value {
        Param([String]$ptn, [Boolean]$onlyName=$False)

        $allfns = $this.jsonObj.software.filesToUpload
        if ($allfns) {
            if($ptn) {
                $fullfn = $allfns | Where-Object {$_ -match $ptn}| Select-Object -First 1
            } else {
                $fullfn = $allfns | Select-Object -First 1
            }
            if ($fullfn) {
                $fn = $fullfn -split "/" | Select-Object -Last 1
                if ($onlyName) {
                    $fn
                } else {
                    $this.jsonObj.remoteFolder | Join-Path -ChildPath $fn
                }
            }
        }
    } -PassThru
    $efe
}


function New-HostsFile {
 Param
     (
       [parameter(Mandatory=$False)]
       [String]
       $FilePath = "/etc/hosts"
    )
    $hf = New-Object -TypeName PSObject -Property @{FilePath=$FilePath;lines=Get-Content $FilePath}

    $hf = $hf | Add-Member -MemberType ScriptMethod -Name addHost -Value {
        Param([parameter(Mandatory=$True)][String]$ip, [parameter(Mandatory=$True)][String]$hn)
        $done = $False
        $this.lines = $this.lines | Select-Object @{N="parts";E={$_ -split "\s+"}} | Where-Object {$_.parts.Length -gt 0} | ForEach-Object {
            if($done) {
               return $_
            }
            if($_.parts[0] -eq $ip) {
                if ($_.parts -notcontains $hn){
                    $_.parts += $hn
                }
                $done = $True
            }
            $_
        } | Select-Object @{N="line"; E={$_.parts -join " "}} | Select-Object -ExpandProperty line
        if (!$done) {
            $this.lines += "$ip $hn"
        }
    } -PassThru


     $hf | Add-Member -MemberType ScriptMethod -Name writeToFile -Value {
        Param([parameter(Position=0,Mandatory=$False)][String]$fileToWrite)
        if (!$fileToWrite) {
            $fileToWrite = $this.FilePath
        }
        Set-Content -Path $fileToWrite -Value $this.lines
    } -PassThru
}

function New-SectionKvFile {
 Param
     (
       [parameter(Mandatory=$True)]
       [String]
       $FilePath,
       [parameter(Mandatory=$False)]
       [String]
       $SectionPattern = "^\[(.*)\]$",
       [parameter(Mandatory=$False)]
       [String]
       $commentPattern = "^#.*"
    )

    $prefix = @()
    $blockHt = [ordered]@{}
    $blockStart = $False
    $currentBlock = $null

    Get-Content $FilePath | ForEach-Object {
        if ($blockStart) {
            if ($_ -match $SectionPattern) {
                $currentBlock = $Matches[0]
                $blockHt[$currentBlock] = @()
            } else {
                $blockHt[$currentBlock] += $_
            }
        } else {
            if ($_ -match $SectionPattern) {
                $blockStart = $True
                $currentBlock = $Matches[0]
                $blockHt[$currentBlock] = @()
            }  else {
                $prefix += $_
            }
        }
    }

    $skf = New-Object -TypeName PSObject -Property @{FilePath=$FilePath;blockHt=$blockHt;prefix=$prefix}

    $addKv = {
        param([String]$k, [String]$v, [String]$section)
        $done = $False
        $blockLines = $this.blockHt[$section] | ForEach-Object {
            if ($done) {
                $_
            } else {
                if ($_ -match "$k=") {
                    $done = $True
                    "$k=$v"
                } else {
                    $_
                }
            }
        }

        if (!$done) {
            $blockLines += "$k=$v"
        }
        $this.blockHt[$section] = $blockLines
    }

    $skf = $skf | Add-Member -MemberType ScriptMethod -Name addKv -Value $addKv -PassThru

     $commentKv = {
        param([String]$k, [String]$section)
        $done = $False
        $blockLines = $this.blockHt[$section] | ForEach-Object {
            if ($done) {
                $_
            } else {
                if ($_ -match "^$k=") {
                    $done = $True
                    "#$_"
                } else {
                    $_
                }
            }
        }
        if ($done) { # if changed.
            $this.blockHt[$section] = $blockLines
        }
    }

    $skf = $skf | Add-Member -MemberType ScriptMethod -Name commentKv -Value $commentKv -PassThru

    $writeToFile = {
        param([parameter(Position=0,Mandatory=$False)][String]$fileToWrite)
        if (!$fileToWrite) {
            $fileToWrite = $this.FilePath
        }
        $lines = $this.prefix
        ([HashTable]$this.blockHt).GetEnumerator().ForEach({
            $lines += $_.Key
            $lines += $_.Value
        })
        Set-Content -Path $fileToWrite -Value $lines
    }

    $skf = $skf | Add-Member -MemberType ScriptMethod -Name writeToFile -Value $writeToFile -PassThru

    return $skf
}

# "1", "2" | Select-Object @{N="line"; E={$_}}, @{N="sstart"; E={$_ -eq "1"}}