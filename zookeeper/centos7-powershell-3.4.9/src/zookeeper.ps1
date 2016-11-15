# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [string]
    $action,
    [string]
    $codefile
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

if (! $codefile) {
    $codefile = $MyInvocation.MyCommand.Path
}

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
    $myenv | Add-Member -MemberType NoteProperty -Name installDir -Value $myenv.software.configContent.installDir
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value $myenv.getUploadedFile("zookeeper-.*\.tar\.gz")
    $myenv | Add-Member -MemberType NoteProperty -Name envvs -Value $myenv.software.configContent.asHt("envvs")
    $myenv | Add-Member -MemberType NoteProperty -Name dataDir -Value $myenv.software.configContent.zkconfig.dataDir
    $myenv
}

function Uninstall-Zk {
    Param($myenv)
}

function Install-Zk {
    Param($myenv)
    $myenv.InstallDir | New-Directory

    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Run-Tar $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        return
    }
    Write-ConfigFiles -myenv $myenv | Out-Null
}

function Write-ConfigFiles {
    Param($myenv)
    $configFile = Join-Path -Path $myenv.envvs.ZOOCFGDIR -ChildPath $myenv.envvs.ZOOCFG
    $resultHash = @{}
    $resultHash.env = @{}

    $myenv.envvs.ZOOCFGDIR, $myenv.dataDir, $myenv.envvs.ZOO_LOG_DIR | New-Directory

    $myenv.software.textfiles | ForEach-Object {
        $name = $_.name
        $content = $_.content
        switch ($name) {
            "zoo.cfg" {
                ($content -split '\r?\n|\r\n?') + $myenv.serviceLines | Out-File -FilePath $configFile -Encoding ascii
            }
        }
    } | Out-Null


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
        Centos7-SetHostName -hostname $myenv.box.hostname
    }
    # open firewall
    Centos7-FileWall -ports $myenv.software.configContent.zkports

    $user = Centos7-GetScriptRunner -myenv $myenv

    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.software.runner -envfile $envfile -code $codefile) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
    # change run user.
    if ($user) {
        Centos7-UserManager -username $user -action add
        $myenv.dataDir, $myenv.envvs.ZOO_LOG_DIR | Centos7-Chown -user $user
    }
}


function Change-Status {
    Param($myenv, [ValidateSet("start","start-foreground","stop", "restart", "status", "upgrade", "print-cmd")][String]$action)
    Centos7-GetRunuserCmd -myenv $myenv -action $action | Invoke-Expression
}

$myenv = New-EnvForExec $envfile | Decorate-Env

if (! $action) {
    return
}
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
