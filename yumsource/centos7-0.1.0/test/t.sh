# http://ss64.com/bash/read.html

testFolder=`dirname "${BASH_SOURCE-$0}"`
. "${testFolder}/../../../src/main/resources/com/jianglibo/easyinstaller/scriptsnippets/bash/common.sh"


if [[ ! -f "/easyinstaller/epel-7.repo" ]];then
  cp "${testFolder}/../../../tgzFolder/Centos-7.repo" "/easy-installer/"
  cp "${testFolder}/../../../tgzFolder/epel-7.repo" "/easy-installer/"
fi

bash "${testFolder}/../src/code.sh" -envfile "${testFolder}/../fixtures/envforcodeexec.yaml" -action changeYumSource
#bash "${testFolder}/../src/code.sh" -envfile "${testFolder}/../fixtures/envforcodeexec.yaml" -action restoreYumSource

tfile="${testFolder}/../fixtures/envforcodeexec.yaml"

countLine() {
  local c=0
  printf "$1" | while read line || [[ -n "$line" ]];do
    echo "11111"
    (( c += 1 ))
  done
  echo $c
}


#result=$(getUploads "$1" 'CentOS7-Base.*repo"$')

#echo $result

#line='  - "http://mirrors.163.com/.help/CentOS7-Base-163.repo"'

#if [[ "$line" =~ [[:blank:]]+-[[:blank:]]+.*?/([^/]+)\"$ ]];then
#  echo "${BASH_REMATCH[1]}"
#fi
