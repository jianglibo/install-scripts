$here = $PSScriptRoot
$sut = (Split-Path -Leaf $PSCommandPath) -replace '\.Tests\.', '.'

$fixture = $here | Join-Path -ChildPath "fixtures" | Join-Path -ChildPath "hostsmodifier"

$resutl = . "$here\$sut" -hostfile $fixture -items "1.1.1.1 a.a.a, 2.2.2.2 b.b.b" -writeback $false

Describe "code" {
    It "should handle add item" {
        $resutl | Where-Object {$_ -match "1.1.1.1"} | Should be "1.1.1.1 a.a.a"
        $resutl | Where-Object {$_ -match "2.2.2.2"} | Should be "2.2.2.2 b.b.b"
    }
    It "should delete item by ip" {
        $resutl = . "$here\$sut" -hostfile $fixture -items "10.74.111.62" -writeback $false -delete
        $resutl | Where-Object {$_ -match "10.74.111.62"} | Should be $null
    }
    It "should delete item by hostname" {
        $resutl = . "$here\$sut" -hostfile $fixture -items "s62.host.name" -writeback $false -delete
        $resutl | Where-Object {$_ -match "s62.host.name"} | Should be $null
    }
}