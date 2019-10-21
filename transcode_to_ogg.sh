#!/bin/bash

function die()
{
    printf '%s\n' "$1" >&2
    exit "${2-1}"
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

input_file="$1"
input_directory="$2"
output_directory="$3"
tmp_directory=/data/tmp
output_file="`echo "$input_file" | sed -E "s#^$input_directory(.+)\\.[a-z0-9]+\\$#$output_directory\\1.ogg#g"`"

directory="`dirname "$output_file"`"
if [ ! -d "$directory" ] ; then
    echo "New Directory: \"$directory\""
    mkdir -p "$directory" || die "Could not create directory \"$directory\"."
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
fi
