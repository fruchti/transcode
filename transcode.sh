#!/bin/bash

output_owner=
input_directory=/data/music

tmp_directory=/data/tmp
lock_file=/tmp/music-transcode.lock

function die()
{
    printf '%s\n' "$1" >&2
    exit "${2-1}"
}

if [ -f "$lock_file" ] ; then
    echo "Another instance is already running. Exiting."
    echo "If you are certain this is the only instance, you can delete the lock file $lockfile"
    exit
else
    touch "$lock_file" || die "Could not create lock file."
fi

if [ ! -d "$tmp_directory" ] ; then
    mkdir -p "$tmp_directory" || die "Could not create temporary directory \"$tmp_directory\"."
fi

function mp3()
{
    output_directory="/data/mp3"

    input_file="$1"
    output_file="`echo "$input_file" | sed -E "s#^$input_directory(.+)\\.[a-z0-9]+\\$#$output_directory\\1.mp3#g"`"

    directory="`dirname "$output_file"`"
    if [ ! -d "$directory" ] ; then
        echo "New Directory: \"$directory\""
        mkdir -p "$directory" || die "Could not create directory \"$directory\"."
        if [ ! "$output_owner" = "" ] ; then
            chown $output_owner "$directory" || die "Could not change permissions on \"$directory\"."
        fi
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

        if [ ! "$output_owner" = "" ] ; then
            chown $output_owner "$output_file" || die "Could not change permissions on \"$output_file\"."
        fi
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

function ogg()
{
    output_directory="/data/ogg"

    input_file="$1"
    output_file="`echo "$input_file" | sed -E "s#^$input_directory(.+)\\.[a-z0-9]+\\$#$output_directory\\1.ogg#g"`"

    directory="`dirname "$output_file"`"
    if [ ! -d "$directory" ] ; then
        echo "New Directory: \"$directory\""
        mkdir -p "$directory" || die "Could not create directory \"$directory\"."
        if [ ! "$output_owner" = "" ] ; then
            chown $output_owner "$directory" || die "Could not change permissions on \"$directory\"."
        fi
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
                ffmpeg -hide_banner -loglevel fatal -i "$input_file" -y -map a -qscale:a 6 -id3v2_version 3 -f ogg "$tmp_ogg" || die "Could not transcode to \"$tmp_ogg\"."

                echo "Adding OGG cover image..."
                metaflac --export-picture-to="$tmp_cover" "$input_file" && \
                    ogg_add_cover "$tmp_ogg" "$tmp_cover" || die "Could not add cover image to \"$tmp_ogg\"."

                mv -f "$tmp_ogg" "$output_file" || die "Could not move file to \"$output_file\"."
                ;;

            application/octet-stream)
                echo "Warning: Assuming \"$input_file\" is a MP3 file."
                ;&
            audio/mpeg)
                echo "Transcoding OGG..."
                ffmpeg -hide_banner -loglevel fatal -i "$input_file" -y -map a -qscale:a 6 -id3v2_version 3 -f ogg "$tmp_ogg" || die "Could not transcode to \"$tmp_ogg\"."

                echo "Adding OGG cover image..."
                exiftool -Picture -b "$input_file" > "$tmp_cover" && \
                    ogg_add_cover "$tmp_ogg" "$tmp_cover" || die "Could not add cover image to \"$tmp_ogg\"."

                mv -f "$tmp_ogg" "$output_file" || die "Could not move file to \"$output_file\"."
                ;;

            *)
                die "Unsupported input type $input_type (\"$input_file\")"
                ;;
        esac

        if [ ! "$output_owner" = "" ] ; then
            chown $output_owner "$output_file" || die "Could not change permissions on \"$output_file\"."
        fi
    fi
}

SAVEIFS=$IFS
IFS=`echo -ne "\n\b"`
for file in `find "$input_directory" -name '*.flac' -or -name '*.mp3' | sort`; do
    mp3 "$file"
    ogg "$file"
done

echo "Done Transcoding."
IFS=$SAVEIFS

rm -f "$lockfile"
