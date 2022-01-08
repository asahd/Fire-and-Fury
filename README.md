# Fire and Fury

## What is this?

Fire and Fury is an example bash implementation of the [Instant Status](https://github.com/instant-status/instant-status) API.

It can be used for reference and testing, but will need to be heavily augmented and modified depending on the type of application that your installation of Instant Status is supporting.

## Assumptions

This implementation assumes the use of AWS and Ubuntu Server, and will require certain configuration variables to be passed through to each server, from a genericized image, via User Data.

Any Git host can be used to host your copy of this deployment code.

Of course, it is also assumed that you are using Instant Status and have a working installation of it. Feel free to check out the [Instant Status deploy repo](https://github.com/instant-status/deploy#readme) for help with this.

## Setup

#### To prepare your copy of Fire and Fury:

1. Update all references to `https://instant-status.example.org` to the URL of your installation of Instant Status, also update the placeholder authorization.
1. Update all generic references (e.g. appuser) to match your chosen names.
1. Update the default global variables in `00-runner.sh`.
1. Update the credentials in `ssh/`.
1. Update `confs/` and `02-updateConfigs.sh` to have all of the required config files for your application, and to update them properly.
1. Finally, update `envs/`, `modules/`, and `03-runner.sh` to correctly represent your configuration and to correctly install, build, migrate and restart your application.

#### To prepare a server for use with Fire and Fury:

1. The `ubuntu` user must have the necessary keys to clone your copy of this deployment code, no write access is required.
1. All required packages and default configuration for your application should be installed.
1. A secondary `appuser` (or any other name) should be present and have permission to clone your application code, and have the necessary application directory structure present.
   > For example, a `releases/` directory with a `current` symlink to alias the latest release.
1. Copy the customized `checkin` and `startup` scripts:

   ```bash
   cat confs/__usr__sbin__faf-startup.sh | sudo tee /usr/sbin/faf-startup.sh
   cat confs/__usr__sbin__faf-checkin.sh | sudo tee /usr/sbin/faf-checkin.sh
   ```

1. Make required directories and files:

   ```bash
   sudo mkdir -p /var/log/faf && sudo chown ubuntu: /var/log/faf
   sudo mkdir -p /etc/faf && sudo touch /etc/faf/isPrimal.txt
   ```

1. Add the startup cronjob (run as `ubuntu` user):

   ```bash
   crontab <<'EOF'
   # PRIMAL FaF CRONJOB
   @reboot /bin/bash /usr/sbin/faf-startup.sh >> /var/log/faf/startup.log 2>&1
   EOF
   ```

1. After imaging this "base" server, spin it up and use JSON User Data to assign its Stack. For example:

   ```json
   {
     "stack": "stack-name-here"
   }
   ```

The corresponding Stack entry must also be created on Instant Status before the server starts.
