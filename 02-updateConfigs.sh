#!/usr/bin/env bash
##### VARIABLES #####
ec2UserDataStackLower=$(cat "$permFileWd/ec2UserDataLower-stack.txt")
ec2Region=$(cat "$permFileWd/ec2Region.txt")

output_log "$ec2InstanceId - CONFIG" "Going to update all Config files." "$actionsLogFile"
output_log "$ec2InstanceId - CONFIG" "Backing up User Config files..." "$actionsLogFile"

# Back-up User Configs
cp -p "$workingDirectory/.profile" "$workingDirectory/.profile.bak"

output_log "$ec2InstanceId - CONFIG" "...backing up General Config files..." "$actionsLogFile"
# Back-up General Configs
sudo cp -p /var/awslogs/etc/aws.conf /var/awslogs/etc/aws.conf.bak
sudo cp -p /var/awslogs/etc/awslogs.conf /var/awslogs/etc/awslogs.conf.bak
sudo cp -p /etc/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf.bak
sudo cp -p /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - CONFIG" "Updating User Config files..." "$actionsLogFile"
# Update User Configs
cat "$workingDirectory/FaF/confs/__home__ubuntu__.profile" | tee "$workingDirectory/.profile" >/dev/null 2>&1
# Update file permissions in case the file did not exist before
# - would have been created with the wrong permissions
chmod 644 "$workingDirectory/.profile"
cat "$workingDirectory/FaF/confs/__usr__local__appuser__.bashrc" | sudo tee "$secondaryWorkingDirectory/.bashrc" >/dev/null 2>&1
# Update file owner and permissions in case the file did not exist before
# - would have been created with the wrong owner and permissions
sudo chown appuser: "$secondaryWorkingDirectory/.bashrc"
sudo chmod 664 "$secondaryWorkingDirectory/.bashrc"

output_log "$ec2InstanceId - CONFIG" "...updating General Config files..." "$actionsLogFile"
# Update General Configs
cat "$workingDirectory/FaF/confs/__var__awslogs__etc__aws.conf" | sudo tee /var/awslogs/etc/aws.conf >/dev/null 2>&1
sudo sed -i "s/<<ec2Region>>/$ec2Region/g" /var/awslogs/etc/aws.conf
cat "$workingDirectory/FaF/confs/__var__awslogs__etc__awslogs.conf" | sudo tee /var/awslogs/etc/awslogs.conf >/dev/null 2>&1
sudo sed -i "s/<<ec2UserDataStackLower>>/$ec2UserDataStackLower/g" /var/awslogs/etc/awslogs.conf
cat "$workingDirectory/FaF/confs/__etc__nginx__conf.d__app.conf" | sudo tee /etc/nginx/conf.d/app.conf >/dev/null 2>&1
cat "$workingDirectory/FaF/confs/__etc__nginx__nginx.conf" | sudo tee /etc/nginx/nginx.conf >/dev/null 2>&1

output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - CONFIG" "Going to update 'sbin' scripts now..." "$actionsLogFile"
cat "$workingDirectory/FaF/confs/__usr__sbin__faf-startup.sh" | sudo tee /usr/sbin/faf-startup.sh >/dev/null 2>&1
cat "$workingDirectory/FaF/confs/__usr__sbin__faf-checkin.sh" | sudo tee /usr/sbin/faf-checkin.sh >/dev/null 2>&1
output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - CONFIG" "Going to update crontab[le] now..." "$actionsLogFile"
sudo crontab -u ubuntu "$workingDirectory/FaF/confs/crontab/ubuntu__all_servers.cron"
output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - CONFIG" "Going to update logrotate now..." "$actionsLogFile"
cat "$workingDirectory/FaF/confs/__etc__logrotate.d__faf" | sudo tee /etc/logrotate.d/faf >/dev/null 2>&1
output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"

output_log "$ec2InstanceId - CONFIG" "Going to update SSH keys and configs now..." "$actionsLogFile"
output_log "$ec2InstanceId - CONFIG" "...configuring for 'ubuntu'..." "$actionsLogFile"
find "$workingDirectory/.ssh/" -type f -not -name 'authorized_keys' -not -name 'known_hosts' -delete
cp "$workingDirectory/FaF/ssh/ubuntu-"* "$workingDirectory/.ssh/"
mv "$workingDirectory/.ssh/ubuntu-config" "$workingDirectory/.ssh/config"
sudo chmod 600 "$workingDirectory/.ssh/"* && sudo chmod 644 "$workingDirectory/.ssh/"*.pub

output_log "$ec2InstanceId - CONFIG" "...configuring for 'appuser'..." "$actionsLogFile"
sudo find "$secondaryWorkingDirectory/.ssh/" -type f -not -name 'known_hosts' -delete
sudo cp "$workingDirectory/FaF/ssh/appuser-"* "$secondaryWorkingDirectory/.ssh/"
sudo mv "$secondaryWorkingDirectory/.ssh/appuser-config" "$secondaryWorkingDirectory/.ssh/config"
sudo chown -R appuser: "$secondaryWorkingDirectory/.ssh/"
# If we don't run these as the 'appuser' user, they error out due to strict permissions
sudo su - appuser -c 'chmod 600 /usr/local/appuser/.ssh/* && chmod 644 /usr/local/appuser/.ssh/*.pub'

output_log "$ec2InstanceId - CONFIG" "...done." "$actionsLogFile"
