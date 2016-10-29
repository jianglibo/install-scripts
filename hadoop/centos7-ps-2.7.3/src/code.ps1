# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [parameter(Mandatory=$true)]
    $action
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv | Add-Member -MemberType ScriptProperty -Name zkconfigLines -Value {
        $this.software.configContent.asHt("zkconfig").GetEnumerator() |
            ForEach-Object {"{0}={1}" -f $_.Key,$_.Value} | Sort-Object
    }
    $myenv | Add-Member -MemberType ScriptProperty -Name serviceLines -Value {
        $this.boxGroup.boxes |
             Select-Object @{n="serverId"; e={$_.ip.split('\.')[-1]}}, hostname |
             ForEach-Object {"server.{0}={1}:{2}:{3}" -f (@($_.serverId, $_.hostname) + $this.software.configContent.zkports.Split(','))} |
             Sort-Object
    }
    $myenv | Add-Member -MemberType NoteProperty -Name DataDir -Value ($myenv.software.configContent.zkconfig.dataDir)

    $myenv | Add-Member -MemberType NoteProperty -Name configFolder -Value (Split-Path -Parent $myenv.software.configContent.configFile)
    $myenv | Add-Member -MemberType NoteProperty -Name configFile -Value $myenv.software.configContent.configFile
    $myenv | Add-Member -MemberType NoteProperty -Name binDir -Value $myenv.software.configContent.binDir
    $myenv | Add-Member -MemberType NoteProperty -Name logDir -Value $myenv.software.configContent.logDir
    $myenv | Add-Member -MemberType NoteProperty -Name pidFile -Value $myenv.software.configContent.pidFile
    $myenv | Add-Member -MemberType NoteProperty -Name logProp -Value $myenv.software.configContent.logProp
    $myenv
}

function Install-Hd {
    Param($myenv)
}

function Change-Status {
    Param($myenv, [String]$action)
    $result = Get-Content $myenv.resultFile | ConvertFrom-Json
    $result.executable, $action -join " " | Invoke-Expression
}

$myenv = New-EnvForExec $envfile | Decorate-Env
switch ($action) {
    "install" {
        Install-Hd $myenv
        break
    }
    default {
        Change-Status -myenv $myenv -action $action
    }
}

"@@success@@"
