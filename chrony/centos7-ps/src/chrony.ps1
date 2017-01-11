Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

function install-chrony {
    Param($myenv)
    Uninstall-NtpService
    
    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    if (Test-ServiceRunning -serviceName "chronyd") {
        systemctl stop chronyd
    }
    yum install -y chrony
    $myenv.software.textfiles | Where-Object Name -Match "chrony.conf$" | ForEach-Object {
        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ("/etc/" | Join-Path -ChildPath $_.name) -Encoding ascii
    } | Out-Null

    $kf = "/etc/chrony.keys"

    if ("CHRONY_SERVER" -in $myenv.myRoles) {
        [array]$lines = Get-Content -Path "/etc/chrony.conf" | Where-Object {$_ -notmatch "^\s*allow"}
        [array]$allowLines = $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $myenv.box.ip} | ForEach-Object {"allow " + $_.hostname}
        $lines + $allowLines | Out-File -FilePath "/etc/chrony.conf" -Encoding ascii

        $keyGenareted = $false
        if (Test-Path "$kf") {
            $keyGenareted =  Get-Content $kf | Where-Object {$_ -imatch "HEX:"}
        }

        if (-not $keyGenareted) {
            systemctl restart chronyd
            Start-Sleep -Seconds 1
            systemctl stop chronyd
        }
        $returnToClient = @{}
        $returnToClient.chronyserver = @{}
        $returnToClient.chronyserver.keysContent = Get-Content $kf | ConvertTo-Base64String
        $returnToClient.chronyserver.keysContent | Write-HostIfInTesting
        Write-ReturnToClient -returnToClient $returnToClient
    }
    if ("CHRONY_CLIENT" -in $myenv.myRoles) {
        [array]$lines = Get-Content -Path "/etc/chrony.conf" | Where-Object {$_ -notmatch "^\s*server"}
        [array]$serverLines = $myenv.boxGroup.boxes | Where-Object {$_.roles -match "CHRONY_SERVER"} | ForEach-Object {"server " + $_.hostname + " iburst"}
        $lines + $serverLines | Out-File -FilePath "/etc/chrony.conf" -Encoding ascii
        $kc = $myenv.boxGroup.installResults.chronyserver.keysContent
        if ($kc) {
           $kc | ConvertFrom-Base64String | Out-File $kf -Encoding ascii
        }
    }
    systemctl enable chronyd
    Update-FirewallItem -ports 123,323 -prot udp
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
