result=$(which tclsh)
if [ "$?" -ne 0 ]; then
   result=$(yum install -y tcl tcllib expect dos2unix)
   if [ $? -ne 0 ]; then
      exit 1
   fi
fi

echo $1
echo $2
echo $3
echo $4
echo $5
echo $6
echo "@@success@@"
exit 0
