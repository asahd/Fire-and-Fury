#!/usr/bin/env bash
output_log "$ec2InstanceId - SAFETY" "Checking if it's safe to start an update..." "$actionsLogFile"

##### GETTING SERVER INFO #####
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

date '+%s' >"$workingDirectory/$tempPrefix-timeStartUNIX.txt"

##### UPDATE STATUS #####
JSONData="{
  \"update_id\": $(jq -R <<<"$updateId"),
  \"server_id\": $(jq -R <<<"$ec2InstanceId"),
  \"server_update_progress\": 5,
  \"server_update_stage\": \"election\",
  \"server_update_message\": \"Casting Vote...\"
}"
response=$(statusAPI_POST "update" "$JSONData")
echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."

##### GET UPDATE INFO #####
JSONData="{
  \"update_id\": $(jq -R <<<"$updateId")
}"
response=$(statusAPI_GET "update" "$JSONData")
echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."
responseIsCancelled=$(echo "$response" | jq -r '."is_cancelled"')
[[ "$responseIsCancelled" == "false" ]] || cancel_update_and_exit_on_error 'Update was cancelled by another server.'

updateAppTo=$(echo "$response" | jq -r '."update_app_to"')
shouldRunMigrations=$(echo "$response" | jq -r '."run_migrations"')

echo "$updateAppTo" >"$workingDirectory/$tempPrefix-updateAppTo.txt"
echo "$shouldRunMigrations" >"$workingDirectory/$tempPrefix-shouldRunMigrations.txt"

output_log "$ec2InstanceId - SAFETY" "Checking if '$updateAppTo' exists..." "$actionsLogFile"

if check_existence_on_git_remote "$appGitRemoteURL" "$updateAppTo"; then
  output_log "$ec2InstanceId - SAFETY" "...done, it does." "$actionsLogFile"
else
  output_log "$ec2InstanceId - SAFETY" "...it doesn't." "$actionsLogFile"
  output_log "$ec2InstanceId - SAFETY" "'$updateAppTo' does NOT seem to exist as a branch or a version, or GitHub is having issues" "$actionsLogFile"
  cancel_update_and_exit_on_error "'$updateAppTo' does NOT seem to exist as a branch or a tag, or GitHub is having issues"
  exit 1
fi

output_log "$ec2InstanceId - SAFETY" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - SAFETY" "Updating app to $updateAppTo" "$actionsLogFile"
