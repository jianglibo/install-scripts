Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

function install-chrony {
    Param($myenv)
    yum install -y chrony
    $myenv.software.textfiles | Where-Object Name -Match "chrony.conf$" | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ("/etc/" | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    if ("CHRONY_SERVER" -in $myenv.myRoles) {
        [array]$lines = Get-Content -Path "/etc/chrony.conf" | Where-Object {$_ -notmatch "^\s*allow"}
        [array]$allowLines = $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $myenv.box.ip} | ForEach-Object {"allow " + $_.hostname}
        $lines + $allowLines | Out-File -FilePath "/etc/chrony.conf" -Encoding ascii
    }

    if ("CHRONY_CLIENT" -in $myenv.myRoles) {
        [array]$lines = Get-Content -Path "/etc/chrony.conf" | Where-Object {$_ -notmatch "^\s*server"}
        [array]$serverBox = 
        [array]$serverLines = $myenv.boxGroup.boxes | Where-Object {$_.roles -contains "CHRONY_SERVER"} | ForEach-Object {"server " + $_.hostname + " iburst"}
        $lines + $serverLines | Out-File -FilePath "/etc/chrony.conf" -Encoding ascii
    }
    systemctl enable chronyd
}

function Update-ChronyStatus {
    Param($state)
    systemctl $state chronyd
}

$myenv = New-EnvForExec $envfile 

switch ($action) {
    "install" {
        install-chrony $myenv
    }
    "start" {
        Update-ChronyStatus "start"
    }
    "stop" {
        Update-ChronyStatus "stop"
    }
    "t" {
        "t" | Write-Output
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
