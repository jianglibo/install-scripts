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
    

        if ($LASTEXITCODE -gt 0) {
            yum reinstall -y dbus-python pygobject3-base python-decorator python-slip-dbus python-decorator python-pyudev | Out-Null
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
    $r = systemctl status $serviceName | Select-Object -First 6 | Where-Object {$_ -match "\s+Loaded:.*\(running\)"} | Select-Object -First 1 | measure
    $r.Count -eq 1
}

function Centos7-IsServiceExists {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    $r = systemctl status $serviceName| Select-Object -First 6 | Where-Object {$_ -match "\s+Active:\s*not-found"} | Select-Object -First 1 | measure
    $r.Count -eq 1
}

function Centos7-IsServiceEnabled {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    (systemctl is-enabled $serviceName | Out-String) -match "enabled"
}

function Centos7-FileWall {
    Param($ports, [String]$prot="tcp", [switch]$delete=$False)
    process {
        if ($ports -match ',') {
            $ports = $ports -split ','
        }
        $firewalld = "firewalld"
        if (! (Centos7-IsServiceEnabled -serviceName $firewalld)) {
            systemctl enable $firewalld *>&1 | Write-Output -OutVariable fromBash | Out-Null
        }

        if (! (Centos7-IsServiceRunning -serviceName $firewalld)) {
            systemctl start $firewalld *>&1 | Write-Output -OutVariable fromBash | Out-Null
        }
        if ($delete) {
            $action = "--remove-port"
        } else {
            $action = "--add-port"
        }
        try {
            foreach ($one in $ports) {
                firewall-cmd --permanent --zone=public $action "$one/$prot" | Out-Null
            }
        }
        catch {
            if ($fromBash -match "Nothing to do") {
                $Error.Clear()
            } else {
                $fromBash
            }
        }
    }
    end {
        firewall-cmd --reload | Out-Null
    }
}

function Centos7-GetOpenPorts {
    (firewall-cmd --list-all | Where-Object {$_ -match "^\s*ports:"} | Select-Object -First 1) -split "\s+" | ? {$_.length -gt 0} | Select-Object -Skip 1
}

function Centos7-UserManager {
    Param([parameter(Mandatory=$True)][String]$username,[string]$group,[switch]$createHome, [ValidateSet("add", "remove", "exists")][parameter(Mandatory=$True)][string]$action)
    $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | measure
    if ($group) {
        $g = Get-Content /etc/group | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | measure
        if ($g.Count -eq 0) {
            groupadd $group
        } 
    }
    switch ($action) {
        "add" {
            if ($r.Count -eq 0) {
                if ($createHome) {
                    if ($group) {
                        useradd -m -g $group $username
                    } else {
                        useradd -m $username
                    }
                } else {
                    if ($group) {
                        useradd -M -s /sbin/nologin -g $group $username
                    } else {
                        useradd -M -s /sbin/nologin $username
                    }
                }
            } else {
                if ($group) {
                    usermod -g $group $username
                }
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

function Centos7-Run-User-String {
    Param([string]$shell="/bin/bash", [string]$scriptcmd, [string]$user,[string]$group)
    $user = $user | Trim-All
    if (! $user) {
        $user = $env:USER
    }
    if (!$group) {
        $group = $user
    }
    Centos7-UserManager -username $user -action add -group $group
    'runuser -s /bin/bash -c "{0}"  {1}' -f $scriptcmd,$user
}

function Centos7-Nohup {
    Param([string]$shell="/bin/bash", [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$scriptcmd, [string]$user,[string]$group,[int]$NICENESS, [string]$logfile,[string]$pidfile)
    $newcmd = "nohup nice -n $NICENESS $ru > `"$logfile`" 2>&1 < /dev/null &"
    $newcmd = Centos7-Run-User-String -shell $shell -scriptcmd $newcmd -user $user -group $group
    $line2 = 'echo $! > $pidfile'
    $line3 = 'sleep 1'
    $tmp = New-TemporaryFile
    $newcmd,$line2,$line3 | Out-File $tmp -Encoding ascii
    bash "$tmp"
    Remove-Item $tmp -Force
}

function Centos7-Run-User {
    Param([string]$shell="/bin/bash", [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$scriptcmd, [string]$user,[string]$group,[switch]$background)
    $user = $user | Trim-All
    if (! $user) {
        $user = $env:USER
    }
    if (!$group) {
        $group = $user
    }
    Centos7-UserManager -username $user -group $group -action add
#    chown $user $scriptfile | Out-Null
#    chmod u+x $scriptfile | Out-Null
    if ($background) {
        'runuser -s /bin/bash -c "{0}"  {1}' -f $scriptcmd,$user | Invoke-Expression
    } else {
        'runuser -s /bin/bash -c "{0}"  {1}' -f $scriptcmd,$user | Invoke-Expression
    }
    
}

function Centos7-Chown {
    Param([string]$user, [string]$group=$null, [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$Path)
    process {
        if (!$group) {
            $group = $user
        }
        Centos7-UserManager -action add -group $group -username $user
        if ($Path -is [System.IO.FileInfo]) {
            $Path = $Path.FullName
        }
        chown -R "${user}:${group}" $Path | Out-Null
    }
}

function Centos7-PersistExport {
    Param([parameter(Mandatory=$True)][string]$key, [parameter(Mandatory=$True)][string]$value)
    $f = "/etc/profile.d/easyinstaller.sh" 
    if ( $f | Test-Path) {
        $lines = Get-Content $f
    }
    "$key=$value","export $key" + $lines | Out-File $f -Encoding ascii
}