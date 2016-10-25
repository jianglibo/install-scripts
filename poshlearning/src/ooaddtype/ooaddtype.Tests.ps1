$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "ooaddtype" {
    It "does new ob" {
        $nob = New-Ooaddtype
        $nob.MyProperty = 66;
        $nob.MyProperty | Should Be 66
    }
}
