#$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$here = $PSScriptRoot
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$result = . "$here\$sut" -envfile $envfile -action t (ConvertTo-Base64String "param0 param1 param2")

$I_AM_IN_TESTING = $True

<#
    MASTER_BIND = 'interface_name'
  | MASTER_HOST = 'host_name'
  | MASTER_USER = 'user_name'
  | MASTER_PASSWORD = 'password'
  | MASTER_PORT = port_num
  | MASTER_CONNECT_RETRY = interval
  | MASTER_RETRY_COUNT = count
  | MASTER_DELAY = interval
  | MASTER_HEARTBEAT_PERIOD = interval
  | MASTER_LOG_FILE = 'master_log_name'
  | MASTER_LOG_POS = master_log_pos
  | MASTER_AUTO_POSITION = {0|1}
  | RELAY_LOG_FILE = 'relay_log_name'
  | RELAY_LOG_POS = relay_log_pos
  | MASTER_SSL = {0|1}
  | MASTER_SSL_CA = 'ca_file_name'
  | MASTER_SSL_CAPATH = 'ca_directory_name'
  | MASTER_SSL_CERT = 'cert_file_name'
  | MASTER_SSL_CRL = 'crl_file_name'
  | MASTER_SSL_CRLPATH = 'crl_directory_name'
  | MASTER_SSL_KEY = 'key_file_name'
  | MASTER_SSL_CIPHER = 'cipher_list'
  | MASTER_SSL_VERIFY_SERVER_CERT = {0|1}
  | MASTER_TLS_VERSION = 'protocol_list'
  | IGNORE_SERVER_IDS = (server_id_list)
#>
function Get-MysqlcnfValue {
    Param($myenv, $key)
        $tmpfile = New-TemporaryFile

        $myenv.software.textfiles | ? name -EQ "my.cnf" | Select-Object -First 1 -ExpandProperty content | Out-File -FilePath $tmpfile

        $sf = New-SectionKvFile -FilePath $tmpfile

        Get-SectionValueByKey -parsedSectionFile $sf -section "[mysqld]" -key $key
        Remove-Item -Path $tmpfile -Force
}

function remove-mysql {
    Param($myenv)
    if (Centos7-IsServiceRunning "mysqld") {
        systemctl stop "mysqld"
    }

    if (Test-Path $myenv.resultFile) {
        Remove-Item -Path $myenv.resultFile -Force
    }

    $revRpms = Get-MysqlRpms $myenv | % {$_ -replace ".*/(.*)-[^-]+$", '$1'}
    [array]::reverse(($revRpms))
    $revRpms | % {yum -y remove $_} | Out-Null

    if (get-mysqlcnfValue $myenv "datadir" | Test-Path) {
        get-mysqlcnfValue $myenv "datadir" | Remove-Item -Recurse -Force
    }
    if (get-mysqlcnfValue $myenv "log-error" | Test-Path) {
        get-mysqlcnfValue $myenv "log-error" | Remove-Item -Force
    }
}

Describe "code" {
    It "should get-tclcontent" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        Get-TclContent -myenv $myenv -filename "get-sqlresult.tcl" | Should Be $True
    }
    It "should return right result" {
        $result | Should Be "param0 param1 param2"

        $p = ConvertTo-Base64String '{"a":1, "b": "xx"}' | ConvertFrom-Base64Parameter
        $p.a | Should Be 1
        $p.b | Should Be "xx"
    }
    It "should handle remaining parameters" {
        function t-t {
            Param([parameter(ValueFromRemainingArguments)]$remainingArguments)
            $remainingArguments | Select-Object -First 1
        }
        function t {
            Param([parameter(ValueFromRemainingArguments)]$remainingArguments)
            t-t @remainingArguments
        }

        function tt {
            Param([parameter(ValueFromRemainingArguments)]$remainingArguments)
            $remainingArguments
        }

        function ttt {
            Param([parameter(ValueFromRemainingArguments)]$remainingArguments)
            $remainingArguments.getType()
        }

        t a b c | Should Be "a"

        tt | Should Be $null

        ttt a | Should Be System.Collections.Generic.List[System.Object]
    }
    It "should parse my.cnf" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        Get-mysqlcnfValue $myenv  "log-error"  | Should Be "/opt/mysqld-usage/mysqld.log"
    }
    It "should handle misc" {
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

        ($myenv.boxGroup.boxes | % {$_.roles} | ? {($_ -match $MYSQL_MASTER) -and ($_ -notmatch $MYSQL_REPLICA)}).Count | Should Be 1
        ([array]($myenv.boxGroup.boxes | ? {($_.roles -match $MYSQL_MASTER) -and ($_.roles -notmatch $MYSQL_REPLICA)})).Count | Should Be 1
        $boxes = @()
        foreach ($box in $myenv.boxGroup.boxes) {
            if (($box.roles -match $MYSQL_MASTER) -and ($box.roles -notmatch $MYSQL_REPLICA)) {
                $boxes += $box
            }
        }
        $boxes.Count | Should Be 1

        ("2016-12-01T11:02:30.947935Z 1 [Note] A temporary password is generated for root@localhost: q&kefv.7emJM" | ? {$_ -match "A temporary password is generated"} | Select-Object -First 1) -replace ".*A temporary password is generated.*?:\s*(.*?)\s*$",'$1' | Should Be "q&kefv.7emJM"
        $myenv.boxGroup.boxes | % {$_.roles} | ? {$_ -match $MYSQL_REPLICA} | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f "a", "b","c"} | Should Be "CREATE USER 'a'@'c' IDENTIFIED BY 'b'"

        $boxes | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f "a", "b","c"} | Should Be "CREATE USER 'a'@'c' IDENTIFIED BY 'b'"

        if ( ! ( Get-UploadFiles $myenv | Select-Object -First 1 | Test-Path)) {
            Get-UploadFiles -myenv $myenv -OnlyName | Select-Object @{n="Path"; e={Join-Path $testTgzFolder -ChildPath $_}}, @{n="Destination";e={Join-Path $myenv.remoteFolder -ChildPath $_}} | Copy-Item
        }

        $myenv.getUploadedFile() | % {Split-Path -Path $_ -Leaf} | Select-Object @{n="Path"; e={Join-Path $testTgzFolder -ChildPath $_}}, @{n="ChildPath";e={$_}} | Test-Path | ? {! $_} | Should Be $null
        $myenv.remoteFolder | Should Be "/easy-installer/"
        $rpms = (Get-UploadFiles -myenv $myenv | ? {$_ -match "(-server-\d+|-client-\d+|-common-\d+|-libs-\d+).*rpm$"} | Sort-Object) -join ' '
        $rpms | Should Be "/easy-installer/mysql-community-client-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-common-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-libs-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-server-5.7.16-1.el7.x86_64.rpm"
    }
    It "should install-replica" {
        $envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec-r.json -Resolve
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        remove-mysql $myenv
        $newpass = "uvks^27A`"123'"
        $replicapass = "kls@9s9Y28s"
        install-replica $myenv @{newpass="$newpass";replicauser="repl";replicapass=$replicapass} | Write-Host

        $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"
        $mysqlds = "[mysqld]"

        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-bin" | Should Be $null
        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-slave-updates" | Should Be $null

        Run-SQL -env $myenv -pass $newpass -sqls  "select count(*) from mysql.user where user like '%repl%';" | Write-Output -OutVariable fromTcl

        $fromTcl | Write-Host
        $fromTcl | ? {$_ -match  '^\|\s*(\d+)\s*\|\s*$'} | Select-Object -First 1 | Should Be $True
        $Matches[1] | Should Be "0"
    }
    It "should install-masterreplica" {
        return
        $envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec-mr.json -Resolve
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        remove-mysql $myenv
        $newpass = "uvks^27A`"123'"
        $replicapass = "kls@9s9Y28s"
        install-masterreplica $myenv @{newpass="$newpass";replicauser="repl";replicapass=$replicapass} | Write-Host

        $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"
        $mysqlds = "[mysqld]"

        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-bin" | Should Be "mysql-bin"
        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-slave-updates" | Should Be "on"

        Run-SQL -env $myenv -pass $newpass -sqls  "select count(*) from mysql.user where user like '%repl%';" | Write-Output -OutVariable fromTcl

        $fromTcl | Write-Host
        $fromTcl | ? {$_ -match  '^\|\s*(\d+)\s*\|\s*$'} | Select-Object -First 1 | Should Be $True
        $Matches[1] | Should Be "1"
    }
    It "should install-master" {
    return
        return
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        remove-mysql $myenv
        $newpass = "uvks^27A`"123'"
        $replicapass = "kls@9s9Y28s"

        install-master $myenv @{newpass="$newpass";replicauser="repl";replicapass=$replicapass} | Write-Output -OutVariable fromTcl | Out-Null

        $fromTcl -match $_INSTALL_RESULT_BEGIN_ | Should Be $True
        $fromTcl -match $_INSTALL_RESULT_END_ | Should Be $True

        $startFlag = $False
        $lines = @()

        foreach ($line in $fromTcl) {
            if ($line -match $_INSTALL_RESULT_END_) {
                break
            }

            if ($startFlag) {
                $lines += $line
            }
            if ($line -match $_INSTALL_RESULT_BEGIN_) {
                $startFlag = $True
            }
        }

        "***********************" | Write-Host
        $lines | Write-Host
        "***********************" | Write-Host

        $returnToClient = $lines | ConvertFrom-Json

        $returnToClient.master.logname -match ((Get-MysqlcnfValue -myenv $myenv -key "log-bin") + "\.\d+") | Should Be $True
        $returnToClient.master.position -match "\d+" | Should Be $True

        $ef = $myenv.software.textfiles | Where-Object Name -EQ "get-sqlresult.tcl" | Select-Object -First 1 -ExpandProperty content

        Run-SQL -env $myenv -pass $newpass -sqls "use mysql;select host,user from user;" | Write-Output -OutVariable fromTcl
        Run-SQL -env $myenv -pass $newpass -sqls  "select count(*) from mysql.user where user like '%repl%';" | Write-Output -OutVariable fromTcl

        $fromTcl | Write-Host
        $fromTcl | ? {$_ -match  '^\|\s*(\d+)\s*\|\s*$'} | Select-Object -First 1 | Should Be $True
        $Matches[1] | Should Be "2"

        $LASTEXITCODE | Write-Host
    }
    It "should install mysql" {
        return
        remove-mysql $myenv
        $myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv
        remove-mysql $myenv
        Install-Mysql $myenv
        Set-NewMysqlPassword $myenv "aks23A%soid"
        $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"
        $mysqlds = "[mysqld]"
        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-bin" | Should Be $null
        Add-SectionKv -parsedSectionFile $mycnf -section $mysqlds -key "log-bin"
        $lb = Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-bin"
        $lb | Should Be "mysql-bin"
        Comment-SectionKv -parsedSectionFile $mycnf -section $mysqlds -key "log-bin"
        $mycnf.writeToFile()
        $datadir = Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "datadir"
        Get-ChildItem -Path $datadir | ? Name -Match "$lb\.\d+$" | Should Be $null

        Enable-LogBinAndRecordStatus $myenv @{newpass="aks23A%soid";replicauser="repl";replicapass="A2938^%ccy"} (Get-MysqlRoleSum $myenv)

        $mycnf = New-SectionKvFile -FilePath "/etc/my.cnf"

        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "log-bin"  | Should Be "mysql-bin"
        Get-SectionValueByKey -parsedSectionFile $mycnf -section $mysqlds -key "server-id"  | Should Be $True

        (Get-ChildItem -Path $datadir | ? Name -Match "$lb\.\d+$").Count -gt 0 | Should Be $True
    }
}
