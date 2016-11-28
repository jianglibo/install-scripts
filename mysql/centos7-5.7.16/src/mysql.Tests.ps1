$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve

. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve

$resutl = . "$here\$sut" -envfile $envfile -action t


function get-mysqlcnfValue {
    Param($myenv, $key)
        $tmpfile = New-TemporaryFile

        $myenv.software.textfiles | ? name -EQ "my.cnf" | Select-Object -First 1 -ExpandProperty content | Out-File -FilePath $tmpfile

        $sf = New-SectionKvFile -FilePath $tmpfile

        $sf.getValue("[mysqld]", $key)

        Remove-Item -Path $tmpfile -Force
}

Describe "code" {
    It "should parse my.cnf" {
        $myenv = New-EnvForExec $envfile | Decorate-Env
        get-mysqlcnfValue $myenv  "log-error"  | Should Be "/var/log/mysqld.log"
    }
    It "should install mysql" {
        $myenv = New-EnvForExec $envfile | Decorate-Env
        
        if ( ! ( Get-UploadFiles $myenv | Select-Object -First 1 | Test-Path)) {
            Get-UploadFiles -myenv $myenv -OnlyName | Select-Object @{n="Path"; e={Join-Path $testTgzFolder -ChildPath $_}}, @{n="Destination";e={Join-Path $myenv.remoteFolder -ChildPath $_}} | Copy-Item
        }

        $myenv.getUploadedFile() | % {Split-Path -Path $_ -Leaf} | Select-Object @{n="Path"; e={Join-Path $testTgzFolder -ChildPath $_}}, @{n="ChildPath";e={$_}} | Test-Path | ? {! $_} | Should Be $null
        $myenv.remoteFolder | Should Be "/easy-installer/"
        $rpms = (Get-UploadFiles -myenv $myenv | ? {$_ -match "(-server-\d+|-client-\d+|-common-\d+|-libs-\d+).*rpm$"} | Sort-Object) -join ' '
        $rpms | Should Be "/easy-installer/mysql-community-client-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-common-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-libs-5.7.16-1.el7.x86_64.rpm /easy-installer/mysql-community-server-5.7.16-1.el7.x86_64.rpm"

        #(yum list installed | ? {$_ -match "mariadb-libs"}) -split "\s+" | Select-Object -First 1 | Should Be "mariadb-libs.x86_64"
#        $revRpms = Get-MysqlRpms $myenv | % {$_ -replace ".*/(.*)-[^-]+$", '$1'}
#        [array]::reverse(($revRpms))
#        $revRpms | % {yum -y remove $_}
#        get-mysqlcnfValue $myenv "datadir" | Remove-Item -Recurse -Force

        Install-Mysql $myenv
    }
}
