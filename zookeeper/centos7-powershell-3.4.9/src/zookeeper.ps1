# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
Param(
    [parameter(Mandatory=$true)]$envfile,
    [string]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/LinuxUtil.ps1

Get-Command java


function ConvertTo-DecoratedEnv {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv | Add-Member -MemberType ScriptProperty -Name zkconfigLines -Value {
        $this.software.configContent.asHt("zkconfig").GetEnumerator() |
            ForEach-Object {"{0}={1}" -f $_.Key,$_.Value} | Sort-Object
    }
    $myenv | Add-Member -MemberType NoteProperty -Name installDir -Value $myenv.software.configContent.installDir
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value $myenv.getUploadedFile("zookeeper-.*\.tar\.gz")
    $myenv | Add-Member -MemberType NoteProperty -Name envvs -Value $myenv.software.configContent.asHt("envvs")
    $myenv | Add-Member -MemberType NoteProperty -Name dataDir -Value $myenv.software.configContent.zkconfig.dataDir
    $myenv
}

function Get-ZookeeperDirInfomation {
    Param($myenv)
    $h = @{}
    $h.zkCli = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/zkCli.sh$"} | Select-Object -First 1 -ExpandProperty FullName
    $h.zkHome = $h.zkCli | Split-Path -Parent | Split-Path -Parent
    $h
}

function Uninstall-Zk {
    Param($myenv)
}

function Install-Zk {
    Param($myenv)
    $myenv.InstallDir | New-Directory | Out-Null

    Invoke-ZookeeperExecutable -myenv $myenv -action stop

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        return
    }
    Write-ConfigFiles -myenv $myenv | Out-Null
}

function Write-ConfigFiles {
    Param($myenv)
    $configFile = Join-Path -Path $myenv.envvs.ZOOCFGDIR -ChildPath $myenv.envvs.ZOOCFG
    $pidFolder = Split-Path -Path $myenv.envvs.ZOOPIDFILE -Parent
    $logDir = $myenv.envvs.ZOO_LOG_DIR
    $resultHash = @{}
    $resultHash.env = @{}

    $myenv.envvs.ZOOCFGDIR, $myenv.dataDir, $logDir | New-Directory | Out-Null

    $idhpair = $myenv.boxGroup.boxes | Where-Object {$_.roles -match "Zookeeper"} | Select-Object @{n="serverId"; e={$_.ip -split "\." | Select-Object -Last 1}}, hostname
    $serviceLines = $idhpair | ForEach-Object {"server.{0}={1}:{2}:{3}" -f (@($_.serverId, $_.hostname) + $myenv.software.configContent.zkports.Split(','))} | Sort-Object

    [array]$zcfgLines = $myenv.software.textfiles | Where-Object {$_.name -eq "zoo.cfg"} | Select-Object -ExpandProperty content

    $zcfgLines + $serviceLines  | Out-File -FilePath $configFile -Encoding ascii

    # encoding is very important.
    # $myenv.serviceLines | Out-File $myenv.configFile -Append -Encoding ascii

    # write myid file.

    $myenv.box.ip -split "\." | Select-Object -Last 1 | Set-Content -Path (Join-Path $myenv.dataDir -ChildPath "myid")

    # get executable file: /opt/zookeeper/zookeeper-3.4.9/bin/zkServer.sh
    # "$ZOOBINDIR/zkEnv.sh", so we can find zkEnv.sh in same directory. zkEnv.sh need ZOOCFGDIR, when get ZOOCFGDIR, it read config from ZOOCFGDIR/zookeeper-env.sh
    # or we can write all value just to zkEnv.sh, just before ZOOBINDIR="${ZOOBINDIR:-/usr/bin}"

    $zkServerBin = (Get-ChildItem -Path $myenv.installDir -Recurse -Filter "zkServer.sh" | Where-Object {($_.FullName -replace "\\","/") -match "/bin/zkServer.sh$"}).FullName
    Join-Path -Path $zkServerBin "../../conf/" | Get-ChildItem | Copy-Item -Destination $myenv.envvs.ZOOCFGDIR
    $zkEnv = $zkServerBin | Split-Path -Parent | Join-Path -ChildPath zkEnv.sh

    # after success install, we will create a file only known to this installation script. called: easyinstaller-result.json

    $myenv.envvs.GetEnumerator() | ForEach-Object {
        $resultHash.env[$_.Key] = $_.Value
    } | Out-Null

    # start command read this file to find executable. or use systemd
    # no need, it can reason from other information.
    $resultHash.executable = $zkServerBin

    # write hostname to hosts.
    $hf = New-HostsFile
    $myenv.boxGroup.boxes | Where-Object {$_.ip -ne $_.hostname} | ForEach-Object {$hf.addHost($_.ip, $_.hostname)}
    $hf.writeToFile()

    #change hostname
    if ($myenv.box.ip -ne $myenv.box.hostname) {
        Set-HostName -hostname $myenv.box.hostname
    }
    # open firewall
    Update-FirewallItem -ports $myenv.software.configContent.zkports,$myenv.software.configContent.zkconfig.clientPort

    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.software.runner -envfile $envfile -code $PSCommandPath) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
    # change run user.
    if ($myenv.software.runas) {
        New-LinuxUser -username $myenv.software.runas
        $myenv.dataDir, $logDir, $pidFolder | Invoke-Chown -user $myenv.software.runas
    }

    $DirInfo = Get-ZookeeperDirInfomation $myenv
    "ZOOKEEPER_HOME=" + $DirInfo.zkHome, "export ZOOKEEPER_HOME" | Out-File -FilePath "/etc/profile.d/zookeeper.sh" -Encoding ascii
}

function Invoke-ZookeeperExecutable {
    Param($myenv, [ValidateSet("start","start-foreground","stop", "restart", "status", "upgrade", "print-cmd")][String]$action)
    if (Test-Path $myenv.resultFile) {
        $rh = Get-Content $myenv.resultFile | ConvertFrom-Json | Add-AsHtScriptMethod
        # expose environment variables.
        $rh.asHt("env").GetEnumerator() | ForEach-Object {
            Set-Content -Path "env:$($_.Key)" -Value $_.Value
        }
        if ((Test-Path $myenv.envvs.ZOOPIDFILE) -and ($action -eq "start")) {
            Start-RunUser -scriptcmd ($rh.executable + " stop") -user $myenv.software.runas
        }

        Start-RunUser -scriptcmd ($rh.executable + " $action") -user $myenv.software.runas
    }
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

if ($myenv.boxGroup.boxes.Count -lt 3) {
    Write-Error "There must at least 3 servers to install zookeeper".
    return
}

if (! $action) {
    return
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

switch ($action) {
    "install" {
        Install-Zk $myenv
        break
    }
    "t" {
        "t"
    }
    default {
        Invoke-ZookeeperExecutable -myenv $myenv -action $action
    }
}

Write-SuccessResult