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
    $myenv | Add-Member -MemberType NoteProperty -Name logDir -Value $myenv.software.configContent.logDir
    $myenv | Add-Member -MemberType NoteProperty -Name pidFile -Value $myenv.software.configContent.pidFile
    $myenv | Add-Member -MemberType NoteProperty -Name logProp -Value $myenv.software.configContent.logProp
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

    if (!(Test-Path $myenv.logDir)) {
      New-Item -Path $myenv.logDir -ItemType Directory | Out-Null
    }

    # encoding is very important.
    $myenv.zkconfigLines + $myenv.serviceLines | Out-File $myenv.configFile -Encoding ascii

    $tgzFile = $myenv.getUploadedFile()
    if (Test-Path $tgzFile -PathType Leaf) {
        Run-Tar $tgzFile -DestFolder $myenv.binDir
    } else {
        exit
    }

    # write myid file.

    $myenv.box.ip -split "\." | Select-Object -Last 1 | Set-Content -Path (Join-Path $myenv.DataDir -ChildPath "myid")

    # get executable file: /opt/zookeeper/zookeeper-3.4.9/bin/zkServer.sh
    # "$ZOOBINDIR/zkEnv.sh", so we can find zkEnv.sh in same directory. zkEnv.sh need ZOOCFGDIR, when get ZOOCFGDIR, it read config from ZOOCFGDIR/zookeeper-env.sh
    # or we can write all value just to zkEnv.sh, just before ZOOBINDIR="${ZOOBINDIR:-/usr/bin}"

    $zkServerBin = (Get-ChildItem -Path $myenv.binDir -Recurse -Filter "zkServer.sh" | Where-Object {($_.FullName -replace "\\","/") -match "/bin/zkServer.sh$"}).FullName
    Join-Path -Path $zkServerBin "../../conf/" | Get-ChildItem | Copy-Item -Destination $myenv.configFolder
    $zkEnv = $zkServerBin | Split-Path -Parent | Join-Path -ChildPath zkEnv.sh

    # after success install, we will create a file only known to this installation script. called: easyinstaller-result.json
    $ZOOCFG = Split-Path -Path $myenv.configFile -Leaf
    $ZOOCFGDIR = $myenv.configFolder
    $ZOOPIDFILE = $myenv.pidFile
    $ZOO_LOG_DIR = $myenv.logDir
    # there is a bug in zkServer.sh, it cannot extract ZOO_DATADIR from config file.
    # $ZOO_DATADIR = $myenv.DataDir
    $ZOO_LOG4J_PROP = $myenv.logProp

    $envlines = "ZOOCFG=`"${ZOOCFG}`"",
                 "ZOOCFGDIR=`"$ZOOCFGDIR`"",
                 "ZOOPIDFILE=`"${ZOOPIDFILE}`"",
                 "ZOO_LOG_DIR=`"${ZOO_LOG_DIR}`"",
                 "ZOO_LOG4J_PROP=`"${ZOO_LOG4J_PROP}`""
   #              "ZOO_DATADIR=`"${ZOO_DATADIR}`""

    Insert-Lines -FilePath $zkEnv -ptn "^ZOOBINDIR=" -lines $envlines

    # start command read this file to find executable. or use systemd
    @{executable=$zkServerBin} | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    $osutil = New-Centos7Util
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        $osutil.setHostName($myenv.box.hostname)
    }
    # open firewall
    $osutil.openFireWall($myenv.software.configContent.zkports)

    # write app.sh, this file can be invoked direct on server.
    "#!/usr/bin/env bash", ('$(', (New-Runner $myenv.software.runner -envfile $envfile -code $MyInvocation.MyCommand.Path), ')' -join "") | Out-File -FilePath $myenv.appFile -Encoding ascii

    # change run user.
}

function Change-Status {
    Param($myenv, [String]$action)
    $result = Get-Content $myenv.resultFile | ConvertFrom-Json
    $result.executable, $action -join " " | Invoke-Expression
}

$myenv = New-EnvForExec $envfile | Decorate-Env
switch ($action) {
    "install" {
        Install-Zk $myenv
        break
    }
    default {
        Change-Status -myenv $myenv -action $action
    }
}

"@@success@@"
