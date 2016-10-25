$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.TestsNix\.', '.'
. "$here\$sut"

Describe "PsCommon" {
    It "should handle OsUtil" {
        $osutil = New-OsUtil -ostype centos
        $osutil.isServiceRunning("crond") | Should Be $True

        $osutil.isEnabled("crond") | Should Be $True
    }
}
