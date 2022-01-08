#!/usr/bin/env bash
export workingDirectory="/home/ubuntu"
export secondaryWorkingDirectory="/usr/local/appuser"

export permFileWd="/etc/faf"
export tempPrefix="tempFaF"

export ec2InstanceId=$(cat "$permFileWd/ec2InstanceId.txt")
export updateId=$(cat "$permFileWd/updateId.txt")

export actionsLogFile="$workingDirectory/$tempPrefix-actionsLog.txt"
export appGitRemoteURL="git@project.github.com:example/project.git"

##### MODULES #####
source "$workingDirectory/FaF/modules/cancel_update_and_exit_on_error.sh"
source "$workingDirectory/FaF/modules/check_existence_on_git_remote.sh"
source "$workingDirectory/FaF/modules/output_log.sh"
source "$workingDirectory/FaF/modules/send_curl_request.sh"
source "$workingDirectory/FaF/modules/send_slack_alert.sh"

export -f check_existence_on_git_remote
export -f cancel_update_and_exit_on_error
export -f output_log
export -f statusAPI_GET
export -f statusAPI_POST
export -f send_slack_alert

rm "$actionsLogFile"
touch "$actionsLogFile" && chmod 666 "$actionsLogFile"

startText="===== STARTED  [$(date '+%Y-%m-%d %H:%M:%S')] ====="

bash "$workingDirectory/FaF/01-checkSafetyAndCastVote.sh" &&
  bash "$workingDirectory/FaF/02-updateConfigs.sh" &&
  bash "$workingDirectory/FaF/03-update.sh"

echo "$startText"
echo "===== FINISHED [$(date '+%Y-%m-%d %H:%M:%S')] ====="
