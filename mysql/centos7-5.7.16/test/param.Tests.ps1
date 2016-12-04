$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stu = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$tfps = $here | Join-Path -ChildPath $stu

$tfsh =  $here | Join-Path -ChildPath t.sh

Describe "code" {
    It "should return right result" {
      powershell -File $tfps a b c | Should Be 3
      powershell -File $tfps "a b c" | Should Be 1

      bash $tfsh a b c | Should Be 3
      bash $tfsh "a b c" | Should Be 1
    }
    It "source ps1 file" {
      . $tfps
      Get-CommandPath | Should Be "/vagrant/mysql/centos7-5.7.16/test/param.ps1"
      Get-Psscriptroot | Should Be "/vagrant/mysql/centos7-5.7.16/test"
    }
}

# Unlike the $PSCommandPath and $PSScriptRoot automatic variables, which contain information about the current script, the PSCommandPath and PSScriptRoot properties of the $MyInvocation variable contain information about the script that called or invoke the current script.
