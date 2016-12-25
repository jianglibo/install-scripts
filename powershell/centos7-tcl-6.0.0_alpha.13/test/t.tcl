package require tcltest 2.2
eval ::tcltest::configure $::argv

set ::baseDir [file join [file dirname [info script]] ..]
lappend auto_path $::baseDir

source [file normalize [file join $::baseDir .. .. src main resources com jianglibo easyinstaller scriptsnippets tcl tclcommon.tcl]]

set ::rpmName [file join $::baseDir fixtures powershell-6.0.0_alpha.10-1.el7.centos.x86_64.rpm]

::tcltest::customMatch mm mmproc

proc mmproc {expectedResult actualResult} {
  set lines [dict get $actualResult lines]
  regexp {dataDir=([^ ]+)} $lines whole dataDir
  set myidFile [file join $dataDir myid]
  set configFile [dict get $actualResult configFile]

  if {! [file exists $dataDir]} {
    puts "${dataDir} does not exists."
    return 0
  }

  if {! [file exists $myidFile]} {
    puts "${myidFile} does not exists."
    return 0
  }

  if {! [file exists $configFile]} {
    puts "${configFile} does not exists."
    return 0
  }
  return 1
}

namespace eval ::example::test {
    namespace import ::tcltest::*

    testConstraint X [file exists $::rpmName]

    test parsefile {} -constraints {X unix} -setup {
      set fx [file join $::baseDir fixtures envforcodeexec.json]
      set argv [list -envfile $fx -action t]
      EnvDictNs::initialize $fx
      set rpmFile [EnvDictNs::getUpload *rpm*]

      if {! [file exists $rpmFile]} {
        file mkdir $EnvDictNs::remoteFolder
        exec cp $::rpmName $EnvDictNs::remoteFolder
      }
      } -body {
        if { [catch {source [file join $::baseDir src code.tcl]}] } {
          return 0
        }
      return [EnvDictNs::isInstalled powershell]
    } -cleanup {

    } -result {1}

    # match regexp, glob, exact
    cleanupTests
}

namespace delete ::example::test
