$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Centos7Util" {
    It "should disable networkmanager" {
        $networkmanager = "NetworkManager"

        if (Centos7-IsServiceEnabled -serviceName $networkmanager) {
            Centos7-NetworkManager -action disable
        }

        Centos7-IsServiceEnabled -serviceName $networkmanager | Should Be $False
        Centos7-IsServiceRunning -serviceName $networkmanager | Should Be $False

        Centos7-NetworkManager -action enable
        Centos7-IsServiceEnabled -serviceName $networkmanager | Should Be $True
        Centos7-IsServiceRunning -serviceName $networkmanager | Should Be $True
    }
    It "should set hostname" {
        $hn = hostname
        Centos7-SetHostName -hostname "a.b.c"
        hostname | Should Be "a.b.c"
        Centos7-SetHostName $hn
    }
    It "should open firewall" {
        $fwd = "firewalld"
        if (Centos7-IsServiceEnabled -serviceName $fwd) {
            systemctl stop $fwd *>1 | Out-Null
            systemctl disable $fwd *>1 | Out-Null
        }

        Centos7-FileWall -ports "8081"
        $r = firewall-cmd --list-all | Where-Object {$_ -match "^\s+ports"} | Select-Object -First 1
        
        $r -match "8081/tcp" | Should Be $True
        Centos7-FileWall -ports "8081" -delete

        Centos7-FileWall -ports "8081,8082"
        $r = firewall-cmd --list-all | Where-Object {$_ -match "^\s+ports"} | Select-Object -First 1
        
        $r -match "8081/tcp" | Should Be $True
        $r -match "8082/tcp" | Should Be $True

        Centos7-FileWall -ports "8081,8082" -delete

    }
    It "should handle user manager" {
        $username = "a" + (Get-Random)
    
        Centos7-UserManager -username $username -action add

        Centos7-UserManager -username $username -action exists | Should Be $True
        
        $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | measure

        $r.Count | Should Be 1
        
        Centos7-UserManager -username $username -action remove

        $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | measure
        $r.Count | Should Be 0

        Centos7-UserManager -username "xxxxxxxxxxu" -action exists | Should Be $False
    }
}

# remember
# useradd -r , create a user has no login.