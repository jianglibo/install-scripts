$ErrorActionPreference = "Stop"

$R_T_C_B = "------RETURN_TO_CLIENT_BEGIN------"
$R_T_C_E = "------RETURN_TO_CLIENT_END------"

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

function Parse-Parameters {
    Param([parameter(ValueFromPipeline=$True)]$parastr)
    $mayBeJsonSting = Decode-Base64 -base64Str $parastr
    try {
        $mayBeJsonSting | ConvertFrom-Json -ErrorAction SilentlyContinue -OutVariable mayBeJson | Out-Null
        $mayBeJson
    }
    catch {
        $Error.Clear()
        Write-Output $mayBeJsonSting
    }
}

function Alter-ResultFile {
    Param([parameter(Mandatory=$True)][string]$resultFile,[parameter(Mandatory=$True)][array]$keys, $value)
    $rh = Get-Content $resultFile | ConvertFrom-Json
    if (!$rh) {
        $rh = New-Object -TypeName psobject
    }
    $parent = $rh
    $leaf = $null

    $keysNoLast = $keys | Select-Object -SkipLast 1
    $lastKey = $keys | Select-Object -Last 1
    
    if ($keysNoLast) {
        foreach ($k in $keysNoLast) {
            $leaf = $parent.$k
            if ($leaf) {
                if ($leaf -isnot [psobject]) {
                    Write-Error "leaf item is not a psobject: $keys"
                }
            } else {
                $o = New-Object -TypeName psobject
                $parent = $parent | Add-Member -MemberType NoteProperty -Name $k -Value $o -PassThru
                $leaf = $parent.$k
            }
            $parent = $leaf
        }
    }
    if (!$leaf) {
        $leaf = $rh
    }
    if ($leaf | Get-Member | ? Name -EQ $lastKey) {
        $leaf.$lastKey = $value
    } else {
        $leaf | Add-Member -MemberType NoteProperty -Name $lastKey -Value $value
    }

    $rh | ConvertTo-Json | Out-File $resultFile -Force -Encoding ascii
}

function Encode-Base64 {
    Param([string]$str)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($str)
    [System.Convert]::ToBase64String($bytes)
}

function Decode-Base64 {
    Param([string]$base64Str)
    $bytes = [System.Convert]::FromBase64String($base64Str)
    [System.Text.Encoding]::ASCII.GetString($bytes)
}

function Quota-Quota {
    Param([string]$quotaChar, [switch]$quotaInnerQuota,[parameter(ValueFromRemainingArguments=$True)]$others)
    if ($quotaChar -eq "'") {
        if ($quotaInnerQuota) {
            $others = $others | % {"'" + ($_ -replace "'","'`"'`"'") + "'"}
        } else {
            $others = $others | % {"'" + $_ + "'"}
        }
    } elseif ($quotaChar -eq '"') {
        if ($quotaInnerQuota) {
            $others = $others | % {'"' + ($_ -replace '"',"`"'`"'`"") + '"'}
        } else {
            $others = $others | % {'"' + $_ + '"'}
        }
    }
    $others
}

function Write-HostIfInTesting {
    Param([parameter(ValueFromPipeline=$True)]$messageToWrite)
    if ($I_AM_IN_TESTING) {
        $messageToWrite | Write-Host
    }
}

function Write-OutputIfTesting {
    Param([parameter(ValueFromPipeline=$True)]$messageToWrite)
    if ($I_AM_IN_TESTING) {
        $messageToWrite
    }
}

function Run-Tcl {
    Param([parameter(ValueFromPipeline=$True)]$content,[parameter(ValueFromRemainingArguments=$True)]$others)
    begin {
        $lines = @()
    }
    process {
        $lines += $content
    }
    end {
        $tf = (New-TemporaryFile).FullName
        $lines | Out-File -FilePath $tf -Encoding ascii
        $others = $others | % {"'" + (Encode-Base64 $_) + "'"}
        ("tclsh",$tf + $others) -join " " | Write-HostIfInTesting
        ("tclsh",$tf + $others) -join " " | Invoke-Expression *>&1
        Remove-Item -Path $tf
    }
}

function Run-String {
    Param([string]$execute, [parameter(ValueFromPipeline=$True)]$content,[string]$quotaChar,[switch]$quotaInnerQuota, [parameter(ValueFromRemainingArguments=$True)]$others)
    $tf = (New-TemporaryFile).FullName

    $content | Out-File -FilePath $tf -Encoding ascii
    $others = Quota-Quota -quotaChar $quotaChar -quotaInnerQuota $quotaInnerQuota @others
    ($execute,$tf + $others) -join " " | Write-Host
    ($execute,$tf + $others) -join " " | Invoke-Expression
    Remove-Item -Path $tf
}

function Detect-RunningYum {
    if (Get-Process | ? Name -EQ yum) {
        Write-Error "Another yum are running, Please wait for it's completion"
    }
}

function Save-Xml {
    Param([xml]$doc, $FilePath, $encoding="ascii")
    $sw = New-Object System.IO.StringWriter
    $doc.Save($sw)
    $sw.ToString() -replace "utf-16", "utf-8" | Out-File -FilePath $FilePath -Encoding $encoding
}

# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Networking_Guide/sec-Using_the_Command_Line_Interface.html
function New-IpUtil {

}

function Insert-Lines {
    Param([String]$FilePath, [String]$ptn, $lines, [switch]$after)
    if ($FilePath -is [System.IO.FileInfo]) {
        $FilePath = $FilePath.FullName
    }
    $bkFile = $FilePath + ".origin"
    if (! (Test-Path $bkFile)) {
        Copy-Item $FilePath -Destination $bkFile
    }
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

function New-ExecuteLine {
    Param([parameter(Mandatory=$True)][String]$runner, [parameter(Mandatory=$True)][String]$envfile, $code)
    if (! $code) {
        $code = $envfile -replace "\.env$",""
    }
    if ($runner -cmatch "(\{code\}|\{envfile\}|\{action\})") {
        $r = $runner -replace "\{code\}",$code
        $r = $r -replace "\{envfile\}",$envfile
        $r -replace "\{action\}",'$1'
    } else {
        $runner, $code, "-envfile", $envfile, "-action", '$1' -join " "
    }
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

    $kvf | Add-Member -MemberType ScriptMethod -Name addKv -Value $addKv

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

    $kvf | Add-Member -MemberType ScriptMethod -Name commentKv -Value $commentKv

    $writeToFile = {
        param([parameter(Position=0,Mandatory=$False)][String]$fileToWrite)
        if (!$fileToWrite) {
            $fileToWrite = $this.FilePath
        }
        Set-Content -Path $fileToWrite -Value $this.lines
    }

    $kvf | Add-Member -MemberType ScriptMethod -Name writeToFile -Value $writeToFile -PassThru
}
# add asHt method to object, allow this object has the ability to covert one of decendant object to a hashtable, So program can iterate over it.
# for example, $a.asHt("x.y.z") will convert $a.x.y.z to a hashtable.

function Add-AsHtScriptMethod {
    Param([parameter(ValueFromPipeline=$True)]$pscustomob)
    $pscustomob | Add-Member -MemberType ScriptMethod -Name asHt -Value {
        Param([String]$pn)
        $tob = $this
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
}

function Get-RandomPassword {
    Param([int]$minLength=8,[int]$maxLength=32, [int]$len)
    if ($len -gt 0) {
        $num = $len
    } else {
        $num = Get-Random -Minimum $minLength -Maximum $maxLength
    }
    $tmp= foreach ($i in 1..$num) {
        $g = ('abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ23456789!"#%&','abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '23456789', '!"#%&+')[(Get-Random 5)]
        $g[(Get-Random $g.Length)]
    }
    $tmp -join ""
}

function Get-BoxRoleConfig {
    Param([parameter(Mandatory=$True)]$myenv,[parameter(ValueFromRemainingArguments)]$remainingArguments)
    $o = $null
    if ($remainingArguments -and ($remainingArguments.Count -gt 0) -and $myenv.box.boxRoleConfig) {
        foreach ($p in $remainingArguments) {
            $o = $myenv.box.boxRoleConfig.$p
            if (! $o) {
                break
            }
        }
    }
    $o
}

function New-EnvForExec {
    Param([parameter(Mandatory=$True)][String]$envfile)
    $efe = Get-Content $envfile | ConvertFrom-Json

    $efe.software.configContent = $efe.software.configContent | ConvertFrom-Json

    $efe.software.runas = $efe.software.runas | Split-ColonComma

    if (! $efe.software.runas) {
        $efe.software.runas = $env:USER
    }

    $efe.software | Add-Member -MemberType ScriptProperty -Name fullName -Value {
        "{0}-{1}-{2}" -f $this.name,$this.ostype,$this.sversion
    }

    Add-AsHtScriptMethod $efe.software.configContent | Out-Null

    $efe | Add-Member -MemberType NoteProperty -Name resultFolder -Value ($efe.remoteFolder | Join-Path -ChildPath "results" | Join-Path -ChildPath $efe.software.fullName)

    $efe | Add-Member -MemberType NoteProperty -Name resultFile -Value ($efe.resultFolder | Join-Path -ChildPath "easyinstaller-result.json")
    $efe | Add-Member -MemberType NoteProperty -Name appFile -Value ($efe.resultFolder | Join-Path -ChildPath "app.sh")

    $efe | Add-Member -MemberType NoteProperty -Name myRoles -Value (($efe.box.roles | Trim-All) -split ',')

    if (! (Test-Path $efe.remoteFolder)) {
        New-Item -ItemType Directory $efe.remoteFolder
    }

    if (! (Test-Path $efe.resultFolder)) {
        New-Item -ItemType Directory $efe.resultFolder
    }

    $efe | Add-Member -MemberType ScriptMethod -Name getUploadedFile -Value {
        Param([String]$ptn, [switch]$OnlyName)

        $allfns = $this.software.filesToUpload
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
                    $this.remoteFolder | Join-Path -ChildPath $fn
                }
            }
        }
    } -PassThru
}

function Get-UploadFiles {
    Param([parameter(Mandatory=$True)]$myenv,[string]$ptn, [switch]$OnlyName)
    $allfns = $myenv.software.filesToUpload
    if ($allfns) {
        if($ptn) {
            $fullfns = $allfns | Where-Object {$_ -match $ptn}
        } else {
            $fullfns = $allfns
        }
        $fullfns | % {$_ -split '/' | Select-Object -Last 1} | % {if($OnlyName) {$_} else {$myenv.remoteFolder | Join-Path -ChildPath $_}}
    }
}

function New-HostsFile {
 Param
     (
       [parameter(Mandatory=$False)]
       [String]
       $FilePath = "/etc/hosts"
    )
    $hf = New-Object -TypeName PSObject -Property @{FilePath=$FilePath;lines=Get-Content $FilePath}

    $hf | Add-Member -MemberType ScriptMethod -Name addHost -Value {
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
        $this
    }

    $hf | Add-Member -MemberType ScriptMethod -Name writeToFile -Value {
        Param([parameter(Position=0,Mandatory=$False)][String]$fileToWrite)
        if (!$fileToWrite) {
            $fileToWrite = $this.FilePath
        }
        Set-Content -Path $fileToWrite -Value $this.lines
    }

    $hf
}

<#
function New-RandomPassword {
    Param([parameter(ValueFromPipeline=$True)][int]$Count=8)
    (0x20..0x7e | ForEach-Object {[char]$_} | Get-Random -Count $Count) -join ""
}
#>

function Add-SectionKv {
    Param([parameter(Mandatory=$True)]$parsedSectionFile,[parameter(Mandatory=$True)][string]$section, [parameter(Mandatory=$True)][string]$key, $value)
    $done = $False
    $blockLines = $parsedSectionFile.blockHt[$section] | ForEach-Object {
        if ($done) {
            $_
        } else {
            if ($_ -match "${key}=") {
                $done = $True
                if ($value) {
                    "${key}=$value"
                } else {
                    $m = $_ -match "^\s*#+\s*(.*)\s*$"
                    if ($m) {
                        $Matches[1]
                    } else {
                        $_
                    }
                }
            } else {
                $_
            }
        }
    }

    if (!$done) {
        if ($value) {
            $blockLines += "${key}=$value"
        }
    }
    $parsedSectionFile.blockHt[$section] = $blockLines
}

function Comment-SectionKv {
    Param([parameter(Mandatory=$True)]$parsedSectionFile,[parameter(Mandatory=$True)][string]$section, [parameter(Mandatory=$True)][string]$key)
    $done = $False
    $blockLines = $parsedSectionFile.blockHt[$section] | ForEach-Object {
        if ($done) {
            $_
        } else {
            if ($_ -match "^\s*${key}=") {
                $done = $True
                "#$_"
            } else {
                $_
            }
        }
    }
    $parsedSectionFile.blockHt[$section] = $blockLines
}

function Get-SectionValueByKey {
    Param([parameter(Mandatory=$True)]$parsedSectionFile,[parameter(Mandatory=$True)][string]$section, [parameter(Mandatory=$True)][string]$key)
    $kv = $parsedSectionFile.blockHt[$section] | ? {$_ -match "^${key}\s*=\s*(.*?)\s*$"} | Select-Object -First 1
    if ($kv) {
        $Matches[1]
    }
    
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

    $skf | Add-Member -MemberType ScriptMethod -Name addKv -Value $addKv

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

    $skf | Add-Member -MemberType ScriptMethod -Name commentKv -Value $commentKv

    $getValue = {
        param([String]$section, [String]$k)
        $kv = $this.blockHt[$section] | ? {$_ -match "^$k="}
        if ($kv) {
            $kv -split "=" | Select-Object -Index 1
        }
    }

    $skf | Add-Member -MemberType ScriptMethod -Name getValue -Value $getValue

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

    $skf | Add-Member -MemberType ScriptMethod -Name writeToFile -Value $writeToFile -PassThru
}

# string utils

function Trim-All {
    Param([parameter(ValueFromPipeline=$True)][string]$content)
    if ($content) {
        $content.Trim()
    } else {
        ""
    }
}

function Trim-Start {
    Param([parameter(ValueFromPipeline=$True)][string]$content)
    if ($content) {
        $content.TrimStart()
    } else {
        ""
    }
}

function Trim-End {
    Param([parameter(ValueFromPipeline=$True)][string]$content)
    if ($content) {
        $content.TrimEnd()
    } else {
        ""
    }
}

function Split-ColonComma {
    Param([parameter(ValueFromPipeline=$True)][string]$content)
    $trimed = $content.Trim()
    if ($trimed) {
        if ($trimed -match ':') {
            $trimed -split ',' | ForEach-Object -End {$h} -Begin {$h = @{}} -Process {
                    $a = $_.split(':')
                    if ($a.length -eq 2) {
                        $h[$a[0].trim()] = $a[1].trim()
                    }
                }
        } else {
            $trimed
        }
    } else {
        ""
    }

}

function Write-TextFile {
    Param([parameter(ValueFromPipelineByPropertyName=$True)][string]$name, [parameter(ValueFromPipelineByPropertyName=$True)][string]$content, [parameter(ValueFromPipelineByPropertyName=$True)][string]$codeLineSeperator)
    $content -split '\r?\n|\r\n?' | Out-File -FilePath $name -Encoding utf8 -Force
}

function Test-AbsolutePath {
    Param([parameter(ValueFromPipeline=$True)][string]$Path)
    process {
        $Path.StartsWith("/") -or ($Path -match ":")
    }
}

function New-Directory {
    Param([parameter(ValueFromPipeline=$True)][string]$Path)
    process {
        if (!(Test-Path -PathType Container -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force
        } else {
            $Path
        }
    }
}

function Choose-FirstTrueValue {
    $args | Where-Object { if($_) {$_}} | Select-Object -First 1
}

function Choose-OnCondition {
   Param([parameter(Mandatory=$True)]$condition,[parameter(Position=1)]$onTrue,[parameter(Position=2)]$onFalse)
   process {
       if ($condition) {
        $onTrue
       } else {
        $onFalse
       }
   }
}

function Print-Success {
    if ($Error.Count -gt 0) {
        $Error | ForEach-Object {$_.ToString(),$_.ScriptStackTrace}
    } else {
        "@@success@@"
    }
}

function Get-CmdTarget {
    Param([parameter(ValueFromPipeline=$True)][string]$command)
    $src = $command | Get-Command | Select-Object -ExpandProperty Source | Get-Item
    if ($src.LinkType -eq "SymbolicLink") {
        $src.Target
    } else {
        $src
    }
}

function Get-JavaHome {
    Get-CmdTarget -command "java" | Split-Path -Parent | Split-Path -Parent
}