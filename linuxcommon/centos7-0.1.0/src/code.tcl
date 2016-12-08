package require base64

set envfile [lindex $argv 1]
set action [lindex $argv 3]
set extraParam [lindex $argv 4]

set extraParam [::base64::decode $extraParam]

# insert-common-script-here:tcl/shared.tcl

proc setupResolver {resolvContent} {
  set resolverFile /etc/resolv.conf
  EnvDictNs::backupOrigin $resolverFile
  if {[catch {open $resolverFile w} fid o]} {
    puts $fid
  } else {
    puts $fid $resolvContent
    close $fid
  }
}

switch -exact -- $action {
  change-resolv {setupResolver $extraParam}
  t {}
  default {}
}

puts "@@success@@"
