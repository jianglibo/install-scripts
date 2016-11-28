#!/bin/sh
# install-java.tcl \
exec tclsh "$0" ${1+"$@"}

package require yaml

# insert-common-script-here:tcl/shared.tcl

# tcl json util cannot handle complex struct.
set envfile [lindex $argv 1]
if {[catch {EnvDictNs::initialize $envfile} msg]} {
  puts $msg
  set data [EnvDictNs::readWholeFile $envfile]
  if {[regexp {"filesToUpload":\s*\[\s*"([^"]+)"} $data discard urlname]} {
    if {[regexp {.*/([^/]+)$} $urlname discard rpmFile]} {
      puts "found file $rpmFile"
    } else {
      set rpmFile $urlname
    }
  } else {
    puts "no file found"
    exit 1
  }
} else {
  set rpmFile [EnvDictNs::getUpload *rpm*]
}

if {[string first "/easy-installer" $rpmFile] == -1} {
  set rpmFile "/easy-installer/$rpmFile"
}

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
