#!/usr/bin/env bash
function cancel_update_and_exit_on_error() {
  # $1 - Error Message to Log
  output_log "$ec2InstanceId - ERROR" "$1" "$actionsLogFile"

  ##### UPDATE STATUS #####
  JSONData="{
    \"update_id\": $(jq -R <<<"$updateId"),
    \"server_id\": $(jq -R <<<"$ec2InstanceId"),
    \"server_update_progress\": 1,
    \"server_update_stage\": \"request-update-cancellation\",
    \"server_update_message\": \"Cancelling...\"
  }"
  statusAPI_POST "update" "$JSONData"

  echo "$1" >"$workingDirectory/$tempPrefix-lastErrorText.txt"
  sudo rm -rf "$permFileWd/updateTimeLock.txt" "$workingDirectory/FaF"
  exit 1
}
