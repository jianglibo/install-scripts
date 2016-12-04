# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# CREATE USER 'jeffrey'@'localhost' IDENTIFIED BY 'mypass';
# ALTER USER 'jeffrey'@'localhost'IDENTIFIED BY 'mypass';
# ALTER USER USER() IDENTIFIED BY 'mypass'; // change own password.
# SET PASSWORD FOR 'jeffrey'@'localhost' = PASSWORD('mypass');

# when this file got parameter, bash escape has done. for exampe '"'"' already change to '

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

$MYSQL_MASTER = "MYSQL_MASTER"
$MYSQL_REPLICA = "MYSQL_REPLICA"

function Decorate-Env {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    # piddir and logdir
    $envvs = $myenv.software.configContent.asHt("envvs")
    $myenv
}

function Run-SQL {
    Param($myenv, $pass, $sqls)
    $fn = "get-sqlresult.tcl"
    $code = Get-TclContent -myenv $myenv -filename $fn
    Run-Tcl -content $code $pass $sqls *>&1 | Write-Output -NoEnumerate -OutVariable fromRunSql
    if ($LASTEXITCODE -ne 0) {
        Write-Error "execute '$fn' failed. $fromRunSql"
    }
    $fromRunSql | Write-HostIfInTesting
    $fromRunSql | Write-OutputIfTesting
    $fromRunSql
}

function Get-MysqlRoleSum {
    Param($myenv)
    $rh = @{}

    # mater-replica boxes
    [array]$mrboxes = $myenv.boxGroup.boxes | ? {($_.roles -match $MYSQL_MASTER) -and ($_.roles -match $MYSQL_REPLICA)}
    if ($mrboxes.Count -gt 1) {
        Write-Error "There can only be one server with both MYSQL_MASTER and MYSQL_REPLICA roles."
    }

    # master boxes
    [array]$mboxes = $myenv.boxGroup.boxes | ? {($_.roles -match $MYSQL_MASTER) -and ($_.roles -notmatch $MYSQL_REPLICA)}
    if ($mboxes.Count -ne 1) {
        Write-Error "There can only be one server with MYSQL_MASTER roles, but ${mboxes.Count}"
    }

    if ($mrboxes.Count -eq 1) {
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

   if (Test-Path $myenv.resultFile) {
      $resultHash = Get-Content $myenv.resultFile | ConvertFrom-Json

      if ($resultHash.info.installation.completed) {
        Write-Output "mysqld already installed."
        return
      }
   }

   Install-Mysql $myenv $paramsHash
   Set-NewMysqlPassword $myenv $paramsHash.newpass
   # before enable log-bin, create replica users first, prevent it from copy to other servers.
   if ($rsum.type -eq "chained") { # master only need create one replica user.
      $boxes = $myenv.boxGroup.boxes | ? {($_.roles -match $MYSQL_MASTER) -and ($_.roles -match $MYSQL_REPLICA)}
   } else { # create replica users for all slaves.
      $boxes = $myenv.boxGroup.boxes | ? {$_.roles -notmatch $MYSQL_MASTER}
   }
   $sqls = ($boxes | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f $paramsHash.replicauser, ($paramsHash.replicapass -replace "'","\'"),$_.hostname}) -join ";"
   Run-SQL -myenv $myenv -pass $paramsHash.newpass -sqls $sqls | Write-Output -OutVariable fromTcl
   Enable-LogBinAndRecordStatus $myenv $paramsHash $rsum
   Alter-ResultFile -resultFile $myenv.resultFile -keys "info","installation","completed" -value $True
}

function install-masterreplica {
   Param($myenv, $paramsHash)

   $rsum = Get-MysqlRoleSum -myenv $myenv

   if ($rsum.mine -ne "mr") {
       "this server not configurated as masterreplic...., skip installation."
        return
   }
   if (!$paramsHash.newpass -or !$paramsHash.replicauser -or !$paramsHash.replicapass) {
      Write-Error "For install action, newpass,replicauser,replicapass are mandontory."
   }

   # if master hadn't installed skip it.
   if (!$myenv.boxGroup.installResults.master) {
        Write-Output "Please install master first!"
        return
   }

   if (Test-Path $myenv.resultFile) {
      $resultHash = Get-Content $myenv.resultFile | ConvertFrom-Json
      if ($resultHash.info.installation.completed) {
        Write-Output "mysqld already installed."
        return
      }
   }

   Install-Mysql $myenv $paramsHash
   Set-NewMysqlPassword $myenv $paramsHash.newpass
   # before enable log-bin, create replica users first, prevent it from copy to replica servers.
   [array]$boxes = $myenv.boxGroup.boxes | ? {($_.roles -notmatch $MYSQL_MASTER) -and ($_.roles -match $MYSQL_REPLICA)}
   # because this is a master-replica, all replica account create here, except itself.
   $sqls = ($boxes | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f $paramsHash.replicauser, ($paramsHash.replicapass -replace "'","\'"), $_.hostname}) -join ";"

   Run-SQL -myenv $myenv -pass $paramsHash.newpass -sqls $sqls | Write-Output -OutVariable fromTcl | Out-Null
   Enable-LogBinAndRecordStatus $myenv $paramsHash $rsum

   # get master host
   $masterBox = $myenv.boxGroup.boxes | ? {($_.roles -match $MYSQL_MASTER) -and ($_.roles -notmatch $MYSQL_REPLICA)} | Select-Object -First 1

   $sqls = "CHANGE MASTER TO MASTER_HOST='{0}', MASTER_USER='{1}', MASTER_PASSWORD='{2}', MASTER_LOG_FILE='{3}', MASTER_LOG_POS={4};" -f $masterBox.hostname, $paramsHash.replicauser, ($paramsHash.replicapass -replace "'", "\'"), $myenv.boxGroup.installResults.master.logname, $myenv.boxGroup.installResults.master.position
   # $myenv.boxGroup.installResults.master.logname, position
   Run-SQL -myenv $myenv -pass $paramsHash.newpass -sqls $sqls | Write-Output -OutVariable fromTcl | Out-Null

   Alter-ResultFile -resultFile $myenv.resultFile -keys "info","installation","completed" -value $True
}

function Get-MysqlRpms {
    Param($myenv)
    Get-UploadFiles $myenv | ? {$_ -match "-common-\d+.*rpm$"}
    Get-UploadFiles $myenv | ? {$_ -match "-libs-\d+.*rpm$"}
    Get-UploadFiles $myenv | ? {$_ -match "-client-\d+.*rpm$"}
    Get-UploadFiles $myenv | ? {$_ -match "-server-\d+.*rpm$"}
}


function Set-NewMysqlPassword {
    Param($myenv,$newpassword)

    $resultHash = Get-Content $myenv.resultFile | ConvertFrom-Json
    if ($resultHash.info.installation.initPasswordReseted) {
       return
    }
    $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $initpassword = (Get-Content (Get-SectionValueByKey -parsedSectionFile $mycnf -section "[mysqld]" -key "log-error") | ? {$_ -match "A temporary password is generated"} | Select-Object -First 1) -replace ".*A temporary password is generated.*?:\s*(.*?)\s*$",'$1'
    $code = Get-TclContent -myenv $myenv -filename "change-init-pass.tcl"
    Run-Tcl -content $code "$initpassword" "$newpassword" | Write-Output -OutVariable fromTcl | Out-Null

    Alter-ResultFile -resultFile $myenv.resultFile -keys "info","installation","initPasswordReseted" -value $True
}

function Enable-LogBinAndRecordStatus {
    Param($myenv, $paramsHash, $rsum)

    $resultHash = Get-Content $myenv.resultFile | ConvertFrom-Json

    if ($resultHash.info.installation.logBinEnabled) {
        Write-Error "logbin already enabled. skipping....."
    }

    $myenf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $mysqlds = "[mysqld]"

    $serverId = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "server-id"

    if (! $serverId) {
        Add-SectionKv -parsedSectionFile $myenf -section $mysqlds -key "server-id" -value (Get-Random)
        $serverId = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "server-id"
    }

    Add-SectionKv -parsedSectionFile $myenf -section $mysqlds -key "log-bin"

    if ($rsum.mine -eq "mr") {
        Add-SectionKv -parsedSectionFile $myenf -section $mysqlds -key "log-slave-updates" -value "on"
    }

    $myenf.writeToFile()
    $logbin = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "log-bin"

    systemctl restart mysqld

    Run-SQL -myenv $myenv -pass $paramsHash.newpass -sqls "show master status;" | Write-Output -OutVariable fromTcl

    $fromTcl | ? {$_ -match "(${logbin}\.\d+)\s*\|\s*(\d+)\s*\|"} | Select-Object -First 1 | Write-Output -OutVariable matchedLine

    if (!$matchedLine -or ($LASTEXITCODE -ne 0)) {
        Write-Error "show master status doesn't work properly.. ${fromTcl}, and matchedLine is: ${matchedLine}, and lastexitcode is: $LASTEXITCODE"
    }

    $returnToClient = @{}

    if ($rsum.mine -eq "m") {
        $returnToClient.master = @{}
        $returnToClient.master.logname = $Matches[1]
        $returnToClient.master.position = $Matches[2]
        Alter-ResultFile -resultFile $myenv.resultFile -keys "info","master" -value $returnToClient.master
    }
    if ($rsum.mine -eq "mr") {
        $returnToClient.masterreplica = @{}
        $returnToClient.masterreplica.logname = $Matches[1]
        $returnToClient.masterreplica.position = $Matches[2]
        Alter-ResultFile -resultFile $myenv.resultFile -keys "info","masterreplica" -value $returnToClient.masterreplica
        # need execute change master to statement.
    }
    $R_T_C_B
    $returnToClient | ConvertTo-Json
    $R_T_C_E
    Alter-ResultFile -resultFile $myenv.resultFile -keys "info","installation", "logBinEnabled" -value $True
}

$cnt = 0

function Get-TclContent {
    Param($myenv,$filename)
    $ef = $myenv.software.textfiles | ? {$_.name -eq $filename} | Select-Object -First 1 -ExpandProperty content
    if ($I_AM_IN_TESTING) {
        $localTcl = $PSScriptRoot | Join-Path -ChildPath configfiles | Join-Path -ChildPath $filename
        if (Test-Path $localTcl) {
            [string]$ef = (Get-Content $localTcl) -join "`n"
        }
    }
    $ef
}

function Install-Mysql {
    Param($myenv, $paramsHash)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}

    if (Test-Path $myenv.resultFile) {
        if ((Get-Content $myenv.resultFile | ConvertFrom-Json).info.installation.installed) {
            return
        }
    }

    Detect-RunningYum
    $mariadblibs = yum list installed | ? {$_ -match "mariadb-libs"}

    if ($mariadblibs) {
        $mariadblibs -split "\s+" | Select-Object -First 1 | % {yum -y remove $_}
    }
    Get-MysqlRpms $myenv | % {yum -y install $_} | Out-Null

    $rsum = Get-MysqlRoleSum $myenv

    #write my.cnf
    $myenv.software.textfiles | ? {$_.name -eq "my.cnf"} | Select-Object -First 1 -ExpandProperty content | Out-File -FilePath "/etc/my.cnf" -Encoding ascii

    $myenf = New-SectionKvFile -FilePath "/etc/my.cnf"
    $mysqlds = "[mysqld]"

    $logError = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "log-error"
    $datadir = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "datadir"
    $pidFile = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "pid-file"
    $socket = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "socket"
    $port = Choose-FirstTrueValue (Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "port") "3306"

    Centos7-FileWall -ports $port

    # first comment out log-bin and server-id item.
    Comment-SectionKv -parsedSectionFile $myenf -section $mysqlds -key "log-bin"
    Comment-SectionKv -parsedSectionFile $myenf -section $mysqlds -key "server-id"
    $myenf.writeToFile()

    #$binLog = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "log-bin"
    # we cannot use this server-id value, because all box are same.
    #$serverId = Get-SectionValueByKey -parsedSectionFile $myenf -section $mysqlds -key "server-id"

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
    systemctl enable mysqld | Write-Output -OutVariable fromSh | Out-Null
    systemctl start mysqld | Write-Output -OutVariable fromSh | Out-Null

    if ($LASTEXITCODE -ne 0 ) {
        Write-Error "Start Mysqld failed. $fromSh"
    }

    $resultHash | ConvertTo-Json | Out-File -FilePath  $myenv.resultFile -Force -Encoding ascii
    # write app.sh, this script will be invoked by root user.
    "#!/usr/bin/env bash",(New-ExecuteLine $myenv.software.runner -envfile $envfile -code $PSCommandPath) | Out-File -FilePath $myenv.appFile -Encoding ascii
    chmod u+x $myenv.appFile
    Alter-ResultFile -resultFile $myenv.resultFile -keys "info","installation","installed" -value $True
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
        Install-master $myenv (Parse-Parameters $remainingArguments)
    }
    "install-masterreplica" {
        install-masterreplica $myenv (Parse-Parameters $remainingArguments)
    }
    "install-replica" {
        install-replica $myenv (Parse-Parameters $remainingArguments)
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
        Parse-Parameters $remainingArguments
        return
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success
