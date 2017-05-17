Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

    # write hostname to hosts.
$hf = New-HostsFile
$myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
$hf.writeToFile()

function Start-ExposeEnv {
    Param($myenv)
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    Add-AsHtScriptMethod $rh
    $envhash =  $rh.asHt("env")
    $envhash.GetEnumerator() | ForEach-Object {
        Set-Content -Path "env:$($_.Key)" -Value $_.Value
    }
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "install" {
        Install-mailserver $myenv (ConvertFrom-Base64Parameter $remainingArguments)
    }
    "start" {
        if (!(Test-ServiceRunning "mysqld")) {
            systemctl start mysqld
        }
    }
    "stop" {
        if (Test-ServiceRunning mysqld) {
            systemctl stop mysqld
        }
    }
    "t" {
        ConvertFrom-Base64Parameter $remainingArguments
        return
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult
