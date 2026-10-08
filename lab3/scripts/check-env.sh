#!/usr/bin/env bash
# check-env.sh -- print the facts a Lab 3 run depends on.
set -euo pipefail
 
echo "terraform: $(terraform version | head -1)"
echo "region:    ${AWS_REGION:-unset}"
 
if [ -z "${AWS_REGION:-}" ; then
  echo "AWS_REGION is not set"
  exit 1
fi
 
echo "environment looks sane"
