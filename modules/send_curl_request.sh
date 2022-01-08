#!/usr/bin/env bash
function statusAPI_GET() {
  curl -s -X GET \
    https://instant-status.example.org/api/v2/"$1" \
    -H 'Authorization: Bearer eyJ' \
    -H 'Content-Type: application/json' \
    --data-raw "$2"
}

function statusAPI_POST() {
  curl -s -X POST \
    https://instant-status.example.org/api/v2/"$1" \
    -H 'Authorization: Bearer eyJ' \
    -H 'Content-Type: application/json' \
    --data-raw "$2"
}
