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
# Remove-Item /opt/vvvvv/* -Recurse -Force

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv = $myenv | Add-Member -MemberType ScriptProperty -Name zkconfigLines -Value {
        $this.softwareConfig.asHt("zkconfig").GetEnumerator() |
            ForEach-Object {"{0}={1}" -f $_.Key,$_.Value} | Sort-Object
        } -PassThru
    $myenv = $myenv | Add-Member -MemberType ScriptProperty -Name serviceLines -Value {
        $this.jsonObj.boxGroup.boxes |
             Select-Object @{n="serverId"; e={$_.ip.split('\.')[-1]}}, hostname |
             ForEach-Object {"server.{0}={1}:{2}:{3}" -f (@($_.serverId, $_.hostname) + $this.softwareConfig.jsonObj.zkports.Split(','))} |
             Sort-Object
        } -PassThru
    $myenv = $myenv | Add-Member -MemberType NoteProperty -Name DataDir -Value ($myenv.softwareConfig.jsonObj.zkconfig.dataDir) -PassThru

    $myenv = $myenv | Add-Member -MemberType NoteProperty -Name configFolder -Value (Split-Path -Parent $myenv.softwareConfig.jsonObj.configFile) -PassThru
    $myenv = $myenv | Add-Member -MemberType NoteProperty -Name configFile -Value $myenv.softwareConfig.jsonObj.configFile -PassThru
    $myenv = $myenv | Add-Member -MemberType NoteProperty -Name binDir -Value $myenv.softwareConfig.jsonObj.binDir -PassThru
    $myenv
}

function Install-Zk {
    Param($myenv)
    if (!(Test-Path $myenv.configFolder)) {
        New-Item -Path $myenv.configFolder -ItemType Directory | Out-Null
    }

    if (!(Test-Path $myenv.DataDir)) {
        New-Item -Path $myenv.DataDir -ItemType Directory | Out-Null
    }
    $myenv.zkconfigLines + $myenv.serviceLines | Out-File $myenv.configFile

    $tgzFile = $myenv.getUploadedFile()
    if (Test-Path $tgzFile) {
        Run-Tar $tgzFile -DestFolder $myenv.binDir
    }
}

switch ($action) {
    "install" {
        Install-Zk (New-EnvForExec $envfile | Decorate-Env)
        break
    }
}

"@@success@@"
