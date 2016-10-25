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
        systemctl status $serviceName | Select-Object -First 4 | Where-Object {$_ -match "\s+Active:.*\(running\)"}
    }
    $coul = $coul | Add-Member -MemberType ScriptMethod -Name isServiceRunning -Value $isServiceRunning -PassThru

    $isEnabled = {
        Param([parameter(Mandatory=$True)][String]$serviceName)
        systemctl is-enabled $serviceName | Where-Object {$_ -match "enabled"}
    }
    $coul = $coul | Add-Member -MemberType ScriptMethod -Name isEnabled -Value $isEnabled -PassThru

    return $coul
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