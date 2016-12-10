Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)] $action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv
}

function Set-JavaHome {
    Param($myenv)
    ("JAVA_HOME={0}" -f (Get-JavaHome)), "export JAVA_HOME" | Out-File -FilePath "/etc/profile.d/java.sh" -Encoding ascii
}

$myenv = New-EnvForExec $envfile | Decorate-Env

switch ($action) {
    "setjavahome" {
        Set-JavaHome $myenv
    }
    "openfirewall" {
        [array]$ports = (Parse-Parameters $remainingArguments) -split "/"
        $ports
        $prot = "tcp"
        if ($ports.Count -gt 1) {
            $prot = $ports[1]
        }
        $ports = $ports[0]
        Centos7-FileWall -ports $ports -prot $prot
        firewall-cmd --list-all
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success
