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
function statusAPI_POST() {
  curl -s -X POST \
    https://instant-status.example.org/api/v2/"$1" \
    -H 'Authorization: Bearer eyJ' \
    -H 'Content-Type: application/json' \
    --data-raw "$2"
}

##### VARIABLES #####
permFileWd="/etc/faf"
tempPrefix="tempFaF"

lastUpdateId=$(cat "$permFileWd/lastUpdateId.txt")

##### CHECKING CACHED INFO #####
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

stackId=$(cat "$permFileWd/stackId.txt")
ec2UserDataStackLower=$(cat "$permFileWd/ec2UserDataLower-stack.txt")

appTag=$(sudo su - appuser -c 'cd /usr/local/appuser/current/ && git describe --tags')
appBranch=$(sudo su - appuser -c 'cd /usr/local/appuser/current/ && git rev-parse --abbrev-ref HEAD')
if [[ "$appBranch" == "HEAD" ]]; then appVersion="$appTag"; else appVersion="$appBranch"; fi

##### CHECKING TIME LOCK #####
if [[ -f "$permFileWd/updateTimeLock.txt" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] Update time lock exists..."
  updateTimeLock=$(cat "$permFileWd/updateTimeLock.txt")
  diffBetweenUpdateTimeLockAndNow="$(("$(date '+%s')" - "$updateTimeLock"))"
  if [[ $diffBetweenUpdateTimeLockAndNow -lt $((60 * 6)) ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ... an update time lock exists and time diff is not older than 6 minutes. QUITTING."
    ##### SEND SLIM DATA #####
    JSONData="{
      \"is_slim_check_in\": true,
      \"server_id\": $(jq -R <<<"$ec2InstanceId"),
      \"stack_id\": $(jq -R <<<"$stackId"),
      \"last_update_id\": $(jq -R <<<"$lastUpdateId"),
      \"server_disk_used_gb\": $(df -h -B1073742000 / | grep ^/ | awk '{print $3}'),
      \"server_health_updated_at\": \"$(date '+%Y-%m-%dT%H:%M:%SZ')\",
      \"server_health_code\": 1,
      \"server_health_message\": \"Update in Progress, full healthcheck not performed.\"
    }"
    response=$(statusAPI_POST "check-in" "$JSONData")
    echo "$response" | jq -r .
    exit
  fi
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ... an update time lock doesn't exist, or exists and time diff IS OLDER than 6 minutes... Continuing."

##### GATHERING HEALTH INFO #####
healthCode=0
healthMessage="All Good!"

if sudo service nginx status >/dev/null 2>&1; then
  echo "[$(date -u)] Nginx running"
else
  echo "[$(date -u)] Nginx not running"
  healthCode=3
  healthMessage="Nginx is not running"
fi

if [[ -f "$workingDirectory/$tempPrefix-lastErrorText.txt" ]]; then
  healthCode=3
  healthMessage+=" | UPDATE FAILED: $(cat "$workingDirectory/$tempPrefix-lastErrorText.txt")"
fi

##### CHECK FOR UPDATE, SEND NEW DATA #####
JSONData="{
  \"server_id\": $(jq -R <<<"$ec2InstanceId"),
  \"stack_id\": $(jq -R <<<"$stackId"),
  \"last_update_id\": $(jq -R <<<"$lastUpdateId"),
  \"stack_region\": $(jq -R <<<"$ec2Region"),
  \"stack_environment\": \"$(grep -m 1 "FAF_ENVIRONMENT" /usr/local/appuser/current/.env | cut -c 17-)\",
  \"stack_logo_url\": \"$(grep -m 1 "FAF_STACK_LOGO" /usr/local/appuser/current/.env | cut -c 16-)\",
  \"stack_app_url\": \"$(grep -m 1 "APP_URL" /usr/local/appuser/current/.env | cut -c 9-)/login/local\",
  \"stack_logs_url\": \"https://$ec2Region.console.aws.amazon.com/cloudwatch/home?region=$ec2Region#logStream:group=appuser-$ec2UserDataStackLower\",
  \"server_public_ip\": \"$(ec2metadata --public-ipv4)\",
  \"server_app_version\": $(jq -R <<<"$appVersion"),
  \"server_disk_used_gb\": $(df -h -B1073742000 / | grep ^/ | awk '{print $3}'),
  \"server_disk_total_gb\": $(df -h -B1073742000 / | grep ^/ | awk '{print $2}'),
  \"server_key_file_name\": \"$(ec2metadata --public-keys | cut -d" " -f3 | cut -d"'" -f1)\",
  \"server_availability_zone\": $(jq -R <<<"$ec2AZ"),
  \"server_type\": \"$(ec2metadata --instance-type)\",
  \"server_health_updated_at\": \"$(date '+%Y-%m-%dT%H:%M:%SZ')\",
  \"server_health_code\": $healthCode,
  \"server_health_message\": $(jq -R <<<"$healthMessage"),
  \"server_update_progress\": 100
}"
response=$(statusAPI_POST "check-in" "$JSONData")
echo "$response" | jq -r . || checkExit 'Could not parse JSON!' 1
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || checkExit '"ok" is not "true"!' 1

responseUpdateAvailable=$(echo "$response" | jq -r '."update_available"')
if [[ "$responseUpdateAvailable" != "true" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ❌ UPDATE IS NOT AVAILABLE"
  exit 1
else
  # Place new time lock file.
  date '+%s' --date='6 minutes' | sudo tee "$permFileWd/updateTimeLock.txt"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ✅ UPDATE IS AVAILABLE"
  responseUpdateId=$(echo "$response" | jq -r '."update_id"')
  echo "$responseUpdateId" | sudo tee "$permFileWd/updateId.txt"
fi

##### DOWNLOADING FaF #####
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] Downloading code..."
if [[ -d "$workingDirectory/FaF" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ...FaF folder already exists, it shouldn't - quitting."
  exit 1
fi
git clone git@FaF.github.com:asahd/Fire-and-Fury.git "$workingDirectory/FaF"
rm -rf "$workingDirectory/FaF/.git"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ...done."

if [[ -f "$permFileWd/isPrimal.txt" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] Removing '$permFileWd/isPrimal.txt' file..."
  sudo rm -f "$permFileWd/isPrimal.txt"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ...done."
fi

##### RESET TEMP FILES #####
rm "$workingDirectory/$tempPrefix-"*

##### RUN UPDATE #####
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] Running update..."
bash "$workingDirectory/FaF/00-runner.sh"
if [[ $? -eq 0 ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ...done."
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CHECK-IN] ...update exited with code '$?'. FAILED?."
fi
