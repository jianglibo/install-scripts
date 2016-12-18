## Shared script snippets and template for [easyinstaller](https://github.com/jianglibo/easyinstaller)

The code under src/main/resources will published as a jar, used as a jar dependency in easyinstaller project. Others folder are separate install script project, please look into settings.gradle file, it lists all subprojects. Run .\gradlew will generate packaged install scripts under build folder, packaged as zip file which can be imported into easyinstaller from web ui.

## How to write, test install script to be used in easyinstaller.

Look into "zookeeper/centos7-powershell-3.4.9" folder, this is the layout of the project. The most important file is ***description.yml***. When processing, we first find this file, other file's position relative to this file. For example, when generate fixtures from easyinstaller ui, you provide the folder name which contains description.yml (in any child depth), easyinstaller will find the sample-env folder relative to description.yml and generate fixtures and put it under fixtures folder.

bellow is a sample install script:
```powershell
Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [parameter(Mandatory=$true)]
    $action
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

function ConvertTo-DecoratedEnv {
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
    $myenv | Add-Member -MemberType NoteProperty -Name DataDir -Value ($myenv.software.configContent.zkconfig.dataDir)

    $myenv | Add-Member -MemberType NoteProperty -Name configFolder -Value (Split-Path -Parent $myenv.software.configContent.configFile)
    $myenv | Add-Member -MemberType NoteProperty -Name configFile -Value $myenv.software.configContent.configFile
    $myenv | Add-Member -MemberType NoteProperty -Name binDir -Value $myenv.software.configContent.binDir
    $myenv | Add-Member -MemberType NoteProperty -Name logDir -Value $myenv.software.configContent.logDir
    $myenv | Add-Member -MemberType NoteProperty -Name pidFile -Value $myenv.software.configContent.pidFile
    $myenv | Add-Member -MemberType NoteProperty -Name logProp -Value $myenv.software.configContent.logProp
    $myenv
}
```

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1
this two lines will be substituted by shared scripts.

this is test file:
```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$testTgzFolder = Join-Path -Path $here -ChildPath "../../../tgzFolder" -Resolve

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath

. (Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\CentOs7Util.Ps1" -Resolve)
```

Here we direct source these two files.

## Magic behind "insert-common-script-here:powershell/PsCommon.ps1"

When easyinstaller meet this pattern in script file, It will search in order:

* if you use full path format, just find it there. for example: insert-common-script-here:classpath:powershell/PsCommon.ps1, insert-common-script-here:file:///powershell/PsCommon.ps1, insert-common-script-here:http://xx.xx.xx/powershell/PsCommon.ps1,
* in a configurable folder, if there sits "powershell/PsCommon.ps1"
* other classpath you config
* java classpath "com/jianglibo/easyinstaller/scriptsnippets/" + "powershell/PsCommon.ps1"
