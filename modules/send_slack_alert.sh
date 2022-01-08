#!/usr/bin/env bash
function send_slack_alert() {
  # $1 - Token
  # $2 - JSON Body
  curl -X POST -H 'Content-type: application/json' --data "$2" "https://hooks.slack.com/services/$1"
}
