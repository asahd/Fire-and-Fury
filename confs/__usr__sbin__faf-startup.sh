#!/usr/bin/env bash
workingDirectory="/home/ubuntu"
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"

##### HARD-IMPORTING MODULES #####
# check_exit.sh
function checkExit() {
  echo "$1" >&2
  if [[ "$2" != 0 ]]; then
    exit "$2"
  fi
}

# extract from send_curl_request.sh
function statusAPI_GET() {
  curl -s -X GET \
    https://instant-status.example.org/api/v2/"$1" \
    -H 'Authorization: Bearer eyJ' \
    -H 'Content-Type: application/json' \
    --data-raw "$2"
}

##### VARIABLES #####
permFileWd="/etc/faf"
tempPrefix="tempFaF"

##### CHECKING SAFETY #####
if [[ ! -f "$permFileWd/isPrimal.txt" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STARTUP] This is NOT a primal server - quitting."
  exit 0
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STARTUP] Removing temporary working directory files..."
rm "$workingDirectory/$tempPrefix-"*
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STARTUP] ...done."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STARTUP] This is a primal server - going to fetch and parse User Data..."

##### GETTING SERVER USER DATA #####
if [[ ! -f "$permFileWd/ec2InstanceId.txt" ]]; then
  ec2metadata --instance-id | sudo tee "$permFileWd/ec2InstanceId.txt"
fi
ec2InstanceId=$(cat "$permFileWd/ec2InstanceId.txt")

if [[ ! -f "$permFileWd/ec2AZ.txt" ]]; then
  ec2metadata --availability-zone | sudo tee "$permFileWd/ec2AZ.txt"
fi
ec2AZ=$(cat "$permFileWd/ec2AZ.txt")

if [[ ! -f "$permFileWd/ec2Region.txt" ]]; then
  echo "${ec2AZ::-1}" | sudo tee "$permFileWd/ec2Region.txt"
fi
ec2Region=$(cat "$permFileWd/ec2Region.txt")

curl -sL http://169.254.169.254/latest/user-data | sudo tee "$permFileWd/ec2UserData.json"
ec2UserData=$(cat "$permFileWd/ec2UserData.json")
echo "$ec2UserData" | jq -r . || checkExit 'Could not parse JSON!' 1
ec2UserDataCount=$(echo "$ec2UserData" | jq -r 'length')

echo "$ec2UserData" | jq -r '.stack' | tr '[:upper:]' '[:lower:]' | sudo tee "$permFileWd/ec2UserDataLower-stack.txt"
ec2NullUserDataCount=$(cat "$permFileWd/ec2UserDataLower-"* | grep -Ec '^null$')

##### CHECKING SERVER USER DATA #####
if [[ $ec2NullUserDataCount -gt 0 ]]; then
  # graceful_exit_on_error "User Data is incomplete... *Quitting*." "Critical Error";
  # clean_up_on_error "$cleanUpOnErrorType" "$2";
  output_log "$ec2InstanceId - SAFETY" "User Data is incomplete. QUITTING." "$workingDirectory/$tempPrefix-actionsLog.txt"
  exit 1
fi

ec2UserDataStackLower=$(cat "$permFileWd/ec2UserDataLower-stack.txt")
##### CHECK FOR STACK ID #####
###############
#   STACK ID  #
###############
JSONData="{
  \"stack_name\": $(jq -R <<<"$ec2UserDataStackLower")
}"
response=$(statusAPI_GET "stack/get-id" "$JSONData")
echo "$response" | jq -r . || checkExit 'Could not parse JSON!' 1
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || checkExit '"ok" is not "true"!' 1

responseId=$(echo "$response" | jq -r '."id"')
echo "$responseId" | sudo tee "$permFileWd/stackId.txt"

##### RUN CHECKIN #####
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STARTUP] Manually running checkin..."
bash /usr/sbin/faf-checkin.sh
