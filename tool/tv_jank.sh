#!/bin/bash
# Measures how smooth the TV home feels: starts One Launcher TV, drives a fixed D-pad route and prints
# frame stats from SurfaceFlinger timestats (Flutter draws into a SurfaceView, so `dumpsys gfxinfo`
# sees nothing). Then 10 s idle (should draw ~0 frames). Run only when the TV is idle (never during playback).
# Usage: TV=<ip:port> tool/tv_jank.sh [label]
set -e
ADB=~/Library/Android/sdk/platform-tools/adb
S=${TV:?set TV=ip:port}
P=com.kirtanya.one_launcher.tv
L=${1:-run}
tv(){ "$ADB" -s "$S" "$@"; }
if tv shell dumpsys media_session | grep -q "state=PLAYING"; then echo "TV is playing something: not touching it"; exit 1; fi
# Frames of our Flutter surface: count, fps, p50/p90/p99 and share over 33 ms of the time between presents.
stats(){ tv shell dumpsys SurfaceFlinger --timestats -dump | awk -v l="$1" '
  /^layerName = SurfaceView\[com.kirtanya.one_launcher/ {on=1; next}
  /^layerName = / {on=0}
  on && /^totalFrames/ {tf=$3}
  on && /^averageFPS/ {fps=$3}
  on && /present2present histogram/ {getline; n=split($0,a," "); for(i=1;i<=n;i++){split(a[i],kv,"="); ms=kv[1]+0; c=kv[2]+0; if(c>0){k++; M[k]=ms; C[k]=c; t+=c; if(ms>33) slow+=c}}; on=0}
  END { if(!t){print l": no frames"; exit}
    s=0; for(i=1;i<=k;i++){s+=C[i]; if(!p50 && s>=t*.5)p50=M[i]; if(!p90 && s>=t*.9)p90=M[i]; if(!p99 && s>=t*.99)p99=M[i]}
    printf "%s: frames=%d fps=%.1f p50=%dms p90=%dms p99=%dms over33ms=%.0f%%\n", l, tf, fps, p50, p90, p99, 100*slow/t }'; }
tv shell am force-stop $P
tv shell am start -W -n $P/com.kirtanya.one_launcher.TvActivity | grep -E "TotalTime" | sed "s/^/$L cold start: /" || true
sleep 8
tv shell dumpsys SurfaceFlinger --timestats -enable -clear >/dev/null
keys(){ local k=$1 n=$2 d=${3:-0.35}; for _ in $(seq "$n"); do tv shell input keyevent "$k"; sleep "$d"; done; }
# Route: along the first row, down through the rows, back up, then fast (held-key speed) moves.
keys DPAD_RIGHT 6; keys DPAD_LEFT 6; keys DPAD_DOWN 4; keys DPAD_RIGHT 8; keys DPAD_DOWN 3; keys DPAD_UP 7
keys DPAD_RIGHT 10 0.12; keys DPAD_DOWN 4 0.15; keys DPAD_UP 4 0.15; keys DPAD_LEFT 10 0.12
sleep 2
stats "$L route"
tv shell dumpsys SurfaceFlinger --timestats -clear >/dev/null; sleep 10
stats "$L idle 10s"
tv shell dumpsys SurfaceFlinger --timestats -disable >/dev/null
tv shell dumpsys meminfo $P | grep -m1 "TOTAL PSS" | sed "s/^ */$L mem: /" || true
