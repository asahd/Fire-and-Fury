#!/usr/bin/env bash
function output_log() {
  # $1 - Signifier / Category
  # $2 - Message to Log
  # $3 - Log File Location
  # echo "$1, $2, $3";
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >>"$3"
}
