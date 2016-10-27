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
    $myenv
}

function Uninstall-Zk {
    Param($myenv)
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
    if (Test-Path $tgzFile -PathType Leaf) {
        Run-Tar $tgzFile -DestFolder $myenv.binDir
    } else {
        exit
    }

    # get executable file: /opt/zookeeper/zookeeper-3.4.9/bin/zkServer.sh
    # "$ZOOBINDIR/zkEnv.sh", so we can find zkEnv.sh in same directory. zkEnv.sh need ZOOCFGDIR, when get ZOOCFGDIR, it read config from ZOOCFGDIR/zookeeper-env.sh
    # or we can write all value just to zkEnv.sh, just before ZOOBINDIR="${ZOOBINDIR:-/usr/bin}"

    $zkServerBin = (Get-ChildItem -Path $myenv.binDir -Recurse -Filter "zkServer.sh" | Where-Object {($_.FullName -replace "\\","/") -match "/bin/zkServer.sh$"}).FullName
    $zkEnv = $zkServerBin | Split-Path -Parent | Join-Path -ChildPath zkEnv.sh

    # after success install, we will create a file only known to this installation script. called: easyinstaller-result.json
    $ZOOCFG = Split-Path -Path $myenv.configFile -Leaf
    $ZOOCFGDIR = $myenv.configFolder

    $envlines = "ZOOCFG=`"${ZOOCFG}`"", "ZOOCFGDIR=`"$ZOOCFGDIR`""
    Insert-Lines -FilePath $zkEnv -ptn "^ZOOBINDIR=" -lines $envlines

    # start command read this file to find executable. or use systemd
    @{zkServerBin=$zkServerBin} | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force
    
}

switch ($action) {
    "install" {
        Install-Zk (New-EnvForExec $envfile | Decorate-Env)
        break
    }
}

"@@success@@"
