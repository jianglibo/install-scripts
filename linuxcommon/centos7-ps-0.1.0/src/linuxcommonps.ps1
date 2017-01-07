Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

function ConvertTo-DecoratedEnv {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "setjavahome" {
        Save-JavaHomeToEasyinstallerProfile
    }
    "openfirewall" {
        [array]$ports = (ConvertFrom-Base64Parameter $remainingArguments) -split "/"
        $ports
        $prot = "tcp"
        if ($ports.Count -gt 1) {
            $prot = $ports[1]
        }
        $ports = $ports[0]
        Update-FirewallItem -ports $ports -prot $prot
        firewall-cmd --list-all
    }
    "kill-process" {
        $remainingArguments | Write-Output
        [string[]]$pns = ($remainingArguments | ConvertFrom-Base64Parameter).Trim() -split "\s+"
        $pns | Write-HostIfInTesting
        Get-Process | Where-Object Name -In $pns | Stop-Process -Force
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult