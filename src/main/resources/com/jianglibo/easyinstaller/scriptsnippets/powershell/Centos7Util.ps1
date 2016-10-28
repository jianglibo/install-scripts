<#
stop NetworkManager, disable NetworkManager service,
1. get all interface names.
2. ip addr [ add | del ] address dev ifname, ip address add 10.0.0.3/24 dev eth0, allow assign multiple address to same interface.
3. Static Routes and the Default Gateway, ip route add 192.0.2.1 via 10.0.0.1 [dev ifname]
4. cat /etc/sysconfig/network-scripts/ifcfg-enp0s3 er interface Configuration. add GATEWAY="xx.xx.xxx.xx" directive.
#>

function New-Centos7Util {
    $osutil = New-Object -TypeName PSObject
    
    $osutil | Add-Member -MemberType ScriptMethod -Name disableNetworkManager -Value {
        systemctl stop NetworkManager
        systemctl disable NetworkManager
        1
    }

    $osutil | Add-Member -MemberType ScriptMethod -Name setHostName -Value {
        Param([String]$hn)
        hostnamectl --static set-hostname $hn
        1
    }

    $osutil | Add-Member -MemberType ScriptMethod -Name isServiceRunning -Value {
        Param([parameter(Mandatory=$True)][String]$serviceName)
        [Boolean](systemctl status $serviceName | Select-Object -First 4 | Where-Object {$_ -match "\s+Active:.*\(running\)"})
    }

    $osutil | Add-Member -MemberType ScriptMethod -Name isServiceEnabled -Value {
        Param([parameter(Mandatory=$True)][String]$serviceName)
        [Boolean](systemctl is-enabled $serviceName | Where-Object {$_ -match "enabled"})
    }

    $osutil | Add-Member -MemberType ScriptMethod -Name installNtp -Value {
        yum install -y ntp ntpdate
        systemctl enable ntpd
        ntpdate pool.ntp.org
        systemctl start ntpd
        1
    }
    # prerequirements, yum install python-pip, pip install decorator
    # every command's out put will send to result receiver.
    $osutil | Add-Member -MemberType ScriptMethod -Name openFireWall -Value {
        Param($ports, [String]$prot="tcp")
        if ($ports -is [Array]) {
            $ports = $ports -join ","
        }
        $firewalld = "firewalld"
        $out = @()
        if (! $this.isServiceEnabled($firewalld)) {
            $out += (systemctl enable $firewalld)
        }

        if (! $this.isServiceRunning($firewalld)) {
            $out += (systemctl start $firewalld)
        }

       $out += (firewall-cmd --permanent --zone=public --add-port "$ports/$prot")
       $out += (firewall-cmd --reload)
       $out
    }

    $osutil | Add-Member -MemberType ScriptMethod -Name userm -Value {
        Param([String]$un, [switch]$delete)
        if ($delete) {
            if ((Select-String -Path /etc/passwd -Pattern ("^{0}:.*" -f $un)).Matches.Value) {
                userdel -f $un
            }
        } else {
            if (! (Select-String -Path /etc/passwd -Pattern ("^{0}:.*" -f $un)).Matches.Value) {
                useradd -r -M -s /sbin/nologin $un
            }
        }
        1
    }

    $osutil
}
