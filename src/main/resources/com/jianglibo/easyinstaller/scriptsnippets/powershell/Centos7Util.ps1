<#
stop NetworkManager, disable NetworkManager service,
1. get all interface names.
2. ip addr [ add | del ] address dev ifname, ip address add 10.0.0.3/24 dev eth0, allow assign multiple address to same interface.
3. Static Routes and the Default Gateway, ip route add 192.0.2.1 via 10.0.0.1 [dev ifname]
4. cat /etc/sysconfig/network-scripts/ifcfg-enp0s3 er interface Configuration. add GATEWAY="xx.xx.xxx.xx" directive.
#>

function New-Centos7Util {
    $osutil = New-Object -TypeName PSObject
    
    $osutil = $osutil | Add-Member -MemberType ScriptMethod -Name disableNetworkManager -Value {
        systemctl stop NetworkManager
        systemctl disable NetworkManager
    } -PassThru

    $osutil = $osutil | Add-Member -MemberType ScriptMethod -Name setHostName -Value {
        Param([String]$hn)
        hostnamectl --static set-hostname $hn
    } -PassThru

    $osutil = $osutil | Add-Member -MemberType ScriptMethod -Name installNtp -Value {
        yum install -y ntp ntpdate
        systemctl enable ntpd
        ntpdate pool.ntp.org
        systemctl start ntpd
    } -PassThru

    $osutil = $osutil | Add-Member -MemberType ScriptMethod -Name openFireWall -Value {
        Param($prot, $ports)
        if ($ports -is [Array]) {
            $ports = $ports -join ","
        }
        firewall-cmd --permanent --zone=public --add-port "$ports/$prot"
        firewall-cmd --reload
    } -PassThru
    return $osutil
}
