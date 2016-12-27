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
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("apache-maven-.*\.tar\.gz"))
    $myenv
}

function Get-DirInfomation {
    Param($myenv)
    $h = @{}
    $h.mvnBin = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/mvn$"} | Select-Object -First 1 -ExpandProperty FullName
    $h.mvnHome = $h.mvnBin | Split-Path -Parent | Split-Path -Parent
    $h
}

function install-mvn {
    Param($myenv)
    $myenv.InstallDir | New-Directory
    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        $myenv.tgzFile + " doesn't exists!" | Write-Error
    }
    $DirInfo = Get-DirInfomation -myenv $myenv

    $myenv.software.textfiles | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.mvnHome | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    Install-Alternatives -link /usr/bin/mvn -name mvn -path $DirInfo.mvnBin -priority 100
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "install" {
        install-mvn $myenv
    }
    "t" {
        "t" | Write-Output
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
