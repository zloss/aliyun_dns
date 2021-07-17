#!/bin/bash
# alidns.sh
# 阿里云DNS api接口 shell 更改DNS解析
which dig &>/dev/null || { echo "need to install dig (yum install -y bind-utils;)";exit 1; }
which jq &>/dev/null || { echo "need to install jq (yum install -y jq;)";exit 1; }
apiurl="https://alidns.aliyuncs.com"
domain="abc.com" #域名
ak="abcdefghijklmnopqrstuvwx"  #阿里云AccessKey ID
sk="abcdefghijklmnopqrstuvwxyz1234&"  #阿里云Access Key Secret  后面多个 &
dnsip=140.205.41.25 #dns9.hichina.com
timestamp(){
  # date -u +"%Y-%m-%dT%H:%M:%SZ"
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

urlencode(){
  curl -s -o /dev/null -w %{url_effective} --get --data-urlencode "_=$1" "" -o - | sed 's#^/?_=##g'
}

nonce(){
  #cat /dev/urandom | tr -dc A-Za-z0-9-_ | head -c 24
  env LC_CTYPE=C tr -dc "A-Za-z0-9-" < /dev/urandom | head -c 24
}

toFirstLetterUpper() {
  str=$1
  firstLetter=`echo ${str:0:1} | awk '{print toupper($0)}'`
  otherLetter=${str:1}
  echo $firstLetter$otherLetter
}

buildQuery(){
  extra_argc=$#
  extra_argv=""
  for i in $(seq 1 1 ${extra_argc})
  do
  str=$( toFirstLetterUpper "$1" )
  key=$(echo -n "$str" | cut -d = -f 1)
  keylen=$(echo -n "$key" | awk '{ print length($0)+1; }')
  val=${str:$keylen}
  extra_argv="${extra_argv},\"${key}\":\"`urlencode $val`\""
  shift
  done
  posts=$(cat <<EOF
{
"AccessKeyId":"`urlencode $ak`"
,"Action":"`urlencode $opt`"
,"Format":"json"
,"SignatureMethod":"HMAC-SHA1"
,"SignatureNonce":"`nonce`"
,"SignatureVersion":"1.0"
,"Timestamp":"`timestamp`"
,"Version":"2015-01-09"
${extra_argv}
}
EOF
)
queryuri=""
while read key
do
val=$(echo "$posts" | jq -rc ".${key}")
queryuri="${queryuri}&${key}=${val}"
done < <( echo $posts | jq "keys|.[]" -r )
queryuri=${queryuri:1}
echo $queryuri
}

send_request() {
opt="$1"
shift
queryuri=$(buildQuery $*)
param="GET&%2F&$(urlencode $queryuri)"
signstr=$(echo -n "$param" | openssl dgst -sha1 -hmac $sk -binary | openssl base64)
Signature="&Signature="$( urlencode $signstr )
curl -k -s "${apiurl}/?${queryuri}$Signature" -o - | jq .
}
add_record() {
  host=$1
  ip=$2
  send_request AddDomainRecord "DomainName=$domain" "RR=$host" "Type=A" "Value=$ip"
}
query_record() {
  host=$1
  if [ "$host" = "@" ]; then
    send_request DescribeSubDomainRecords "SubDomain=${domain}"
  else
    send_request DescribeSubDomainRecords "SubDomain=${host}.${domain}"
  fi
}
update_record() {
  host=$1
  ip=$2
  recordId=$(query_record $host | jq -rc ".DomainRecords.Record[0].RecordId" )
  [ "$recordId" = "" ] && { echo "$host.$domain  $ip UpdateError";exit 1; }
  send_request "UpdateDomainRecord" "RR=${host}" "RecordId=${recordId}" "Type=A" "Value=$ip"
}
delete_record() {
  host=$1
  recordId=$(query_record $host | jq -rc ".DomainRecords.Record[0].RecordId" )
  [ "$recordId" = "" ] && { echo "$host.$domain  $ip DeleteError";exit 1; }
  send_request "DeleteDomainRecord" "RecordId=${recordId}"
}
remark_record() {
  host=$1
  rmk="$2"
  recordId=$(query_record $host | jq -rc ".DomainRecords.Record[0].RecordId" )
  [ "$recordId" = "" ] && { echo "$host.$domain  $ip RemarkError";exit 1; }
  send_request "UpdateDomainRecordRemark" "RecordId=${recordId}" "Remark=${rmk}"
}
usage(){
  echo "usage: $1 [q]uery [@|www|subdomain]"
  echo "       $1 [s]et www 123.123.123.123"
  echo "       $1 [d]elete www"
  echo "       $1 [r]emark www 我的解析记录"
}
alidns() {
# var:  subdomain ip
if [ $# -eq 0 ]; then
  usage $0
else
  opt="$1"
  sub="$2"
  cont="$3"
  optlen=${#opt}
  if [ $optlen -gt 1 ]; then 
    [ `echo $opt | grep -oE '^query$|^set$|^delete$|^remark$'|wc -l` -eq 0 ] && { echo "unsupported method ${opt}";exit 1; }
  else
    [ `echo $opt | grep -oE '^q$|^s$|^d$|^r$'|wc -l` -eq 0 ] && { echo "unsupported method ${opt}";exit 1; }
  fi
  OPT=${opt:0:1}
  case $OPT in
   q)
    if [ -z "$sub" -o "$sub" = "@" ]; then
      send_request DescribeDomainRecords DomainName=${domain} PageSize=200
    else
      ip_dns=$(dig @${dnsip} ${sub}.${domain} A +short)
      test -n "$ip_dns" && echo "$ip_dns $sub.$domain " || echo "$sub.$domain no found"
    fi
   ;;
   s)
    [ `echo $cont |grep -oE '^[0-9]{0,3}\.[0-9]{0,3}\.[0-9]{0,3}\.[0-9]{0,3}$' |wc -l` -eq 0 ] && { echo "ip ${cont} error";exit 1; }
    test "$cont" = "$ip_dns" && echo "$ip_dns $sub.$domain" || { [ "$ip_dns" = "" ] && { add_record "$sub" "$cont" ; } || { update_record "$sub" "$cont"; } }
   ;;
   d)
    test -z "$sub" && { echo "empty subdomain";exit 1; } || delete_record "$sub"
   ;;
   r)
    test -z "$sub" && { echo "empty subdomain";exit 1; } || ( test -z "$cont"  && { echo "empty remark";exit 1; } || remark_record "$sub" "$cont" )
   ;;
   *)
    usage
   ;;
  esac

fi
}

alidns "$@"
