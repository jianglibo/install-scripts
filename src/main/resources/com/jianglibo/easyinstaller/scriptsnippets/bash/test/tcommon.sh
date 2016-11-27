
testFolder=`dirname "${BASH_SOURCE-$0}"`
. "${testFolder}/../common.sh"

tfile="${testFolder}/../fixtures/envforcodeexec.yaml"

line='  - "http://mirrors.163.com/.help/CentOS7-Base-163.repo"'

if [[ $line =~ $yamlarraylineRegex ]];then
  fullname="${BASH_REMATCH[1]}" 
  if [[ "$fullname" == "http://mirrors.163.com/.help/CentOS7-Base-163.repo" ]];then
    if [[ $fullname =~ $pathLeafRegex ]];then
      echo "" #"${BASH_REMATCH[1]}" 
    else
      exit 1
    fi
  else
    exit 1
  fi
else
  exit 1
fi

getUploads $tfile "^CentOS7-Base.*repo$"
