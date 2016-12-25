#!/bin/sh
# install-java.tcl \
exec tclsh "$0" ${1+"$@"}

# insert-common-script-here:tcl/tclcommon-nolib.tcl

CommonNoLib::initialize [lindex $argv 1]

set rpmFile [CommonNoLib::getUpload]

if {[string length $rpmFile] == 0} {
  puts "cannot found rmp file in filesToUpload."
} else {
  if {! [file exists $rpmFile]} {
    puts "file $rpmFile not exists."
  } else {
    if {[CommonNoLib::isInstalled powershell]} {
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
