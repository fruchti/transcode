#!/bin/bash

input_directory=/data/music

tmp_directory=/data/tmp/transcode
lock_file=/tmp/music-transcode.lock

function transcode_to_mp3()
{
    input_file="$1"
    output_directory="$2"
    output_file="`echo "$input_file" | sed -E "s#^$input_directory(.+)\\.[a-z0-9]+\\$#$output_directory\\1.mp3#g"`"

    directory="`dirname "$output_file"`"
    if [ ! -d "$directory" ] ; then
        echo "New Directory: \"$directory\""
        mkdir -p "$directory" || { echo "Could not create directory \"$directory\"." ; return 1 ; }
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
                ffmpeg -hide_banner -loglevel fatal -i "$input_file" -y -b:a 320k -qscale:a 2 -id3v2_version 3 -f mp3 "$tmp_file" || { echo "Failed to transcode to \"$tmp_file\"." ; return 1 ; }
                mv -f "$tmp_file" "$output_file" || { echo "Could not move file to \"$output_file\"." ; return 1 ; }
                ;;

            application/octet-stream)
                echo "Warning: Assuming \"$input_file\" is a MP3 file."
                ;&
            audio/mpeg)
                echo "Copying MP3..."
                cp -f "$input_file" "$output_file"
                ;;

            *)
                echo "Unsupported input type $input_type (\"$input_file\")"
                return 1
                ;;
        esac
    fi
}

function ogg_add_cover()
{
    ogg_file="$1"
    cover_file="$2"

    tmp_metafile="$tmp_directory/metadata"
    tmp_mdimg="$tmp_directory/image-with-header"

    cover_mime_type="`file -b --mime-type "$cover_file"`"

    description=""
    vorbiscomment --list --raw "$ogg_file" > "$tmp_metafile" && \
        sed -i -e '/^metadata_block_picture/d' "$tmp_metafile" && \
        echo -n "" > "$tmp_mdimg" && \
        printf "0: %.8x" 3 | xxd -r -g0 >> "$tmp_mdimg" && \
        printf "0: %.8x" $(echo -n "$cover_mime_type" | wc -c) | xxd -r -g0 >> "$tmp_mdimg" && \
        echo -n "$cover_mime_type" >> "$tmp_mdimg" && \
        printf "0: %.8x" $(echo -n "$description" | wc -c) | xxd -r -g0 >> "$tmp_mdimg" && \
        echo -n "$description" >> "$tmp_mdimg" && \
        printf "0: %.8x" 0 | xxd -r -g0  >> "$tmp_mdimg" && \
        printf "0: %.8x" 0 | xxd -r -g0  >> "$tmp_mdimg" && \
        printf "0: %.8x" 0 | xxd -r -g0  >> "$tmp_mdimg" && \
        printf "0: %.8x" 0 | xxd -r -g0  >> "$tmp_mdimg" && \
        printf "0: %.8x" $(wc -c "$cover_file" | cut --delimiter=' ' --fields=1) | xxd -r -g0 >> "$tmp_mdimg" && \
        cat "$tmp_cover" >> "$tmp_mdimg" && \
        echo "metadata_block_picture=$(base64 --wrap=0 < "$tmp_mdimg")" >> "$tmp_metafile" && \
        vorbiscomment --write --raw --commentfile "$tmp_metafile" "$ogg_file" && \
        rm "$tmp_metafile" "$tmp_mdimg"
}

function transcode_to_ogg()
{
    input_file="$1"
    output_directory="$2"
    output_file="`echo "$input_file" | sed -E "s#^$input_directory(.+)\\.[a-z0-9]+\\$#$output_directory\\1.ogg#g"`"

    directory="`dirname "$output_file"`"
    if [ ! -d "$directory" ] ; then
        echo "New Directory: \"$directory\""
        mkdir -p "$directory" || { echo "Could not create directory \"$directory\"." ; return 1 ; }
    fi

    transcode=false

    if [ ! -f "$output_file" ] ; then
        echo "New OGG: \"$output_file\""
        transcode=true
    elif [ "$input_file" -nt "$output_file" ] ; then
        echo "Input file is newer: \"$output_file\""
        transcode=true
    fi

    if [ "$transcode" = true ] ; then
        input_type="`file -b --mime-type "$input_file"`"

        tmp_ogg="$tmp_directory/`basename "$output_file"`"
        tmp_cover="$tmp_directory/cover"

        case "$input_type" in
            audio/flac)
                echo "Transcoding OGG..."
                ffmpeg -hide_banner -loglevel fatal -i "$input_file" -y -map a -qscale:a 6 -id3v2_version 3 -f ogg "$tmp_ogg" || { echo "Could not transcode to \"$tmp_ogg\"." ; return 1 ; }

                echo "Adding OGG cover image..."
                metaflac --export-picture-to="$tmp_cover" "$input_file" && \
                    ogg_add_cover "$tmp_ogg" "$tmp_cover" || { echo "Could not add cover image to \"$tmp_ogg\"." ; return 1 ; }

                mv -f "$tmp_ogg" "$output_file" || { echo "Could not move file to \"$output_file\"." ; return 1 ; }
                ;;

            application/octet-stream)
                echo "Warning: Assuming \"$input_file\" is a MP3 file."
                ;&
            audio/mpeg)
                echo "Transcoding OGG..."
                ffmpeg -hide_banner -loglevel fatal -i "$input_file" -y -map a -qscale:a 6 -id3v2_version 3 -f ogg "$tmp_ogg" || die "Could not transcode to \"$tmp_ogg\"."

                echo "Adding OGG cover image..."
                exiftool -Picture -b "$input_file" > "$tmp_cover" && \
                    ogg_add_cover "$tmp_ogg" "$tmp_cover" || { echo "Could not add cover image to \"$tmp_ogg\"." ; return 1 ; }

                mv -f "$tmp_ogg" "$output_file" || { echo "Could not move file to \"$output_file\"." ; return 1 ; }
                ;;

            *)
                echo "Unsupported input type $input_type (\"$input_file\")"
                return 1
                ;;
        esac
    fi
}

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
    transcode_to_mp3 "$file" "/data/mp3" || break
    transcode_to_ogg "$file" "/data/ogg" || break
done

echo "Done Transcoding."
IFS=$SAVEIFS
