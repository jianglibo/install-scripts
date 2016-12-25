
namespace eval CommonNoLib {

  # cannot process comments.
  proc todict {lines} {
    set mydd [dict create]
    set currentKey {}
    set blockLines {}
    set skipThisLine 0
    foreach line $lines {
        # top level container.
        if {[regexp {^([^: ]+):\s*$} $line whole key]} {
          if {[string length $currentKey] > 0} {
            dict set mydd $currentKey $blockLines
            set blockLines {}
            set currentKey {}
          }
          set skipThisLine 1
          set currentKey $key
        }
        # top level string value.
        if {[regexp {^([^: ]+):\s+"(.*)"$} $line whole key value]} {
          if {[string length $currentKey] > 0} {
            dict set mydd $currentKey $blockLines
            set blockLines {}
            set currentKey {}
          }
          set value [regsub {\\"} $value {"}]
          dict set mydd $key $value
          set skipThisLine 1
        }
        # top level number value.
        if {[regexp {^([^: ]+):\s+([0-9.])+$} $line whole key value]} {
          if {[string length $currentKey] > 0} {
            dict set mydd $currentKey $blockLines
            set blockLines {}
            set currentKey {}
          }
          dict set mydd $key $value
          set skipThisLine 1
        }
        if {[string length $currentKey] > 0 && !$skipThisLine} {
          set skip 0
          if {[regexp {^\s*#} $line]} {
            set skip 1
          }
          if {!$skip} {
            lappend blockLines $line
          }
        }
        set skipThisLine 0
    }
    if {[string length $currentKey] > 0 && [llength $blockLines] > 0} {
      dict set mydd $currentKey $blockLines
    }
    return $mydd
  }

  proc upgradeLevel {lines} {
    set newLines {}
    if {[llength $lines] > 0} {
      regexp {^\s*} [lindex $lines 0] spaces
      set spacesLength [string length $spaces]
      foreach line $lines {
        lappend newLines [regsub "^\\s{$spacesLength}" $line {}]
      }
    }
    return $newLines
  }

  proc initialize {envfile} {
    variable envLines
    variable topDict
    set envLines [readLines $envfile]
    set topDict [todict $envLines]
  }

  proc untar {dstFolder {tgzFile ""}} {
    if {! [file exists $dstFolder]} {
      file mkdir $dstFolder
    }
    if {[string length $tgzFile] == 0} {
      set tgzFile [getUpload]
    }
    exec tar -zxvf $tgzFile -C $dstFolder
  }

  proc remoteFolderWithEndSlash {} {
    variable envLines
    variable topDict
    set remoteFolder [dict get $topDict remoteFolder]
    if {[regexp {.*/$} $remoteFolder]} {
      return $remoteFolder
    } else {
      return "${remoteFolder}/"
    }
  }

  proc toDictList {lines} {
    set dictList {}
    set oblines {}
    set start 0
    foreach line $lines {
      if {$start} {
        lappend oblines $line
      }
      if {[regexp {^-\s+[^:]+:\s+} $line]} {
        if {$start} {
          lappend dictList [todict [upgradeLevel $oblines]]
          set oblines {}
        }
        set start 1
        lappend oblines [regsub {^-} $line { }]
      }
    }
    if {[llength $oblines] > 0} {
      lappend dictList [todict [upgradeLevel $oblines]]
    }
    return $dictList
  }

  proc toValueList {lines} {
    set valueList {}
    foreach line $lines {
      lappend valueList [regsub {^-\s+} $line {}]
    }
    return $valueList
  }

  proc mybox {} {
    variable topDict
    set boxLines [upgradeLevel [dict get $topDict box]]
    todict $boxLines
  }

  proc boxGroup {} {
    variable topDict
    set groupLines [upgradeLevel [dict get $topDict boxGroup]]
    set bgdict [todict $groupLines]
    dict set bgdict boxes [toDictList [upgradeLevel [dict get $bgdict boxes]]]
    return $bgdict
  }

  proc getUploads {{ptn {}}} {
    variable topDict
    set softwareLines [upgradeLevel [dict get $topDict software]]
    set softwareDict [todict $softwareLines]
    set filesToUploadLines [upgradeLevel [dict get $softwareDict filesToUpload]]
    set filesToUploadList [toValueList $filesToUploadLines]
    set files {}
    foreach fullFn $filesToUploadList {
      regexp {^".*?([^/]+)"$} $fullFn whole fn
      if {[regexp $ptn $fn]} {
        lappend files "[remoteFolderWithEndSlash]$fn"
      }
    }
    return $files
  }

  proc getUpload {{ptn ""}} {
    set files [getUploads $ptn]
    if {[llength $files] > 0} {
      return [lindex $files 0]
    }
  }

  proc readLines {fileName} {
    return [split [readWholeFile $fileName] \n]
  }

  proc readWholeFile {fileName} {
    if {[catch {open $fileName} fid o]} {
      puts $fid
      exit 1
    } else {
      set data [read $fid]
      close $fid
    }
    return $data
  }

  proc writeFile {fileName content} {
    if {[catch {open $fileName w} fid o]} {
      puts $fid
      exit 1
    } else {
      puts $fid $content
      close $fid
    }
  }

  proc writeFileLines {fileName lines} {
    if {[catch {open $fileName w} fid o]} {
      puts $fid
      exit 1
    } else {
      foreach line $lines {
          puts $fid $line
      }
      close $fid
    }
  }

  proc sethostname {hn} {
    if {[string length $hn] > 0} {
      exec hostnamectl set-hostname $hn --static
    }
  }

  proc backupOrigin {fn} {
    if {[file exists $fn]} {
      set of "$fn.origin"
      if {! [file exists $of]} {
        exec cp $fn $of
      }
    }
  }

  proc splitLine {longline} {
    set newlines {}
    set lines [split $longline "\n"]
    foreach line $lines {
      lappend newlines $line
    }
    return $newlines
  }
  
  proc trimLeftLines {lines} {
    set newlines {}
    foreach line $lines {
      lappend newlines [string trim $line]
    }
    return $newlines
  }

  proc setupResolver {nameserver} {
    set resolverFile /etc/resolv.conf
    backupOrigin $resolverFile
    if {[catch {open $resolverFile w} fid o]} {
      puts $fid
      exit 1
    } else {
      puts $fid "nameserver $nameserver"
      close $fid
    }
  }

  proc openFirewall {prot args} {
    foreach port $args {
      catch {exec firewall-cmd --permanent --zone=public --add-port ${port}/$prot} msg o
    }
    catch {exec firewall-cmd --reload} msg o
  }

  proc isInstalled {execName} {
    catch {exec which $execName} msg o
    if {[dict get $o -code] == 0} {
      return 1
    }
    return 0
  }
}
