echo $1
echo $2
echo $3
echo $4
echo "$(echo $5 | base64 --decode)"
eval "$(echo $5 | base64 --decode)"
echo "@@success@@"
exit 0
