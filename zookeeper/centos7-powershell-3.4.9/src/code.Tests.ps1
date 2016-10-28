$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath

$envfile = Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve
$resutl = . "$here\$sut" -envfile $envfile -action t

<#
ZOOBINDIR=/opt/zookeeper/zookeeper-3.4.9/bin
ZOOBINDIR,ZOOCFGDIR, insert to /opt/zookeeper/zookeeper-3.4.9/bin/zkEnv.sh before line ZOOBINDIR="${ZOOBINDIR:-/usr/bin}"
others can put into : "${ZOOCFGDIR}/zookeeper-env.sh": ZOOCFG,ZOO_LOG_DIR,ZOO_LOG4J_PROP, even JAVA_HOME
#>


Describe "code" {

    It "should deco env" {
        $decorated = (New-EnvForExec $envfile | Decorate-Env)
        $decorated.DataDir | Should Be "/var/lib/zookeeper/"
        ($decorated.configFolder -replace '\\','/') | Should Be "/var/zookeeper"
        $decorated.configFile | Should Be "/var/zookeeper/zoo.cfg"
        $decorated.binDir | Should Be "/opt/zookeeper"
        $decorated.serviceLines -join "," | Should Be "server.110=192.168.33.110:2888:3888,server.111=a1.host.name:2888:3888,server.112=a2.host.name:2888:3888"
        $decorated.zkconfigLines -join "," | Should Be "clientPort=2181,dataDir=/var/lib/zookeeper/,initLimit=5,syncLimit=2,tickTime=1999"
    }
    It "should be installed" {
        if (!$IsLinux) {
            return
        }
        $decorated = (New-EnvForExec $envfile | Decorate-Env)
        $fixtureFile = Join-Path $testTgzFolder -ChildPath $decorated.getUploadedFile("", $True)
        $tgzFile = $decorated.getUploadedFile()

        if (-not (Test-Path $tgzFile)) {
            if (Test-Path $fixtureFile -PathType Leaf) {
                Copy-Item $fixtureFile $tgzFile
            }
        }

        Install-Zk $decorated
        Test-Path $decorated.binDir | Should Be $True
        Test-Path $decorated.DataDir | Should Be $True
        Test-Path $decorated.configFolder | Should Be $True
        Test-Path $decorated.configFile | Should Be $True
        $decorated.resultFile -replace "\\", "/" | Should Be "/opt/easyinstaller/results/zookeeper-CentOs7-powershell-3.4.9/easyinstaller-result.json"

        (Get-Content $decorated.resultFile | ConvertFrom-Json).executable | Should be "/opt/zookeeper/zookeeper-3.4.9/bin/zkServer.sh"

        $zkEnv = (Get-ChildItem -Path $myenv.binDir -Recurse -Filter "zkEnv.sh" | Where-Object {($_.FullName -replace "\\","/") -match "/bin/zkEnv.sh$"}).FullName
        
    }
}
