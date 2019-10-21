#!/bin/bash

function die()
{
    printf '%s\n' "$1" >&2
    exit "${2-1}"
}

input_file="$1"
input_directory="$2"
output_directory="$3"
tmp_directory=/data/tmp
output_file="`echo "$input_file" | sed -E "s#^$input_directory(.+)\\.[a-z0-9]+\\$#$output_directory\\1.mp3#g"`"

directory="`dirname "$output_file"`"
if [ ! -d "$directory" ] ; then
    echo "New Directory: \"$directory\""
    mkdir -p "$directory" || die "Could not create directory \"$directory\"."
fi

transcode=false

if [ ! -f "$output_file" ] ; then
    echo "New MP3: \"$output_file\""
    transcode=true
elif [ "$input_file" -nt "$output_file" ] ; then
    echo "Input file is newer: \"$output_file\""
    transcode=true
fi

if [ "$transcode" = true ] ; then
    input_type="`file -b --mime-type "$input_file"`"
    case "$input_type" in
        audio/flac)
            tmp_file="$tmp_directory/`basename "$output_file"`"
            echo "Transcoding MP3..."
            ffmpeg -hide_banner -loglevel fatal -i "$input_file" -y -b:a 320k -qscale:a 2 -id3v2_version 3 -f mp3 "$tmp_file" || die "Failed to transcode to \"$tmp_file\"."
            mv -f "$tmp_file" "$output_file" || die "Could not move file to \"$output_file\"."
            ;;

        application/octet-stream)
            echo "Warning: Assuming \"$input_file\" is a MP3 file."
            ;&
        audio/mpeg)
            echo "Copying MP3..."
            cp -f "$input_file" "$output_file"
            ;;

        *)
            die "Unsupported input type $input_type (\"$input_file\")"
            ;;
    esac
fi
