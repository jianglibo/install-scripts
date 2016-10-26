$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'

$commonPath = Join-Path -Path $here -ChildPath "\..\..\..\src\main\resources\com\jianglibo\easyinstaller\scriptsnippets\powershell\PsCommon.Ps1" -Resolve
. $commonPath

. "$here\$sut" -envfile (Join-Path -Path (Split-Path -Path $here -Parent) -ChildPath fixtures/envforcodeexec.json -Resolve) -action t



Describe "code" {
    It "should work gen-zkcfglines" {
        (gen-zkcfglines).count | Should Be 5
        (gen-zkcfglines | Where-Object {$_ -match "tickTime=1999"} | measure).Count | Should Be 1
    }
}
