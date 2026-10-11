#!/usr/bin/env bash
# Scripted gestures on the phone (no taps; swipes start on wallpaper or card edges) while a
# PERF_LOG build logs frame times. Usage: tool/perf_bench.sh  → prints the PERF lines.
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB logcat -c
s() { $ADB shell input swipe "$@"; sleep 0.6; }
for i in 1 2 3; do s 900 450 150 450 180; done      # carousel left ×3
for i in 1 2 3; do s 150 450 900 450 180; done      # carousel right ×3
s 540 950 540 150 160                                 # sheet up (fling)
for i in 1 2 3; do s 1050 1900 1050 700 140; done   # list fling up ×3
for i in 1 2 3; do s 1050 800 1050 2000 140; done   # list fling down ×3
s 540 330 540 1900 160                                # sheet down
sleep 2.5
$ADB logcat -d | grep -o "PERF.*"
