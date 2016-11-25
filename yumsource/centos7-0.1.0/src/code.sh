bakname="/etc/yum.repos.d/CentOS-Base.repo.backup"
oriname="/etc/yum.repos.d/CentOS-Base.repo"

extractUploads() {
  fullNameRegex='filesToUpload.*?\[\"(.*?)\"\]'
  nameRegex='[^/]+$'
  if [[ $1 =~ $fullNameRegex ]]
  then
    fullname="${BASH_REMATCH[1]}"
    if [[ $fullname =~ $nameRegex ]]
    then
      echo "${BASH_REMATCH[0]}"
    fi
  fi
}

if [[ ! -f $bakname ]]
then
  cp $oriname $bakname
fi

case "$4" in
  changeYumSource)
    fc=`cat $2`
    name=$(extractUploads "$fc")
    if [[ $name ]]
    then
      cp -f "/easy-installer/$name" $oriname
      yum clean all
      yum makecache
      echo "@@success@@"
    fi
  ;;
  restoreYumSource)
    if [[ -f $bakname ]]
    then
      cp -f $bakname $oriname
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
