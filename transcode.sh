#!/bin/sh

output_owner=fruchti:data
lockfile=/tmp/music-transcode.lock

if [ -f "$lockfile" ] ; then
    echo "Another instance is already running. Exiting."
    echo "If you are certain this is the only instance, you can delete the lock file $lockfile"
    exit
else
    touch "$lockfile"
fi

tmpdir=/data/tmp

if [ ! -d "$tmpdir" ] ; then
    mkdir -p "$tmpdir"
fi

SAVEIFS=$IFS
IFS=`echo -ne "\n\b"`
for flac in `find /data/music -name '*.flac' | sort`; do
    # MP3

    mp3=`echo "$flac" | sed -e 's/^\/data\/music/\/data\/mp3/' -e 's/.flac$/.mp3/'`
    tmpmp3="$tmpdir/`basename "$mp3"`"
    mp3dir=`dirname "$mp3"`
    transcodemp3=false

    if [ ! -d "$mp3dir" ] ; then
        echo "New Directory: \"$mp3dir\""
        mkdir -p "$mp3dir"
    fi

    if [ ! -f "$mp3" ] ; then
        echo "New MP3: \"$mp3\""
        transcodemp3=true
    elif [ "$flac" -nt "$mp3" ] ; then
        echo "FLAC is newer: \"$mp3\""
        transcodemp3=true
    fi

    if [ "$transcodemp3" = true ] ; then
        echo "Transcoding MP3..."
        # ffmpeg -i "$flac" -y -b:a 320k -qscale:a 2 -f mp3 "$mp3"
        ffmpeg -hide_banner -loglevel fatal -i "$flac" -y -b:a 320k -qscale:a 2 -id3v2_version 3 -f mp3 "$tmpmp3" && \
            mv -f "$tmpmp3" "$mp3" && \
            chown $output_owner "$mp3"
        echo -e "Done.\n"
    fi

    # OGG

    ogg=`echo "$flac" | sed -e 's/^\/data\/music/\/data\/ogg/' -e 's/.flac$/.ogg/'`
    tmpogg="$tmpdir/`basename "$ogg"`"
    tmpcover="$tmpdir/cover"
    tmpmetafile="$tmpdir/metadata"
    tmpmdimg="$tmpdir/image-with-header"
    oggdir=`dirname "$ogg"`
    transcodeogg=false

    if [ ! -d "$oggdir" ] ; then
        echo "New Directory: \"$oggdir\""
        mkdir -p "$oggdir"
    fi

    if [ ! -f "$ogg" ] ; then
        echo "New OGG: \"$ogg\""
        transcodeogg=true
    elif [ "$flac" -nt "$ogg" ] ; then
        echo "FLAC is newer: \"$ogg\""
        transcodeogg=true
    fi

    if [ "$transcodeogg" = true ] ; then
        echo "Transcoding OGG..."

        ffmpeg -hide_banner -loglevel fatal -i "$flac" -y -map a -qscale:a 6 -id3v2_version 3 -f ogg "$tmpogg" && \
            mv -f "$tmpogg" "$ogg" && \
            metaflac --export-picture-to="$tmpcover" "$flac" && \
            covermimetype="image/png" && \
            covermimetype="`file -b --mime-type "$tmpcover"`" && \
            description="" && \
            vorbiscomment --list --raw "$ogg" > "$tmpmetafile" && \
            sed -i -e '/^metadata_block_picture/d' "$tmpmetafile" && \
            echo -n "" > "$tmpmdimg" && \
            printf "0: %.8x" 3 | xxd -r -g0 >> "$tmpmdimg" && \
            printf "0: %.8x" $(echo -n "$covermimetype" | wc -c) | xxd -r -g0 >> "$tmpmdimg" && \
            echo -n "$covermimetype" >> "$tmpmdimg" && \
            printf "0: %.8x" $(echo -n "$description" | wc -c) | xxd -r -g0 >> "$tmpmdimg" && \
            echo -n "$description" >> "$tmpmdimg" && \
            printf "0: %.8x" 0 | xxd -r -g0  >> "$tmpmdimg" && \
            printf "0: %.8x" 0 | xxd -r -g0  >> "$tmpmdimg" && \
            printf "0: %.8x" 0 | xxd -r -g0  >> "$tmpmdimg" && \
            printf "0: %.8x" 0 | xxd -r -g0  >> "$tmpmdimg" && \
            printf "0: %.8x" $(wc -c "$tmpcover" | cut --delimiter=' ' --fields=1) | xxd -r -g0 >> "$tmpmdimg" && \
            cat "$tmpcover" >> "$tmpmdimg" && \
            echo "metadata_block_picture=$(base64 --wrap=0 < "$tmpmdimg")" >> "$tmpmetafile" && \
            vorbiscomment --write --raw --commentfile "$tmpmetafile" "$ogg" && \
            chown $output_owner "$ogg"

        echo -e "Done.\n"
    fi
done

echo "Done Transcoding."
IFS=$SAVEIFS

rm -f "$lockfile"
