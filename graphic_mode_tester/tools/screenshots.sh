#!/bin/bash
# Runs GMTEST.COM in DOSBox (CGA, EGA, Hercules) on a virtual X display and
# saves one screenshot per mode to out/. Needs dosbox, Xvfb, xdotool, imagemagick.
set -e
cd "$(dirname "$0")/.."
BIN=$PWD/bin
OUT=$PWD/out
mkdir -p "$OUT"

shoot() {
    local machine=$1 count=$2 conf window
    conf=$(mktemp)
    cat > "$conf" <<C
[sdl]
output=surface
[dosbox]
machine=$machine
[render]
scaler=none
aspect=false
[autoexec]
mount c $BIN
c:
GMTEST.COM
exit
C
    Xvfb :9 -screen 0 1024x768x24 >/dev/null 2>&1 & local xvfb=$!
    sleep 1
    DISPLAY=:9 SDL_AUDIODRIVER=dummy dosbox -conf "$conf" >/dev/null 2>&1 & local dosbox=$!
    sleep 4
    for i in $(seq 1 "$count"); do
        window=$(DISPLAY=:9 xdotool search --class dosbox | tail -1)
        DISPLAY=:9 import -window "$window" "$OUT/$machine-$i.png"
        DISPLAY=:9 xdotool key --window "$window" space
        sleep 2
    done
    DISPLAY=:9 xdotool key --window "$window" Escape
    sleep 1
    kill "$dosbox" "$xvfb" 2>/dev/null || true
    wait 2>/dev/null || true
    rm -f "$conf"
}

shoot cga 7
shoot ega 10
shoot hercules 1
