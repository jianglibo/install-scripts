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
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("jdk-.*\.tar\.gz"))
    $myenv
}

function Get-DirInfomation {
    Param($myenv)
    $h = @{}
    $h.javaBin = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/java$"} | Select-Object -First 1 -ExpandProperty FullName
    $h
}

function install-java {
    $myenv.InstallDir | New-Directory
    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        $myenv.tgzFile + " doesn't exists!" | Write-Error
    }
    $DirInfo = Get-DirInfomation -myenv $myenv

    Install-Alternatives -link "/usr/bin/java" -path $DirInfo.javaBin -name "java" -priority 100
    Save-JavaHomeToEasyinstallerProfile
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "install" {
        install-java $myenv
    }
    "t" {
        "t" | Write-Output
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
