$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$result = . "$here\$sut" -envfile $envfile -action t "param0 param1 param2"


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
    It "should return right result" {
        $result | Should Be "param0 param1 param2"
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
        $myenv = New-EnvForExec $envfile | Decorate-Env
        Get-mysqlcnfValue $myenv  "log-error"  | Should Be "/opt/mysqld-usage/mysqld.log"
    }
    It "should install mysql" {
        $myenv = New-EnvForExec $envfile | Decorate-Env
#        remove-mysql -myenv $myenv
#        return
        ($myenv.boxGroup.boxes | % {$_.roles} | ? {($_ -match $MYSQL_MASTER) -and ($_ -notmatch $MYSQL_REPLICA)}).Count | Should Be 1

        # bugs?
        $boxes = @()
        foreach ($box in $myenv.boxGroup.boxes) {
            if (($box.roles -match $MYSQL_MASTER) -and ($box.roles -notmatch $MYSQL_REPLICA)) {
                $boxes += $box
            }
        }
        $boxes.Count | Should Be 1

        ("2016-12-01T11:02:30.947935Z 1 [Note] A temporary password is generated for root@localhost: q&kefv.7emJM" | ? {$_ -match "A temporary password is generated"} | Select-Object -First 1) -replace ".*A temporary password is generated.*?:\s*(.*?)\s*$",'$1' | Should Be "q&kefv.7emJM"

        # ($myenv.boxGroup.boxes | ? {(($_ | Select-Object -ExpandProperty roles) -match $MYSQL_MASTER) -and (($_ | Select-Object -ExpandProperty roles) -notmatch $MYSQL_REPLICA)}).Count | Should Be 1

        $myenv.boxGroup.boxes | % {$_.roles} | ? {$_ -match $MYSQL_REPLICA} | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f "a", "b","c"} | Should Be "CREATE USER 'a'@'c' IDENTIFIED BY 'b'"

        $boxes | % {"CREATE USER '{0}'@'{2}' IDENTIFIED BY '{1}'" -f "a", "b","c"} | Should Be "CREATE USER 'a'@'c' IDENTIFIED BY 'b'"




        if ( ! ( Get-UploadFiles $myenv | Select-Object -First 1 | Test-Path)) {
            Get-UploadFiles -myenv $myenv -OnlyName | Select-Object @{n="Path"; e={Join-Path $testTgzFolder -ChildPath $_}}, @{n="Destination";e={Join-Path $myenv.remoteFolder -ChildPath $_}} | Copy-Item
        }

        $myenv.getUploadedFile() | % {Split-Path -Path $_ -Leaf} | Select-Object @{n="Path"; e={Join-Path $testTgzFolder -ChildPath $_}}, @{n="ChildPath";e={$_}} | Test-Path | ? {! $_} | Should Be $null
        $myenv.remoteFolder | Should Be "/easy-installer/"
        $rpms = (Get-UploadFiles -myenv $myenv | ? {$_ -match "(-server-\d+|-client-\d+|-common-\d+|-libs-\d+).*rpm$"} | Sort-Object) -join ' '
        $rpms | Should Be "/easy-installer/mysql-community-client-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-common-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-libs-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-server-5.7.16-1.el7.x86_64.rpm"

        # (Get-MysqlRpms $myenv) -join " " | Should Be "/easy-installer/mysql-community-client-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-common-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-libs-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-server-5.7.16-1.el7.x86_64.rpm"

        #(yum list installed | ? {$_ -match "mariadb-libs"}) -split "\s+" | Select-Object -First 1 | Should Be "mariadb-libs.x86_64"

        remove-mysql $myenv

        Install-Mysql $myenv

        #@{newpass="aks23A%soid"}

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

        remove-mysql $myenv

        install-master $myenv @{newpass="aks23A%soid";replicauser="repl";replicapass="A2938^%ccy"} | Write-Output -OutVariable fromTcl | Out-Null

        $fromTcl -match $R_T_C_B | Should Be $True
        $fromTcl -match $R_T_C_E | Should Be $True

        $startFlag = $False
        $lines = @()

        foreach ($line in $fromTcl) {
            if ($line -match $R_T_C_E) {
                break
            }

            if ($startFlag) {
                $lines += $line
            }
            if ($line -match $R_T_C_B) {
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
        Run-String -execute tclsh -content $ef -quotaParameter "aks23A%soid" "use mysql;select host,user from user;" | Write-Output -OutVariable fromTcl

        Run-String -execute tclsh -content $ef -quotaParameter "aks23A%soid" "select count(*) from mysql.user where user like '%repl%';" | Write-Output -OutVariable fromTcl
        
        $fromTcl | ? {$_ -match  '^\|\s*(\d+)\s*\|\s*$'} | Select-Object -First 1 | Should Be $True
        $Matches[1] | Should Be "1"

        $LASTEXITCODE | Write-Host
        # | Should Be "Enter password: "
    }
}
