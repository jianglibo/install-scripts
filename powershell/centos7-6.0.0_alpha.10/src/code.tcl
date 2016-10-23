#!/bin/sh
# install-java.tcl \
exec tclsh "$0" ${1+"$@"}

package require yaml

# insert-common-script-here:classpath:scripts/tcl/shared.tcl

EnvDictNs::initialize [lindex $argv 1]

set rpmFile [EnvDictNs::getUpload *rpm*]

if { [string length $rpmFile] == 0} {
  puts "cannot found rmp file in filesToUpload."
} else {
  if {! [file exists $rpmFile]} {
    puts "file $rpmFile not exists."
  } else {
    if {[EnvDictNs::isInstalled powershell]} {
        puts "powershell already installed.@@success@@"
    } else {
      if { [catch {exec yum install -y $rpmFile} msg o] } {
          if {[string match -nocase "*Nothing to do*" $msg]} {
              puts "already installed @@success@@"
          } else {
              puts $msg
          }
      } else {
        puts "@@success@@"
      }
    }
  }
}
