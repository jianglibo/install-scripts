# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# CREATE USER 'jeffrey'@'localhost' IDENTIFIED BY 'mypass';
# ALTER USER 'jeffrey'@'localhost'IDENTIFIED BY 'mypass';
# ALTER USER USER() IDENTIFIED BY 'mypass'; // change own password.
# SET PASSWORD FOR 'jeffrey'@'localhost' = PASSWORD('mypass');

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments,
    [string]$codefile
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

$MYSQL_MASTER = "MYSQL_MASTER"
$MYSQL_REPLICA = "MYSQL_REPLICA"

$remainingArguments | Write-Output

if (! $codefile) {
    $codefile = $MyInvocation.MyCommand.Path
}

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    # piddir and logdir
    $envvs = $myenv.software.configContent.asHt("envvs")
    $myenv
}

<#
mysql> CHANGE MASTER TO
    ->     MASTER_HOST='master_host_name',
    ->     MASTER_USER='replication_user_name',
    ->     MASTER_PASSWORD='replication_password',
    ->     MASTER_LOG_FILE='recorded_log_file_name',
    ->     MASTER_LOG_POS=recorded_log_position;
#>

function Get-MysqlRoleSum {
    Param($myenv)
    $rh = @{}

    $mrnumber = ($myenv.boxGroup.boxes | % {$_.roles} | ? {($_ -match $MYSQL_MASTER) -and ($_ -match $MYSQL_REPLICA)}).Count
    if ($mrnumber -gt 1) {
        Write-Error "There can only be one server with both MYSQL_MASTER and MYSQL_REPLICA roles."
    }

    $mnumber = ($myenv.boxGroup.boxes | % {$_.roles} | ? {($_ -match $MYSQL_MASTER) -and ($_ -notmatch $MYSQL_REPLICA)}).Count
    if ($mnumber -ne 1) {
        Write-Error "There can only be one server with MYSQL_MASTER roles, but $mnumber"
    }

    if ($mrnumber -eq 1) {
        $rh.type = "chained"
    } else {
        $rh.type = "notchained"
    }

    if (($myenv.myRoles -contains $MYSQL_REPLICA) -and ($myenv.myRoles -contains $MYSQL_REPLICA)) {
        $rh.mine = "mr"
    } elseif ($myenv.myRoles -contains $MYSQL_MASTER) {
        $rh.mine = "m"
    } elseif ($myenv.myRoles -contains $MYSQL_REPLICA){
        $rh.mine = "r"
    } else {
        Write-Error "server roles must be in MYSQL_MASTER,MYSQL_REPLICA"
    }
    $rh
}

function install-master {
   Param($myenv, $paramsHash)
   $rsum = Get-MysqlRoleSum -myenv $myenv

   if ($rsum.mine -ne "m") {
       "this server not configurated as master...., skip installation."
        return
   }
   if (!$paramsHash.newpass -or !$paramsHash.replicauser -or !$paramsHash.replicapass) {
      Write-Error "For install action, newpass,replicauser,replicapass are mandontory."
   }

   if (Centos7-IsServiceExists mysqld) {
        "mysql is already installed...., skip installation."
        return
   }
   Install-Mysql $myenv
   Set-NewMysqlPassword $myenv $paramsHash.newpass
   # before enable log-bin, create replica users first, prevent it from copy to other servers.
   $boxes = @()
   if ($rsum.type -eq "chained") { # master only need create one replica user.
      foreach ($box in $myenv.boxGroup.boxes) {
         if (($box.roles -match $MYSQL_MASTER) -and ($box.roles -notmatch $MYSQL_REPLICA)) {
            $boxes += $box
          }
      }
   } else { # create replica users for all slaves.
         foreach ($box in $myenv.boxGroup.boxes) {
         if ($box.roles -notmatch $MYSQL_REPLICA) {
            $boxes += $box
          }
      }
   }
   
   $sqls = ($boxes | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f $paramsHash.replicauser, $paramsHash.replicapass,$_.hostname}) -join ";"
   $sqls | write-host
   $ef = $myenv.software.textfiles | Where-Object Name -EQ "get-sqlresult.tcl" | Select-Object -First 1 -ExpandProperty content
   Run-String -execute tclsh -content $ef -quotaParameter $paramsHash.newpass $sqls | Write-Output -OutVariable fromTcl
   Enable-LogBinAndRecordStatus $myenv $paramsHash $rsum
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

    $initpassword = (Get-Content (Get-SectionValueByKey -parsedSectionFile $mycnf -section "[mysqld]" -key "log-error") | ? {$_ -match "A temporary password is generated"} | Select-Object -First 1) -replace ".*A temporary password is generated.*?:\s*(.*?)\s*$",'$1'

    Run-String -execute tclsh -content $ef -quotaParameter "$initpassword" "$newpassword" | Write-Output -OutVariable fromTcl

    if ($LASTEXITCODE -ne 0) {
        Write-Error "change-init-pass.tcl exit with none zero. $fromTcl"
    }

    Alter-ResultFile -resultFile $myenv.resultFile -keys "info","initPasswordReseted" -value $True
}
function Enable-LogBinAndRecordStatus {
    Param($myenv, $paramsHash, $rsum)
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
        Add-SectionKv -parsedSectionFile $sf -section $mysqlds -key "server-id" -value (Get-Random)
        $serverId = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "server-id"
    }

    Add-SectionKv -parsedSectionFile $sf -section $mysqlds -key "log-bin"

    if ($rsum.mine -eq "mr") {
        Add-SectionKv -parsedSectionFile $sf -section $mysqlds -key "log-slave-updates" -value "on"
    }

    $logbin = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "log-bin"

    $sf.writeToFile()
    systemctl restart mysqld | Out-Null

    $ef = $myenv.software.textfiles | Where-Object Name -EQ "get-sqlresult.tcl" | Select-Object -First 1 -ExpandProperty content
    Run-String -execute tclsh -content $ef -quotaParameter $paramsHash.newpass "show master status;" | Write-Output -OutVariable fromTcl

    $fromTcl | ? {$_ -match "(${logbin}\.\d+)\s*\|\s*(\d+)\s*\|"} | Select-Object -First 1 | Write-Output -OutVariable matchedLine

    if (!$matchedLine -or ($LASTEXITCODE -ne 0)) {
        Write-Error "show master status doesn't work properly.. $fromTcl"
    }

    $returnToClient = @{}

    if ($rsum.mine -eq "m") {
        $returnToClient.master = @{}
        $returnToClient.master.logname = $Matches[1]
        $returnToClient.master.position = $Matches[2]
        Alter-ResultFile -resultFile $myenv.resultFile -keys "info","master" -value $returnToClient.master
    }
    $R_T_C_B
    $returnToClient | ConvertTo-Json
    $R_T_C_E

}

function Install-Mysql {
    Param($myenv, $paramsHash)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}
    Detect-RunningYum
    $mariadblibs = yum list installed | ? {$_ -match "mariadb-libs"}

    if ($mariadblibs) {
        $mariadblibs -split "\s+" | Select-Object -First 1 | % {yum -y remove $_}
    }
    Get-MysqlRpms $myenv | % {yum -y install $_} | Out-Null

    $rsum = Get-MysqlRoleSum $myenv

    #write my.cnf
    $myenv.software.textfiles | ? {$_.name -eq "my.cnf"} | Select-Object -First 1 -ExpandProperty content | Out-File -FilePath "/etc/my.cnf" -Encoding ascii

    $sf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $mysqlds = "[mysqld]"

    $logError = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "log-error"
    $datadir = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "datadir"
    $pidFile = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "pid-file"
    $socket = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "socket"

    # first comment out log-bin and server-id item.
    Comment-SectionKv -parsedSectionFile $sf -section $mysqlds -key "log-bin"
    Comment-SectionKv -parsedSectionFile $sf -section $mysqlds -key "server-id"
    $sf.writeToFile()

    #$binLog = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "log-bin"
    # we cannot use this server-id value, because all box are same.
    #$serverId = Get-SectionValueByKey -parsedSectionFile $sf -section $mysqlds -key "server-id"

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
    "install-master" {
        $ph = Parse-Parameters $remainingArguments
        $ph | Write-Output
        Install-master $myenv $ph
    }
#    "enableLogBin" {
#        Enable-LogBinAndRecordStatus $myenv
#    }
#    "changePassword" {
#        Set-NewMysqlPassword $myenv @remainingArguments
#    }
#    "start" {
#        if (!(Centos7-IsServiceRunning "mysqld")) {
#            systemctl start mysqld
#        }
#    }
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
