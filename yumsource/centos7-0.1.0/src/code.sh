baseOriname="/etc/yum.repos.d/CentOS-Base.repo"
epelOriname="/etc/yum.repos.d/epel.repo"
epelTestOriName="/etc/yum.repos.d/epel-testing.repo"

# insert-common-script-here:bash/common.sh
catch {source "../../src/main/resources/com/jianglibo/easyinstaller/scriptsnippets/bash/common.sh"} msg

if [[ ! -f "${baseOriname}.bakcup" ]];then
  cp $baseOriname "${baseOriname}.backup" 2>/dev/null
fi

if [[ ! -f "${epelOriname}.bakcup" ]];then
  cp $epelOriname "${epelOriname}.backup" 2>/dev/null
fi

case "$4" in
  changeYumSource)
    basefn=$(getUploads "$2" "^Centos-7.repo$")
    epelfn=$(getUploads "$2" "^epel-7.repo$")

    if [[ $basefn ]];then
      cp -f "/easy-installer/$basefn" $baseOriname
    else
      echo "$basefn can't found. Please take care of character case."
      exit 1
    fi
    if [[ $epelfn ]];then
      cp -f "/easy-installer/$epelfn" $epelOriname
      if [[ ! -f "${epelTestOriName}.backup" ]];then
        cp -f $epelTestOriName "${epelTestOriName}.backup"
      fi
      if [[ -f $epelTestOriName ]] && [[ -f "${epelTestOriName}.backup" ]];then
        rm -f $epelTestOriName
      fi
    else
      echo "$epelfn can't found. Please take care of character case."
    fi
    yum clean all
    yum makecache
    echo "@@success@@"
  ;;
  restoreYumSource)
    if [[ -f "${baseOriname}.backup" ]];then
      cp -f "${baseOriname}.backup" $baseOriname
    fi
    if [[ -f "${epelOriname}.backup" ]];then
      cp -f "${epelOriname}.backup" $epelOriname
    fi
    if [[ ! -f $epelTestOriName ]] && [[ -f "${epelTestOriName}.backup" ]];then
      mv "${epelTestOriName}.backup" $epelTestOriName
    fi
    echo "@@success@@"
  ;;
  *)
  echo "no such action: ${4}"
esac

echo $1
echo $2
echo $3
echo $4
exit 0
