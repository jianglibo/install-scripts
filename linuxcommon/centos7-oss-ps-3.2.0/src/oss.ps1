Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

function ConvertTo-DecoratedEnv {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("nexus-.*\.tar\.gz"))
    $myenv
}

function Get-DirInfomation {
    Param($myenv)
    $h = @{}
    $h.nexusBin = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/nexus$"} | Select-Object -First 1 -ExpandProperty FullName
    $h.nexusHome = $h.nexusBin | Join-Path -ChildPath "../../../" -Resolve
    $h
}

function install-oss {
    Param($myenv)

    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}

    $myenv.InstallDir | New-Directory

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        $myenv.tgzFile + " doesn't exists!" | Write-Error
    }

    $myenv.InstallDir | Centos7-Chown -user $myenv.software.runas

    $DirInfo = Get-DirInfomation -myenv $myenv

    $logFile = $DirInfo.nexusHome | Join-Path -ChildPath "sonatype-work/nexus3/log/nexus.log"

    if (Test-Path $logFile) {
        Remove-Item $logFile -Force
    }

    Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} start" -f $DirInfo.nexusBin) -user $myenv.software.runas

    $steady = $false
    $lastLc = 0
    while (!$steady) {
        Start-Sleep -Seconds 30
        $lc = Get-Content -Path $logFile | Measure-Object -Line | Select-Object -ExpandProperty Lines
        $lc | Write-HostIfInTesting
        $lastLc | Write-HostIfInTesting
        if ($lc -eq $lastLc) {
            $steady = $true
        } else {
            $lastLc = $lc
        }
        if (Get-Content $logFile | Where-Object {$_ -match "^Started Sonatype Nexus OSS"} | Select-Object -First 1) {
            $steady = $true
        }
    }

    Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} stop" -f $DirInfo.nexusBin) -user $myenv.software.runas

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.nexusHome | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    $portLine = Get-Content ($DirInfo.nexusHome | Join-Path -ChildPath "sonatype-work/nexus3/etc/nexus.properties") | Where-Object {$_ -match "^\s*application-port=(\d+)"} | Select-Object -First 1
    $nexusPort = "8081"
    if ($portLine) {
        $nexusPort = $Matches[1]
    }
    Centos7-FileWall -ports $Matches[1]
    $resultHash.dirInfo = $DirInfo
    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
}

function Update-OssStataus {
    Param($myenv, $state)
    $resultJson = Get-Content $myenv.resultFile | ConvertFrom-Json
    Centos7-Run-User -shell "/bin/bash" -scriptcmd ("{0} $state" -f $resultJson.dirInfo.nexusBin) -user $myenv.software.runas
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "install" {
        install-oss $myenv
    }
    "start" {
        Update-OssStataus $myenv "start"
    }
    "stop" {
        Update-OssStataus $myenv "stop"
    }
    "restart" {
        Update-OssStataus $myenv "restart"
    }
    "t" {
        "t" | Write-Output
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
