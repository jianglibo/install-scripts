yamlarraylineRegex="^[[:blank:]]*-[[:blank:]]+\"(.*)\"$"
pathLeafRegex=".*?/([^/]+)$"

getUploads() {
  local start=false
  local filesToUploadLineRegex='^[[:blank:]]*filesToUpload:[[:blank:]]*$'
  # whitespace prefix already trimmed.
  cat "$1" | while read line || [[ -n "$line" ]];do
    if $start;then
      if [[ $line =~ $yamlarraylineRegex ]];then
        fullname="${BASH_REMATCH[1]}"
        if [[ $fullname =~ $pathLeafRegex ]];then
          name="${BASH_REMATCH[1]}"
          if [[ "$name" =~ $2 ]];then
            echo "$name"
          fi
        fi
      else
        break
      fi
    fi
    if [[ $line =~ $filesToUploadLineRegex ]];then
      start=true
    fi
  done
}
