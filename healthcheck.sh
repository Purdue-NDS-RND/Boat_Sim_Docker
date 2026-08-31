#!/usr/bin/env bash
set -Eeuo pipefail

pgrep -f '[g]z sim' >/dev/null
pgrep -f '[a]rdurover' >/dev/null
pgrep -f '[m]avproxy.py' >/dev/null

clock_topic=$(timeout 3 gz topic -l 2>/dev/null | sed -n '/^\/world\/.*\/clock$/p' | head -n 1)
[[ -n $clock_topic ]]
timeout 4 gz topic -e -t "$clock_topic" -n 1 2>/dev/null | grep -q 'sim'
