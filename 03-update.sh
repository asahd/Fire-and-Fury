#!/usr/bin/env bash
##### VARIABLES #####
ec2UserDataStackLower=$(cat "$permFileWd/ec2UserDataLower-stack.txt")

updateAppTo=$(cat "$workingDirectory/$tempPrefix-updateAppTo.txt")
shouldRunMigrations=$(cat "$workingDirectory/$tempPrefix-shouldRunMigrations.txt")
echo "$secondaryWorkingDirectory/releases/$(date "+%Y-%m-%d_%H.%M.%S_$updateAppTo")" >"$workingDirectory/$tempPrefix-newReleaseWd.txt"
newReleaseWd=$(cat "$workingDirectory/$tempPrefix-newReleaseWd.txt")

##### UPDATE STATUS #####
JSONData="{
  \"update_id\": $(jq -R <<<"$updateId"),
  \"server_id\": $(jq -R <<<"$ec2InstanceId"),
  \"server_update_progress\": 25,
  \"server_update_stage\": \"installation\",
  \"server_update_message\": \"Downloading Code...\"
}"
response=$(statusAPI_POST "update" "$JSONData")
echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."

output_log "$ec2InstanceId - UPDATE" "Constructing and placing install script." "$actionsLogFile"

sudo tee "$secondaryWorkingDirectory/$tempPrefix-install.sh" <<EOF >/dev/null 2>&1
#!/usr/bin/env bash
##### IMPORTING MODULES #####
source "$workingDirectory/FaF/modules/output_log.sh"

##### VARIABLES #####
errorLogFile="$secondaryWorkingDirectory/$tempPrefix-install-error-log.txt"
appBranch="$updateAppTo"
newReleaseWd="$(cat "$workingDirectory/$tempPrefix-newReleaseWd.txt")"

cd "$secondaryWorkingDirectory/releases/"
output_log "$ec2InstanceId - {appuser} INSTALL" "Going to delete all releases except the last five..." "$actionsLogFile"
rm -rf "\$(ls -t | tail -n +6)"
output_log "$ec2InstanceId - {appuser} INSTALL" "...done." "$actionsLogFile"
output_log "$ec2InstanceId - {appuser} INSTALL" "Downloading '\$appBranch' and installing..." "$actionsLogFile"

output_log "$ec2InstanceId - {appuser} INSTALL" "Cloning into new release directory..." "$actionsLogFile"
git clone --branch "\$appBranch" --depth 1 "$appGitRemoteURL" "\$newReleaseWd"
if [[ $? -eq 0 ]]; then
  output_log "$ec2InstanceId - {appuser} INSTALL" "...done" "$actionsLogFile"
else
  output_log "$ec2InstanceId - {appuser} INSTALL" "'\$appBranch' does NOT seem to exist as a branch or a version, or GitHub is having issues" "$actionsLogFile"
  echo "'\$appBranch' does NOT seem to exist as a branch or a version, or GitHub is having issues" >"\$errorLogFile"
  exit 1
fi

output_log "$ec2InstanceId - {appuser} INSTALL" "...done." "$actionsLogFile"

# ENV files can be set here, in addition, build steps for complex apps can be performed here

EOF

output_log "$ec2InstanceId - UPDATE" "...constructed and placed script, now running..." "$actionsLogFile"
sudo su - appuser -c "cd $secondaryWorkingDirectory && bash '$tempPrefix-install.sh'" || cancel_update_and_exit_on_error "Update script did not exit cleanly! $(cat "$secondaryWorkingDirectory/$tempPrefix-install-error-log.txt")"
output_log "$ec2InstanceId - UPDATE" "...done." "$actionsLogFile"

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

responseChosenOne=$(echo "$response" | jq -r '."chosen_one"')
responseServerCount=$(echo "$response" | jq -r '."server_count"')
responseServerReadyToSwitchCount=$(echo "$response" | jq -r '."server_ready_to_switch_count"')

if [[ "$ec2InstanceId" == "$responseChosenOne" ]]; then
  # SERVER IS THE CHOSEN ONE
  output_log "$ec2InstanceId - UPDATE" "This server is The Chosen One :)" "$actionsLogFile"

  output_log "$ec2InstanceId - CONFIG" "Going to update crontab[le] now..." "$actionsLogFile"
  sudo crontab -u appuser "$workingDirectory/FaF/confs/crontab/appuser__one_server.cron"
  output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

  # WAIT UNTIL THE NON CHOSEN ONES HAVE DOWNLOADED AND ARE READY TO SWITCH
  waitLoop=1
  while [[ $(($responseServerCount - 1)) -ne $responseServerReadyToSwitchCount ]]; do
    if [[ $waitLoop -ge 21 ]]; then
      output_log "$ec2InstanceId - UPDATE" "Tried 21 or more times...QUITTING." "$actionsLogFile"
      cancel_update_and_exit_on_error "Tried 21 or more times..."
    else
      output_log "$ec2InstanceId - UPDATE" "This is try $waitLoop" "$actionsLogFile"
      sleep 5s
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

      responseServerCount=$(echo "$response" | jq -r '."server_count"')
      responseServerReadyToSwitchCount=$(echo "$response" | jq -r '."server_ready_to_switch_count"')
      waitLoop=$(($waitLoop + 1))
    fi
  done
  output_log "$ec2InstanceId - UPDATE" "Okay, all non-Chosen Ones have finished now, going to run once-per-stack commands..." "$actionsLogFile"

  ##### UPDATE STATUS #####
  JSONData="{
    \"update_id\": $(jq -R <<<"$updateId"),
    \"server_id\": $(jq -R <<<"$ec2InstanceId"),
    \"server_update_progress\": 75,
    \"server_update_stage\": \"special\",
    \"server_update_message\": \"Running Special Tasks...\"
  }"
  response=$(statusAPI_POST "update" "$JSONData")
  echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
  responseOk=$(echo "$response" | jq -r '."ok"')
  [[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."

  # Any other update tasks that should be performed only ONCE per update can be done here

  output_log "$ec2InstanceId - UPDATE" "...Done running once-per-stack commands, now checking if asked to migrate." "$actionsLogFile"
  if [[ "$shouldRunMigrations" == "true" ]]; then
    output_log "$ec2InstanceId - UPDATE" "Migrations requested, constructing and placing migrations script." "$actionsLogFile"

    sudo tee "$secondaryWorkingDirectory/$tempPrefix-migrate.sh" <<EOF >/dev/null 2>&1
#!/usr/bin/env bash
# Migrations can be performed here
# E.g:

##### VARIABLES #####
appMigrationOutputFile="$secondaryWorkingDirectory/$tempPrefix-app-migration-output.txt"

output_log "$ec2InstanceId - {appuser} MIGRATE" "Migrating app..." "$actionsLogFile"
cd "$newReleaseWd/app" && app migrate 2>&1 | tee "\$appMigrationOutputFile"
output_log "$ec2InstanceId - {appuser} MIGRATE" "\$(cat \$appMigrationOutputFile)" "$actionsLogFile"
if [[ "\$(grep -c 'SQLSTATE' \$appMigrationOutputFile)" -eq "0" ]]; then
  appMigrationAlertText=\$(cat \$appMigrationOutputFile)
  echo "\$appMigrationAlertText" >"$secondaryWorkingDirectory/$tempPrefix-app-migration-alert.txt"
else
  appMigrationAlertText='⚠️ App Migrations Failed. Needs Manual Investigation! ⚠️'
  echo "\$appMigrationAlertText" >"$secondaryWorkingDirectory/$tempPrefix-app-migration-alert.txt"
  output_log "$ec2InstanceId - {appuser} MIGRATE" "\$appMigrationAlertText" "$actionsLogFile"
  exit 1
fi
output_log "$ec2InstanceId - {appuser} MIGRATE" "...done." "$actionsLogFile"

EOF

    output_log "$ec2InstanceId - UPDATE" "...constructed and placed script, now running..." "$actionsLogFile"
    sudo su - appuser -c "cd $secondaryWorkingDirectory && bash '$tempPrefix-migrate.sh'" || cancel_update_and_exit_on_error "Migration script did not exit cleanly! App migrations failed."
    output_log "$ec2InstanceId - UPDATE" "...done." "$actionsLogFile"

    # appMigrationOutput=$(cat "$secondaryWorkingDirectory/$tempPrefix-app-migration-alert.txt")
    # send_slack_alert "ORG/CHANNEL/KEY" "{\"icon_emoji\":\":information_source:\",\"username\":\"App ( ${ec2UserDataStackLower} ) Migrations Output\",\"text\":\"*Message from *\`${ec2InstanceId}\` | \`${ec2UserDataStackLower}\`\",\"attachments\":[{\"fields\":[{\"title\":\"For version\",\"value\":\"\`${updateAppTo}\`\",\"short\":true}],\"color\":\"#0d6788\"},{\"title\":\"App Migrations Output\",\"text\":\"\`\`\`${appMigrationOutput}\`\`\`\",\"color\":\"#880d67\"}]}"
  else
    output_log "$ec2InstanceId - UPDATE" "Migrations were not requested, skipping." "$actionsLogFile"
  fi

  ##### UPDATE STATUS #####
  JSONData="{
    \"update_id\": $(jq -R <<<"$updateId"),
    \"server_id\": $(jq -R <<<"$ec2InstanceId"),
    \"server_update_progress\": 90,
    \"server_update_stage\": \"ready-to-switch\",
    \"server_update_message\": \"Announcing Switch...\"
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

  switchCodeAtDate=$(echo "$response" | jq -r '."switch_code_at_date"')
else
  # SERVER IS NOT THE CHOSEN ONE
  output_log "$ec2InstanceId - UPDATE" "This server is NOT The Chosen One :(" "$actionsLogFile"

  output_log "$ec2InstanceId - CONFIG" "Going to update crontab[le] now..." "$actionsLogFile"
  sudo crontab -u appuser "$workingDirectory/FaF/confs/crontab/appuser__all_servers.cron"
  output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

  ##### UPDATE STATUS #####
  JSONData="{
    \"update_id\": $(jq -R <<<"$updateId"),
    \"server_id\": $(jq -R <<<"$ec2InstanceId"),
    \"server_update_progress\": 90,
    \"server_update_stage\": \"ready-to-switch\",
    \"server_update_message\": \"Waiting for Switch...\"
  }"
  response=$(statusAPI_POST "update" "$JSONData")
  echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
  responseOk=$(echo "$response" | jq -r '."ok"')
  [[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."

  # WAIT FOR CHOSEN ONE TO BE READY TO SWITCH TOO
  waitLoop=1
  while [[ $responseServerCount -ne $responseServerReadyToSwitchCount ]]; do
    if [[ $waitLoop -ge 21 ]]; then
      output_log "$ec2InstanceId - UPDATE" "Tried 21 or more times...QUITTING." "$actionsLogFile"
      cancel_update_and_exit_on_error "Tried 21 or more times..."
    else
      output_log "$ec2InstanceId - UPDATE" "This is try $waitLoop" "$actionsLogFile"
      sleep 15s
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

      responseServerCount=$(echo "$response" | jq -r '."server_count"')
      responseServerReadyToSwitchCount=$(echo "$response" | jq -r '."server_ready_to_switch_count"')
      waitLoop=$(($waitLoop + 1))
    fi
  done
  output_log "$ec2InstanceId - UPDATE" "Okay, The Chosen One has finished now, continuing..." "$actionsLogFile"
  switchCodeAtDate=$(echo "$response" | jq -r '."switch_code_at_date"')
fi

output_log "$ec2InstanceId - UPDATE" "Need to wait until: $switchCodeAtDate, ($(($switchCodeAtDate - $(date '+%s'))) seconds) to switch" "$actionsLogFile"
sleep "$(($switchCodeAtDate - $(date '+%s')))s"
output_log "$ec2InstanceId - UPDATE" "Current Time: $(date '+%s')" "$actionsLogFile"

##### UPDATE STATUS #####
JSONData="{
  \"update_id\": $(jq -R <<<"$updateId"),
  \"server_id\": $(jq -R <<<"$ec2InstanceId"),
  \"server_update_progress\": 99,
  \"server_update_stage\": \"special\",
  \"server_update_message\": \"Switching!\"
}"
response=$(statusAPI_POST "update" "$JSONData")
echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."

output_log "$ec2InstanceId - UPDATE" "Switching out the app symlink..." "$actionsLogFile"
sudo su - appuser -c 'cd "'"$secondaryWorkingDirectory"'" && unlink current && ln -s "'"$newReleaseWd"'" current'
output_log "$ec2InstanceId - UPDATE" "...done." "$actionsLogFile"
output_log "$ec2InstanceId - UPDATE" "Will reload nginx and restart and awslogs now..." "$actionsLogFile"
sudo service nginx reload
sudo service awslogs restart

sudo cp -p "$permFileWd/updateId.txt" "$permFileWd/lastUpdateId.txt"

##### UPDATE STATUS #####
JSONData="{
  \"update_id\": $(jq -R <<<"$updateId"),
  \"server_id\": $(jq -R <<<"$ec2InstanceId"),
  \"server_update_progress\": 100,
  \"server_update_stage\": \"finished\",
  \"server_update_message\": \"Update Finished!\"
}"
response=$(statusAPI_POST "update" "$JSONData")
echo "$response" | jq -r . || cancel_update_and_exit_on_error 'Could not parse response JSON!'
responseOk=$(echo "$response" | jq -r '."ok"')
[[ "$responseOk" == "true" ]] || cancel_update_and_exit_on_error "Non-ok response was received."

output_log "$ec2InstanceId - UPDATE" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - UPDATE" "Cleaning up..." "$actionsLogFile"
sudo rm -rf "$permFileWd/updateTimeLock.txt" "$workingDirectory/FaF"
output_log "$ec2InstanceId - UPDATE" "...done." "$actionsLogFile"
