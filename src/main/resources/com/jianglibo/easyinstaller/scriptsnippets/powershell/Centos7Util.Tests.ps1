$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Centos7Util" {
    It "should disable networkmanager" {
        $osutil = New-Centos7Util
        $osutil.disableNetworkManager() | Should Be 1
    }
    It "should set hostname" {
        $osutil = New-Centos7Util
        $osutil.setHostName() | Should Be 1
    }
    It "should open firewall" {
        $osutil = New-Centos7Util
        $fwd = "firewalld"
        systemctl stop $fwd
        systemctl disable $fwd
        $out =  $osutil.openFireWall("8080")
        $out.getType() | Should Be "System.Object[]"
        $out.Count | Should be 2

        $out -join "," | Should Be "success,success"
        
    }
    It "should handle user manager" {
        $osutil = New-Centos7Util

        $un = "a" + (Get-Random)
        $osutil.userm($un) | Should Be 1

        Select-String -Path /etc/passwd -Pattern "^${un}:" | Should Be $True

        $osutil.userm($un, $True) | Should Be 1
    }
}

# remember

# useradd -r , create a user has no login.