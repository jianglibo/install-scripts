Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

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
    $DirInfo = Get-DirInfomation -myenv $myenv

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.nexusHome | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

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
