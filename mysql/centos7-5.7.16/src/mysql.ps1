# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
# runuser -s /bin/bash -c "/opt/hadoop/hadoop-2.7.3/bin/hdfs dfs -mkdir -p /user/hbase" hdfs
# runuser -s /bin/bash -c "/opt/hadoop/hadoop-2.7.3/bin/hdfs dfs -chown hbase /user/hbase" hdfs

Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [parameter(Mandatory=$true)]
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
    # piddir and logdir
    $envvs = $myenv.software.configContent.asHt("envvs")
    $myenv
}

function Install-Mysql {
    Param($myenv)
    Write-ConfigFiles -myenv $myenv
}

function Get-MysqlRpms {
    Param($myenv)
    Get-UploadFiles -myenv $myenv | ? {$_ -match "-common-\d+.*rpm$"}
    Get-UploadFiles -myenv $myenv | ? {$_ -match "-libs-\d+.*rpm$"}
    Get-UploadFiles -myenv $myenv | ? {$_ -match "-client-\d+.*rpm$"}
    Get-UploadFiles -myenv $myenv | ? {$_ -match "-server-\d+.*rpm$"}
}

function Write-ConfigFiles {
    Param($myenv)
    $resultHash = @{}
    $resultHash.env = @{}
    $resultHash.info = @{}

#    $myenv.software.textfiles | ForEach-Object {
#        $_.content -split '\r?\n|\r\n?' | Out-File -FilePath ($DirInfo.hadoopDir | Join-Path -ChildPath $_.name) -Encoding ascii
#    } | Out-Null

    $mariadblibs = yum list installed | ? {$_ -match "mariadb-libs"}

    if ($mariadblibs) {
        $mariadblibs -split "\s+" | Select-Object -First 1 | % {yum -y remove $_}
    }

    Get-MysqlRpms $myenv | % {yum -y install $_} | Out-Null
    
    # start mysqld
    systemctl enable mysqld | Out-Null
    systemctl start mysqld | Out-Null

    $ef = $myenv.software.textfiles | Where-Object Name -EQ "change-init-pass.tcl" | Select-Object -First 1 -ExpandProperty content

    $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"
    
    $initpassword = (Get-Content $mycnf.getValue("[mysqld]", "log-error") | ? {$_ -match "A temporary password is generated"} | Select-Object -First 1) -replace ".*:\s*(.*?)\s*$",'$1'

    $randp = Get-RandomPassword -len 12

    "--------------****-------------", "generate a random password for you: $randp", "--------------****-------------" | Write-Output

    Run-String -execute tclsh -content $ef "$initpassword" "$randp"

    $resultHash | ConvertTo-Json | Write-Output -NoEnumerate | Out-File $myenv.resultFile -Force -Encoding ascii
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
        Install-Hadoop $myenv
    }
    "start" {
        start-dfs $myenv start
    }
    "stop" {
        start-yarn $myenv start
    }
    "t" {
        # do nothing
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Print-Success
