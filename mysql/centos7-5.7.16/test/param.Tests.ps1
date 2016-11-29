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
}
