#!/bin/zsh
# Watch Bandje during a long recording: memory (as Activity Monitor shows it), CPU, the size of
# the recording being written and free disk space, every N seconds (default 30).
# Writes a CSV to ~/Music/Bandje/selftest/memory-<date>.csv and prints each line. Stop with Ctrl-C.
#
#   scripts/dev/watch-memory.sh [seconds]
#
# Expect: memory flat while recording (audio streams through a fixed ring buffer to disk), the
# .caf growing by about 22 MB per minute (48 kHz stereo float32, 1.3 GB per hour; after stopping it
# becomes an .m4a of about 55 MB per hour), and a temporary rise while transcribing afterwards.
interval=${1:-30}
dir="$HOME/Music/Bandje"
out="$dir/selftest/memory-$(date +%Y-%m-%d_%H-%M).csv"
mkdir -p "$dir/selftest"
echo "time,pid,memory,cpu,recording_file,recording_mb,free_disk_gb" > "$out"
echo "Writing $out (every ${interval}s, Ctrl-C to stop)"
peak=0
trap 'echo; echo "Peak memory: ${peak} MB. CSV: $out"; exit 0' INT
while true; do
  pid=$(pgrep -f "Bandje.app/Contents/MacOS/Bandje" | head -1)
  now=$(date +%H:%M:%S)
  if [[ -z $pid ]]; then
    echo "$now,,,,,," >> "$out"; echo "$now  Bandje is not running"
  else
    read -r _ mem cpu <<< "$(top -l 1 -pid $pid -stats pid,mem,cpu | tail -1)"
    # Newest recording file (.caf while recording, .m4a after), in a recording folder or directly in $dir.
    files=( "$dir"/*.caf(N) "$dir"/*/*.caf(N) "$dir"/*/*.m4a(N) "$dir"/*.m4a(N) )
    files=( ${files:#$dir/selftest/*} )
    file=""; (( ${#files} )) && file=$(ls -t "${files[@]}" | head -1)
    mb=""; [[ -n $file ]] && mb=$(( $(stat -f %z "$file") / 1048576 ))
    free=$(df -g "$dir" | awk 'NR==2 {print $4}')
    echo "$now,$pid,$mem,$cpu,${file:t},$mb,$free" >> "$out"
    printf "%s  memory %-6s cpu %-5s  %s %s MB  free %s GB\n" "$now" "$mem" "$cpu" "${file:t}" "$mb" "$free"
    value=${mem%[MKG]*}; unit=${mem: -1}
    [[ $unit == G ]] && value=$(( ${value%.*} * 1024 ))
    [[ $unit == K ]] && value=0
    (( ${value%.*} > peak )) && peak=${value%.*}
  fi
  sleep "$interval"
done
