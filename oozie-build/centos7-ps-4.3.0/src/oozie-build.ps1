# how to run this script. powershell -File /path/to/this/file.
# ParamTest.ps1 - Show some parameter features
# Param statement must be first non-comment, non-blank line in the script

Param(
    [parameter(Mandatory=$true)]$envfile,
    [parameter(Mandatory=$true)]$action,
    [string]$remainingArguments
)

# insert-common-script-here:powershell/PsCommon.ps1
# insert-common-script-here:powershell/Centos7Util.ps1

Get-Command java

function ConvertTo-DecoratedEnv {
    Param([parameter(ValueFromPipeline=$True)]$myenv)
    $myenv | Add-Member -MemberType NoteProperty -Name InstallDir -Value ($myenv.software.configContent.installDir)
    $myenv | Add-Member -MemberType NoteProperty -Name tgzFile -Value ($myenv.getUploadedFile("oozie-.*\.tar\.gz"))
    $myenv
}

function Get-ZooieBuildDirInfomation {
    Param($myenv)
    $h = @{}
    $h.mkdistro = Get-ChildItem $myenv.InstallDir -Recurse | Where-Object {($_.FullName -replace "\\", "/") -match "/bin/mkdistro\.sh$"} | Select-Object -First 1 -ExpandProperty FullName
    $h.buildHome = $h.mkdistro | Split-Path -Parent | Split-Path -Parent
    $h.tclFile = $h.buildHome | Join-Path -ChildPath "tcl.tcl"
    $h
}

function Start-build {
    Param($myenv)
    $DirInfo = Get-ZooieBuildDirInfomation $myenv
    $tmplog = New-TemporaryFile
    $cmd =  $DirInfo.mkdistro + " -DskipTests >${tmplog} 2>&1"

    "$cmd" | Write-HostIfInTesting
    $success = $false
    $retry = 1
    
    for ($i = 0; $i -lt $retry; $i++) {
        try {
            "$cmd" | Invoke-Expression
        }
        catch {
            "ttttttttt" | Write-HostIfInTesting
            $Error | Write-HostIfInTesting
            "ttttttttt" | Write-HostIfInTesting
            $LASTEXITCODE | Write-HostIfInTesting
        }
        finally {
            $allr = Get-Content $tmplog
            Remove-Item -Force -Path $tmplog
        }
        
        $allr | Write-HostIfInTesting
        $r = $allr | Where-Object {$_ -match "\[INFO\] Apache Oozie Distro .* SUCCESS"} | Select-Object -First 1
        if ($r) {
            $success = $true
            break
        }
    }
    # $mvnRoot = "~/.m2/repository/"
    # $hadoopVersion = "2.4.0"
    # $commonsConfigurationVersion = "1.8"
    # $libext = "/home/jianglibo/ooziedistro/oozie-4.3.0/libext"
    # $extjsUrl = "http://archive.cloudera.com/gplextras/misc/ext-2.2.zip"
    # $extjsUrl -match "([^/]+)$"
    # $extjs = $Matches[1]

    # Get-ChildItem "${mvnRoot}org/apache/hadoop" -Recurse | Where-Object fullName -Match "/$hadoopVersion/" | Where-Object FullName -Match ".*\.jar$" | Where-Object FullName -NotMatch "(-sources\.jar|-tests\.jar)$" | Copy-Item -Destination $libext
    # Get-ChildItem "${mvnRoot}commons-configuration" -Recurse | Where-Object FullName -Match "/$commonsConfigurationVersion/" | Where-Object FullName -Match ".*\.jar$" | Where-Object FullName -NotMatch "(-sources\.jar|-tests\.jar)$" | Copy-Item -Destination $libext
    # Invoke-WebRequest -Uri $extjsUrl -OutFile $extjs
    # Move-Item $extjs $libext


    if (!$success) {
        $allr | Write-Error 
    }

}
function Start-BuildOozieGit {
    Param($myenv)

    if ("OOZIE_BUILD_SERVER" -notin $myenv.myRoles) {
        Write-Output "this box has'nt a role of OOZIE_BUILD_SERVER, skipping installation"
        return
    }
    $myenv.InstallDir | New-Directory
    $cc = $myenv.software.configContent

    if (!($cc.gitUrl -match "([^/]+)\.git$")) {
        Write-Error -Message "gitUrl not end with .git."
    }

    $repoFolder = $myenv.InstallDir | Join-Path -ChildPath $Matches[1]

    $repoFolder | Write-HostIfInTesting

    if (Test-Path $repoFolder) {
        Set-Location $repoFolder
#        git pull $cc.gitUrl $cc.branch
    } else {
        Set-Location $myenv.InstallDir
        git clone $cc.gitUrl
        Set-Location $repoFolder
        git checkout $cc.branch
    }
    Start-build $myenv
}

function Start-BuildOozieTar {
    Param($myenv)

    if ("OOZIE_BUILD_SERVER" -notin $myenv.myRoles) {
        Write-Output "this box has'nt a role of OOZIE_BUILD_SERVER, skipping installation"
        return
    }
    $myenv.InstallDir | New-Directory
    if (Test-Path $myenv.tgzFile -PathType Leaf) {
        Start-Untgz $myenv.tgzFile -DestFolder $myenv.InstallDir | Out-Null
    } else {
        Write-Error ($myenv.tgzFile + " doesn't exists.")
    }
    Start-build $myenv
}

$myenv = New-EnvForExec $envfile | ConvertTo-DecoratedEnv

if ("OOZIE_BUILD_SERVER" -notin $myenv.myRoles) {
    if (!$I_AM_IN_TESTING) {
        Write-Error "not a OOZIE_BUILD_SERVER"
    }
}

switch ($action) {
    "install-with-tar" {
        Start-BuildOozieTar $myenv (ConvertFrom-Base64Parameter $remainingArguments)
    }
    "install-with-git" {
        Start-BuildOozieTar $myenv (ConvertFrom-Base64Parameter $remainingArguments)
    }
    "t" {
        # do nothing
    }
    default {
        Write-Error -Message ("Unknown action {0}"  -f $action)
    }
}

Write-SuccessResult

#     $tcl=@"
#     for {set index 0} { $index < 100 } { incr index } {
#         if {[catch [exec {distroCmd} -DskipTests] o msg]} {
#             continue
#         } else {
#             break
#         }
#     }
# "@
#     $tcl = $tcl -replace "distroCmd",$DirInfo.mkdistro

#     $tcl | Write-HostIfInTesting
#     $tcl | Out-File -FilePath $DirInfo.tclFile -Encoding ascii
#     tclsh $DirInfo.tclFile