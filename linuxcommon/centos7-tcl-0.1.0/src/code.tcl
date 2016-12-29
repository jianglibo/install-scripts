package require base64

set envfile [lindex $argv 1]
set action [lindex $argv 3]
set extraParam [lindex $argv 4]

set extraParam [::base64::decode $extraParam]

# insert-common-script-here:tcl/tclcommon.tcl

proc setupResolver {resolvContent} {
  if {[string length $resolvContent] == 0} {
    puts "resov.conf content not exists in paramter string."
    exit 1
  }
  set lines [EnvDictNs::splitLine $resolvContent]
  set lines [EnvDictNs::trimLeftLines $lines]
  set resolverFile /etc/resolv.conf
  EnvDictNs::backupOrigin $resolverFile
  if {[catch {open $resolverFile w} fid o]} {
    puts $fid
  } else {
    foreach line $lines {
      puts $fid $line
    }
    close $fid
  }
}

proc deleteFolder {folderName} {
  if {[llength $folderName] > 1} {
    puts "only allow one path."
    exit 1
  }
  if {![string equal [file pathtype $folderName] "absolute"]} {
    puts "need a absolute path."
    exit 1
  }
  if {[llength [file split $folderName]] < 4} {
    puts "delete failed."
    exit 1
  } else {
    file delete -force $folderName
  }
}

proc anyCmd {oneCmd} {
  exec $oneCmd
}

proc enableNtpd {} {
  exec yum install -y ntp
  exec systemctl enable ntpd 2>@1
  exec systemctl enable ntpdate 2>@1
  exec systemctl start ntpd 2>@1
}

proc killProcess {extraParam} {
    set pnames [regexp -inline -all -- {[^\s]+} $extraParam]
    set results [open "|ps aux" r]
    set rpre {^[^\s]+\s+([^\s]+).*}
    while { [gets $results line] >= 0 } {
      foreach tokill $pnames {
        if {[regexp "${rpre}${tokill}" $line whole mypid]} {
          exec kill -9 $mypid
        }
      }
    }
    if {[catch {close $results} err]} {
        puts "ps failed: $err"
        exit 1
    }
}

switch -exact -- $action {
  change-resolv {setupResolver $extraParam}
  delete-folder {deleteFolder $extraParam}
  enable-ntpd {enableNtpd}
  any-cmd {anyCmd $extraParam}
  kill-process {killProcess $extraParam}
  t {}
  default {}
}

puts "@@success@@"
