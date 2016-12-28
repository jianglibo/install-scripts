$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Centos7Util" {
    It "should disable networkmanager" {
        $networkmanager = "NetworkManager"

        if (Test-ServiceEnabled -serviceName $networkmanager) {
            Update-NetworkManagerState -action disable
        }

        Test-ServiceEnabled -serviceName $networkmanager | Should Be $False
        Test-ServiceRunning -serviceName $networkmanager | Should Be $False

        Update-NetworkManagerState -action enable
        Test-ServiceEnabled -serviceName $networkmanager | Should Be $True
#        Test-ServiceRunning -serviceName $networkmanager | Should Be $True

        Test-ServiceExists -serviceName "heloabc" | Should Be $False
    }
    It "should set hostname" {
        $hn = hostname
        Set-HostName -hostname "a.b.c"
        hostname | Should Be "a.b.c"
        Set-HostName $hn
    }
    It "should open firewall" {
        $fwd = "firewalld"
        if (Test-ServiceEnabled -serviceName $fwd) {
            systemctl stop $fwd *>1 | Out-Null
            systemctl disable $fwd *>1 | Out-Null
        }

        Update-FirewallItem -ports "8081"
        $r = firewall-cmd --list-all | Where-Object {$_ -match "^\s+ports"} | Select-Object -First 1
        
        $r -match "8081/tcp" | Should Be $True
        Update-FirewallItem -ports "8081" -delete

        Update-FirewallItem -ports "8081,8082"
        $r = firewall-cmd --list-all | Where-Object {$_ -match "^\s+ports"} | Select-Object -First 1
        
        $r -match "8081/tcp" | Should Be $True
        $r -match "8082/tcp" | Should Be $True

        Update-FirewallItem -ports "8081,8082" -delete

    }
    It "should handle user manager" {
        $username = "a" + (Get-Random)
    
        New-LinuxUser -username $username

        Find-LinuxUser -username $username | Should Be $True
        
        $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | Measure-Object

        $r.Count | Should Be 1

        Remove-LinuxUser -username $username

        $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | Measure-Object
        $r.Count | Should Be 0
        Find-LinuxUser -username "xxxxxxxxxxu" | Should Be $False
    }

    It "should persist export" {
        $f = "/etc/profile.d/easyinstaller.sh"
        if ($f | Test-Path) {
            Remove-Item $f
        }
        $f | Test-Path | Should Be $False
        Save-EnvToProfile -key "JAVA_HOME" -value "/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.111-1.b15.el7_2.x86_64/jre"
        $f | Test-Path | Should Be $True
        
        Get-Content $f | Where-Object {$_ -match "^JAVA_HOME"} | Select-Object -First 1 | Should Be "JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-1.8.0.111-1.b15.el7_2.x86_64/jre"
        Get-Content $f | Where-Object {$_ -match "^export JAVA_HOME"} | Select-Object -First 1 | Should Be "export JAVA_HOME"
        # Remove-Item $f
    }
}

# remember
# useradd -r , create a user has no login.