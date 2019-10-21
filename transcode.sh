#!/bin/bash

input_directory=/data/music

tmp_directory=/data/tmp/transcode
lock_file=/tmp/music-transcode.lock

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function die()
{
    printf '%s\n' "$1" >&2
    exit "${2-1}"
}

if [ -f "$lock_file" ] ; then
    echo "Another instance is already running. Exiting."
    echo "If you are certain this is the only instance, you can delete the lock file $lockfile"
    exit 2
else
    touch "$lock_file" || die "Could not create lock file."
fi

function cleanup()
{
    rm -f "$lock_file"
    rm -rf "$tmp_directory"
}

trap cleanup EXIT SIGTERM SIGKILL

if [ ! -d "$tmp_directory" ] ; then
    mkdir -p "$tmp_directory" || die "Could not create temporary directory \"$tmp_directory\"."
fi

SAVEIFS=$IFS
IFS=`echo -ne "\n\b"`
for file in `find "$input_directory" -name '*.flac' -or -name '*.mp3' | sort`; do
    bash ${__dir}/transcode_to_mp3.sh "$file" "$input_directory" "/data/mp3" || break
    bash ${__dir}/transcode_to_ogg.sh "$file" "$input_directory" "/data/ogg" || break
done

echo "Done Transcoding."
IFS=$SAVEIFS
