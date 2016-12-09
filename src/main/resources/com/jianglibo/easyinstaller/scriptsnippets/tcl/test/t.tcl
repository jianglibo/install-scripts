package require tcltest 2.2
package require json
package require yaml
eval ::tcltest::configure $::argv

set ::baseDir [file join [file dirname [info script]] ..]

set ::fixJson [file normalize [file join $::baseDir fixtures envforcodeexec.json]]

lappend auto_path $::baseDir

namespace eval ::example::test {
    namespace import ::tcltest::*
    testConstraint X [expr {1}]

    test topProperty {} -constraints {X unix} -setup {
      } -body {
        source [file normalize [file join $::baseDir shared.tcl]]
        EnvDictNs::initialize $::fixJson
        return [dict get $EnvDictNs::envdict remoteFolder]
      } -cleanup {
      } -result {/opt/easyinstaller}

      test splitLine {} -constraints {} -setup {
        } -body {
          source [file normalize [file join $::baseDir shared.tcl]]
          return [EnvDictNs::splitLine "abc\nbb"]
        } -cleanup {
        } -result {abc bb}


      test boxGroupProperty {} -constraints {X unix} -setup {
        } -body {
          source [file normalize [file join $::baseDir shared.tcl]]
          EnvDictNs::initialize $::fixJson
          return [dict get $EnvDictNs::boxGroupConfigContent zkconfig tickTime]
        } -cleanup {
        } -result {1999}

      test softwareProperty {} -constraints {X unix} -setup {
        } -body {
            source [file normalize [file join $::baseDir shared.tcl]]
            EnvDictNs::initialize $::fixJson
            return [dict get $EnvDictNs::softwareConfigContent zkconfig tickTime]
        } -cleanup {
        } -result {1999}

        test filesToUpload {} -constraints {X unix} -setup {
          } -body {
              source [file normalize [file join $::baseDir shared.tcl]]
              EnvDictNs::initialize $::fixJson
              return [EnvDictNs::getUpload]
          } -cleanup {
          } -result {/opt/easyinstaller/zookeeper-3.4.9.tar.gz}

        test filesToUploadExists {} -constraints {X unix} -setup {
          } -body {
              source [file normalize [file join $::baseDir shared.tcl]]
              EnvDictNs::initialize $::fixJson
              return [EnvDictNs::getUpload *zookeeper*]
          } -cleanup {
          } -result {/opt/easyinstaller/zookeeper-3.4.9.tar.gz}

        test filesToUploadNotExists {} -constraints {X unix} -setup {
          } -body {
              source [file normalize [file join $::baseDir shared.tcl]]
              EnvDictNs::initialize $::fixJson
              return [EnvDictNs::getUpload *notexists*]
          } -cleanup {
          } -result {}

      test filesToUploads {} -constraints {X unix} -setup {
        } -body {
            source [file normalize [file join $::baseDir shared.tcl]]
            EnvDictNs::initialize $::fixJson
            return [EnvDictNs::getUploads]
        } -cleanup {
        } -result {/opt/easyinstaller/zookeeper-3.4.9.tar.gz}


    # match regexp, glob, exact
    cleanupTests
}

namespace delete ::example::test
