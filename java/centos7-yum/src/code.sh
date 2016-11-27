result=$(which java)
if [ "$?" -ne 0 ]; then
   result=$(yum install -y java-1.8.0-openjdk.x86_64)
   if [ $? -ne 0 ]; then
      exit 1
   fi
fi

echo "@@success@@"
exit 0
