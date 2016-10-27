$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve
$resutl = . "$here\$sut" -envfile $envfile -action install



Describe "code" {

    It "should deco env" {
        $decorated = (New-EnvForExec $envfile | Decorate-Env)
        $decorated.DataDir | Should Be "/var/lib/zookeeper/"
        $decorated.configFolder -match "^(\\|/)var$" | Should Be $True
        $decorated.configFile | Should Be "/var/zoo.cfg"
        $decorated.binDir | Should Be "/opt/zookeeper"
        $decorated.serviceLines -join "," | Should Be "server.10=192.168.2.10:2888:3888,server.11=a1.host.name:2888:3888,server.14=a2.host.name:2888:3888"
        $decorated.zkconfigLines -join "," | Should Be "clientPort=2181,dataDir=/var/lib/zookeeper/,initLimit=5,syncLimit=2,tickTime=1999"
    }

    It "should create files and folders" {
        $decorated = (New-EnvForExec $envfile | Decorate-Env)
        Test-Path $decorated.DataDir | Should Be $True
        Test-Path $decorated.configFolder | Should Be $True
        Test-Path $decorated.configFile | Should Be $True
        Test-Path $decorated.binDir | Should Be $True
    }
}
