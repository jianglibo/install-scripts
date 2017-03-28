<#
stop NetworkManager, disable NetworkManager service,
1. get all interface names.
2. ip addr [ add | del ] address dev ifname, ip address add 10.0.0.3/24 dev eth0, allow assign multiple address to same interface.
3. Static Routes and the Default Gateway, ip route add 192.0.2.1 via 10.0.0.1 [dev ifname]
4. cat /etc/sysconfig/network-scripts/ifcfg-enp0s3 er interface Configuration. add GATEWAY="xx.xx.xxx.xx" directive.
#>

function Update-NetworkManagerState {
    Param([ValidateSet("enable", "disable")][parameter(Mandatory=$True)][string]$action,
        [ValidateSet("centos7", "unbuntu")][string]$ostype="centos7")
    $nm = "NetworkManager"
    
    switch ($action) {
        "enable" {
            try {systemctl enable $nm *>&1 | Out-Null} catch {}
            try {systemctl start $nm *>&1 | Out-Null} catch {}
        }
        "disable" {
            try {systemctl stop $nm *>&1 | Out-Null} catch {}
            try {systemctl disable $nm *>&1 | Out-Null} catch {}
        }
    }

    if ($LASTEXITCODE -gt 0) {
        yum reinstall -y dbus-python pygobject3-base python-decorator python-slip-dbus python-decorator python-pyudev | Out-Null
    }
}

function Install-Alternatives {
   Param(
       [Parameter(Mandatory=$true)]
       [string]$link,
       [Parameter(Mandatory=$true)]
       [string]$name,
       [Parameter(Mandatory=$true)]
       [string]$path,
       [Parameter(Mandatory=$true)]
       [long]$priority
    )

    $aname = alternatives --display $name | Where-Object {$_ -match ".*priority\s+(\d+).*"} | Select-Object -First 1
    if ($aname) {
        [long]$curPriority = $Matches[1]
        if ($priority -le $curPriority) {
            $priority = $curPriority + 100
        }
    }
    $cmd = "alternatives --install {0} {1} {2} {3}" -f $link,$name,$path,$priority
    $cmd | Write-HostIfInTesting
    $cmd | Invoke-Expression
    alternatives --auto $name
}

function Set-HostName {
    Param([String]$hostname, [string]$ostype="centos7")
    hostnamectl --static set-hostname $hostname
}

function Install-NtpService {
    Param([string]$ostype="centos7")
    yum install -y ntp ntpdate
    systemctl enable ntpd
    ntpdate pool.ntp.org
    systemctl start ntpd
}

function Uninstall-NtpService {
    Param([string]$ostype="centos7")
    if (Test-ServiceRunning -serviceName "ntpd") {
        systemctl stop ntpd
    }
    yum remove -y ntpd ntpdate
}

function Test-ServiceRunning {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    systemctl status $serviceName | Select-Object -First 6 | Where-Object {$_ -match "\s+Loaded:.*\(running\)"} | Select-Object -First 1
}

function Test-ServiceExists {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    systemctl status $serviceName| Select-Object -First 6 | Where-Object {$_ -match "\s+Active:\s*not-found"} | Select-Object -First 1
}

function Test-ServiceEnabled {
    Param([parameter(Mandatory=$True)][String]$serviceName)
    (systemctl is-enabled $serviceName | Out-String) -match "enabled"
}

function Update-FirewallItem {
    Param($ports, [ValidateSet("tcp", "udp")][String]$prot="tcp", [switch]$delete=$False)
    process {
        if ($ports -match ',') {
            $ports = $ports -split ','
        }
        $firewalld = "firewalld"
        if (! (Test-ServiceEnabled -serviceName $firewalld)) {
            try {
                systemctl enable $firewalld *>&1 | Write-Output -OutVariable fromBash | Out-Null
            }
            catch {
                $Error.Clear()
#                if ($fromBash -match "Created symlink from") {
#                    $Error.Clear()
#                }
            }
        }

        if (! (Test-ServiceRunning -serviceName $firewalld)) {
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

function Get-FirewallOpenPorts {
    (firewall-cmd --list-all | Where-Object {$_ -match "^\s*ports:"} | Select-Object -First 1) -split "\s+" | Where-Object {$_.length -gt 0} | Select-Object -Skip 1
}

function Find-LinuxUser {
    Param([parameter(Mandatory=$True)][String]$username)
    Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1
}

function Find-LinuxGroup {
    Param([parameter(Mandatory=$True)][String]$groupname)
    Get-Content /etc/group | Where-Object {$_ -match "^${groupname}:"} | Select-Object -First 1
}

function New-LinuxUser {
    Param([parameter(Mandatory=$True)][String]$username,[string]$groupname,[switch]$createHome)
    if ($groupname) {
        if (-not (Find-LinuxGroup $groupname)) {
            groupadd -f $groupname
        }
    }
    if (Find-LinuxUser $username) {
        if ($groupname) {
            $inGroup = ((groups $username) -split "\s*:\s*") -contains $groupname
            if (!$inGroup) {
                usermod -g $groupname $username
            }
        }
    } else {
        if ($createHome) {
            if ($groupname) {
                useradd -m -g $groupname $username
            } else {
                useradd -m $username
            }
        } else {
            if ($groupname) {
                useradd -M -s /sbin/nologin -g $groupname $username
            } else {
                useradd -M -s /sbin/nologin $username
            }
        }
    }
}

function Remove-LinuxUser {
    Param([parameter(Mandatory=$True)][String]$username)
    if (Find-LinuxUser $username) {
        userdel -f $username
    }
}

# function Centos7-UserManager {
#     Param([parameter(Mandatory=$True)][String]$username,[string]$group,[switch]$createHome, [ValidateSet("add", "remove", "exists")][parameter(Mandatory=$True)][string]$action)
#     $r = Get-Content /etc/passwd | Where-Object {$_ -match "^${username}:"} | Select-Object -First 1 | Measure-Object
#     if ($group) {
#         $g = Get-Content /etc/group | Where-Object {$_ -match "^${group}:"} | Select-Object -First 1 | Measure-Object
#         if ($g.Count -eq 0) {
#             groupadd $group
#         } 
#     }
#     switch ($action) {
#         "add" {
#             if ($r.Count -eq 0) {
#                 if ($createHome) {
#                     if ($group) {
#                         useradd -m -g $group $username
#                     } else {
#                         useradd -m $username
#                     }
#                 } else {
#                     if ($group) {
#                         useradd -M -s /sbin/nologin -g $group $username
#                     } else {
#                         useradd -M -s /sbin/nologin $username
#                     }
#                 }
#             } else {
#                 if ($group) {
#                     usermod -g $group $username
#                 }
#             }
#         }

#         "remove" {
#             if ($r.Count -eq 1) {
#                 userdel -f $username
#             }
#         }

#         "exists" {
#             $r.Count -eq 1
#         }
#     }
# }

# runuser -s /bin/bash -c "/opt/tmp8TEpPH.sh 1 2 3" abc
# su -s /bin/bash -c "/opt/tmp8TEpPH.sh 1 2 3" abc

function Start-RunUser-String {
    Param([string]$shell="/bin/bash", [string]$scriptcmd, [string]$user,[string]$group)
    $user = $user | Trim-All
    if (! $user) {
        $user = $env:USER
    }
    if (!$group) {
        $group = $user
    }
    New-LinuxUser -username $user -groupname $group
    "runuser -s /bin/bash -c '{0}'  {1}" -f $scriptcmd,$user
}

function Start-Nohup {
    Param([string]$shell="/bin/bash", [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$scriptcmd, [string]$user,[string]$group,[int]$NICENESS, [string]$logfile,[string]$pidfile)
    $newcmd = "nohup nice -n $NICENESS $scriptcmd > `"$logfile`" 2>&1 < /dev/null &"
    $newcmd = Start-RunUser-String -shell $shell -scriptcmd $newcmd -user $user -group $group
    $line2 = 'sleep 1'
    $line3 = 'echo $! >' + $pidfile
    $tmp = New-TemporaryFile
    $newcmd,$line2,$line3 | Out-File $tmp -Encoding ascii
    Write-Host "$tmp"
    bash "$tmp"
    $tmp | Write-HostIfInTesting
#    Remove-Item $tmp -Force
}

function Start-RunUser {
    Param([string]$shell="/bin/bash", [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$scriptcmd, [string]$user,[string]$group,[switch]$background)
    $user = $user | Trim-All
    if (-not $user) {
        $user = $env:USER
    }
    if (-not $group) {
        $group = $user
    }
    New-LinuxUser -username $user -groupname $group
#    chown $user $scriptfile | Out-Null
#    chmod u+x $scriptfile | Out-Null
    $torun = 'runuser -s /bin/bash -c "{0}"  {1}' -f $scriptcmd,$user 
    if ($background) {
         $torun | Invoke-Expression
    } else {
        $torun | Invoke-Expression
    }
    
    "Start-RunUser full command: $torun"
}

function Invoke-Chown {
    Param([string]$user, [string]$group=$null, [parameter(ValueFromPipeline=$True, Mandatory=$True)][string]$Path)
    process {
        if (!$group) {
            $group = $user
        }
        New-LinuxUser -username $user -groupname $group
        if ($Path -is [System.IO.FileInfo]) {
            $Path = $Path.FullName
        }
        chown -R "${user}:${group}" $Path | Out-Null
    }
}

function Save-EnvToProfile {
    Param([parameter(Mandatory=$True)][string]$key, [parameter(Mandatory=$True)][string]$value)
    $f = "/etc/profile.d/easyinstaller.sh" 
    if ( $f | Test-Path) {
        $lines = Get-Content $f
    }
    "$key=$value","export $key" + $lines | Out-File $f -Encoding ascii
}