# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# CREATE USER 'jeffrey'@'localhost' IDENTIFIED BY 'mypass';
# ALTER USER 'jeffrey'@'localhost'IDENTIFIED BY 'mypass';
# ALTER USER USER() IDENTIFIED BY 'mypass'; // change own password.
# SET PASSWORD FOR 'jeffrey'@'localhost' = PASSWORD('mypass');

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$codefile,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

Detect-RunningYum

if (! $codefile) {
    $codefile = $MyInvocation.MyCommand.Path
}

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    # piddir and logdir
    $envvs = $myenv.software.configContent.asHt("envvs")
    $myenv
}

function Install-Mysql {
    Param($myenv)

    if (Centos7-IsServiceRunning mysqld) {
        Write-Error "mysql are running...., skip installation."
    }
    $mariadblibs = yum list installed | ? {$_ -match "mariadb-libs"}

    if ($mariadblibs) {
        $mariadblibs -split "\s+" | Select-Object -First 1 | % {yum -y remove $_}
    }
    Get-MysqlRpms $myenv | % {yum -y install $_} | Out-Null
    Write-ConfigFiles -myenv $myenv
}

function Get-MysqlRpms {
    Param($myenv)
    Get-UploadFiles $myenv | ? {$_ -match "-common-\d+.*rpm$"}
    Get-UploadFiles $myenv | ? {$_ -match "-libs-\d+.*rpm$"}
    Get-UploadFiles $myenv | ? {$_ -match "-client-\d+.*rpm$"}
    Get-UploadFiles $myenv | ? {$_ -match "-server-\d+.*rpm$"}
}


function Set-NewMysqlPassword {
    Param($myenv, $newpassword)
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json

    if ($rh.info -and $rh.info.initPasswordReseted) {
        Write-Error "Initial Password already rested, skipping..."
    }

    if (!($rh.info -and $rh.info.firstRunned)) {
        Write-Error "Mysqld hadn't ran once, skipping..."
    }

    $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $ef = $myenv.software.textfiles | Where-Object Name -EQ "change-init-pass.tcl" | Select-Object -First 1 -ExpandProperty content

    $initpassword = (Get-Content (Get-SectionValueByKey -parsedSectionFile $mycnf -section "[mysqld]" -key "log-error") | ? {$_ -match "A temporary password is generated"} | Select-Object -First 1) -replace ".*:\s*(.*?)\s*$",'$1'

    Run-String -execute tclsh -content $ef -quotaParameter "$initpassword" "$newpassword" | Write-Output -OutVariable fromTcl
    if ($LASTEXITCODE -ne 0) {
        Write-Error "change-init-pass.tcl exit with none zero. $fromTcl"
    }

    Alter-ResultFile -resultFile $myenv.resultFile -keys "info","initPasswordReseted" -value $True
}

function New-MysqlUser {
    Param($myenv, $rootpassword)
}

function Enable-LogBin {
    Param($myenv)
    if (! ("MYSQL_MASTER" -in $myenv.myRoles)) {
        "not a master server, skip enable logbin"
        return
    }
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    if (!$rh.info -or !$rh.info.initPasswordReseted) {
        Write-Error "Please reset mysqld init password first."
    }

    if ($rh.info -and $rh.info.logBinEnabled) {
        Write-Error "logbin already enabled. skipping....."
    }

    $sf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $mysqlds = "[mysqld]"

    $serverId = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "server-id"

    if (! $serverId) {
        Add-SectionKv -parsedSectionFile $sf -section $mysqlds -key "server-id"
        $serverId = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "server-id"
    }

    if (! $serverId) {
        Write-Error "There must exists an item with server-id=xxx format in my.cnf, that server-id is for mysqld master, slave will get random server-id."
    }
    Add-SectionKv -parsedSectionFile $sf -section $mysqlds -key "log-bin"
    $sf.writeToFile()
    systemctl restart mysqld | Out-Null
}

function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}

    #write my.cnf
    $myenv.software.textfiles | ? {$_.name -eq "my.cnf"} | Select-Object -First 1 -ExpandProperty content | Out-File -FilePath "/etc/my.cnf" -Encoding ascii

    $sf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $mysqlds = "[mysqld]"
    $logError = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "log-error"
    $datadir = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "datadir"
    $pidFile = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "pid-file"
    $socket = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "socket"
    $binLog = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "log-bin"
    # we cannot use this server-id value, because all box are same.
    $serverId = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "server-id"

    # if bin-log init enabled.
    if ($binLog) {
        Comment-SectionKv -parsedSectionFile $sf -section $mysqlds -key "log-bin"
        if ($serverId) {
            Comment-SectionKv -parsedSectionFile $sf -section $mysqlds -key "server-id"
        }
        $sf.writeToFile()
    }

    if (! (Split-Path -Parent $datadir | Test-Path)) {
        Split-Path -Parent $datadir | New-Directory | Out-Null
    }

    if (! (Split-Path -Parent $logError | Test-Path)) {
        Split-Path -Parent $logError | New-Directory | Out-Null
    }

    if ($logError | Test-Path) {
        Remove-Item -Path $logError | Out-Null
    }

    # start mysqld£¬ when mysql first start, It will create directory and user to run mysql.
    # so just change my.cnf, that's all.
    systemctl enable mysqld | Out-Null
    systemctl start mysqld | Out-Null

    $resultHash.info.firstRunned = $True

    $resultHash | ConvertTo-Json | Out-File -FilePath  $myenv.resultFile -Force -Encoding ascii
    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.software.runner -envfile $envfile -code $codefile) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile
}

function expose-env {
    Param($myenv)
    $rh = Get-Content $myenv.resultFile | ConvertFrom-Json
    Add-AsHtScriptMethod $rh
    $envhash =  $rh.asHt("env")
    $envhash.GetEnumerator() | ForEach-Object {
        Set-Content -Path "env:$($_.Key)" -Value $_.Value
    }
}

$myenv = New-EnvForExec $envfile | Decorate-Env

switch ($action) {
    "install" {
        Install-Mysql $myenv
    }
    "enableLogBin" {
        enable-logbin $myenv
    }
    "changePassword" {
        Set-NewMysqlPassword $myenv @remainingArguments
    }
    "start" {
        if (!(Centos7-IsServiceRunning "mysqld")) {
            systemctl start mysqld
        }
    }
    "stop" {
        if (Centos7-IsServiceRunning mysqld) {
            systemctl stop mysqld
        }
    }
    "t" {
        $remainingArguments
        return
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success
