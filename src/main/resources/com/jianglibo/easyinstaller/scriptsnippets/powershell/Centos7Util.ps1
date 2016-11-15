<#
stop NetworkManager, disable NetworkManager service,
1. get all interface names.
2. ip addr [ add | del ] address dev ifname, ip address add 10.0.0.3/24 dev eth0, allow assign multiple address to same interface.
3. Static Routes and the Default Gateway, ip route add 192.0.2.1 via 10.0.0.1 [dev ifname]
4. cat /etc/sysconfig/network-scripts/ifcfg-enp0s3 er interface Configuration. add GATEWAY="xx.xx.xxx.xx" directive.
#>

function Centos7-NetworkManager {
    Param([ValidateSet("enable", "disable")][parameter(Mandatory=$True)][string]$action)
    $nm = "NetworkManager"
    switch ($action) {
        "enable" {
            systemctl enable $nm *>1 | Out-Null
            systemctl start $nm *>1 | Out-Null
        }
        "disable" {
            systemctl stop $nm *>1 | Out-Null
            systemctl disable $nm *>1 | Out-Null
        }
    }
}

function Centos7-GetRunuserCmd {
    Param($myenv, $action)
    $result = Get-Content $myenv.resultFile | ConvertFrom-Json

    Add-AsHtScriptMethod -pscustomob $result

    [HashTable]$envs = $result.asHt("env")

    $envs.GetEnumerator() | ForEach-Object {
        Set-Content -Path ("env:" + $_.Key) -Value $_.Value
    }

    $user = Centos7-GetScriptRunner -myenv $myenv

    'runuser -s /bin/bash -c "{0}" {1}' -f ($result.executable, $action -join " ").Trim(),$user
}

function Centos7-GetScriptRunner {
    Param($myenv)
    [string]$user = $myenv.software.runas
    $user = $user.Trim()
    if ($user) {
        $user
    } else {
        $env:USER
    }
}

function Centos7-SetHostName {
    Param([String]$hostname)
    hostnamectl --static set-hostname $hostname
}

function Centos7-InstallNtp {
    yum install -y ntp ntpdate
    systemctl enable ntpd
    ntpdate pool.ntp.org
    systemctl start ntpd
}

function Centos7-IsServiceRunning {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    $r = systemctl status $serviceName | Select-Object -First 4 | Where-Object {$_ -match "\s+Active:.*\(running\)"} | Select-Object -First 1 | measure
    $r.Count -eq 1
}

function Centos7-IsServiceEnabled {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    (systemctl is-enabled $serviceName | Out-String) -match "enabled"
}

function Centos7-FileWall {
    Param($ports, [String]$prot="tcp", [switch]$delete=$False)
    if ($ports -is [Array]) {
        $ports = $ports -join ","
    }
    $firewalld = "firewalld"
    if (! (Centos7-IsServiceEnabled -serviceName $firewalld)) {
        systemctl enable $firewalld *>1 | Out-Null
    }

    if (! (Centos7-IsServiceRunning -serviceName $firewalld)) {
        systemctl start $firewalld *>1 | Out-Null
    }
    if ($delete) {
        $action = "--remove-port"
    } else {
        $action = "--add-port"
    }

    firewall-cmd --permanent --zone=public $action "$ports/$prot" | Out-Null
    firewall-cmd --reload | Out-Null
}

function Centos7-UserManager {
    Param([parameter(Mandatory=$True)][String]$username, [ValidateSet("add", "remove", "exists")][parameter(Mandatory=$True)][string]$action)
    $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | measure

    switch ($action) {
        "add" {
            if ($r.Count -eq 0) {
                useradd -r -M -s /sbin/nologin $username
            }
        }

        "remove" {
            if ($r.Count -eq 1) {
                userdel -f $username
            }
        }

        "exists" {
            $r.Count -eq 1
        }
    }
}

# runuser -s /bin/bash -c "/opt/tmp8TEpPH.sh 1 2 3" abc
# su -s /bin/bash -c "/opt/tmp8TEpPH.sh 1 2 3" abc

function Centos7-Run-User {
    Param([string]$shell="/bin/bash", [string]$scriptcmd, [string]$user)
    $user = $user | Trim-All
    if (! $user) {
        $user = $env:USER
    }
    Centos7-UserManager -username $user -action add
#    chown $user $scriptfile | Out-Null
#    chmod u+x $scriptfile | Out-Null
    'runuser -s /bin/bash -c "{0}"  {1}' -f $scriptcmd,$user | Invoke-Expression
}

function Centos7-Chown {
    Param([string]$user, [string]$group=$null, [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$Path)
    process {
        if (!$group) {
            $group = $user
        }
        Centos7-UserManager -action add -username $user
        if ($Path -is [System.IO.FileInfo]) {
            $Path = $Path.FullName
        }
        chown -R "${user_hdfs}:${user_hdfs}" $Path | Out-Null
    }
}