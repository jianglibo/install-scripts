# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script
Param(
    [parameter(Mandatory=$true)]
    $envfile,
    [parameter(Mandatory=$true)]
    $action
)

# insert-common-script-here:powershell/PsCommon.ps1
# Remove-Item /opt/vvvvv/* -Recurse -Force

$envForExec = New-EnvForExec $envfile

function gen-zkcfglines {
    $zkconfigLines = $envForExec.softwareConfig.asHt("zkconfig") | foreach {"{0}={1}" -f $_.Key,$_.Value}
    $srvlines = $envForExec.boxGroup.boxes | Select-Object @{n="serverId"; e={$_.ip.split('\.')[-1]}}, hostname | ForEach-Object {"server.{0}={1}:{2}:{3}" -f (@($_.serverId, $_.hostname) + $softwareConfig.zkports.Split(','))}
    $zkconfigLines + $srvlines
}

switch ($action) {
    "install" {
        $configFileFolder = Split-Path -Parent $envForExec.softwareConfig.jsonObj.configFile
        if (!(Test-Path $configFileFolder)) {
            New-Item -Path $configFileFolder -ItemType Directory | Out-Null
        }
        $dataDir = $envForExec.softwareConfig.jsonObj.zkconfig.dataDir

        if (!(Test-Path $dataDir)) {
            New-Item -Path $dataDir -ItemType Directory | Out-Null
        }
        gen-zkcfglines | Out-File $envForExec.softwareConfig.jsonObj.configFile

        $tgzFile = $envForExec.getUploadedFile()
        if (Test-Path $tgzFile) {
            Run-Tar $tgzFile -DestFolder $envForExec.softwareConfig.jsonObj.binDir
        }
        break
    }
}

"@@success@@"
