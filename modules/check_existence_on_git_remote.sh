#!/usr/bin/env bash
function check_existence_on_git_remote() {
  # $1 - Remote URL
  # $2 - Branch / Tag
  result=1
  if [[ $(sudo su - appuser -c "git ls-remote --heads $1 $2 | wc -l") -eq 1 ]] || [[ $(sudo su - appuser -c "git ls-remote --tags $1 $2 | wc -l") -eq 1 ]]; then
    result=0
  fi

  return $result
}
