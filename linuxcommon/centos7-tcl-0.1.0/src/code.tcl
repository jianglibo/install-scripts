package require base64

set envfile [lindex $argv 1]
set action [lindex $argv 3]
set extraParam [lindex $argv 4]

set extraParam [::base64::decode $extraParam]

# insert-common-script-here:tcl/shared.tcl

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

porc anyCmd {oneCmd} {
  exec $oneCmd
}

switch -exact -- $action {
  change-resolv {setupResolver $extraParam}
  delete-folder {deleteFolder $extraParam}
  any-cmd {anyCmd $extraParam}
  t {}
  default {}
}

puts "@@success@@"
