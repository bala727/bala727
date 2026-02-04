#!/bin/bash

PROCESS=compress_images     # can be compress_images or extract_frames
IMAGE_DIR=sac_repeatability_jpeg/jpeg
OUTPUT_FILE_PATH=`pwd`
IMAGE_NAME_PATTERN="*.jpeg"


# compress_images options
# 1. 1pass
# 2. 2pass
COMPRESS_OPTIONS="2pass"

# frame rate recommendations
FRAME_RATE=10

# encoder recommendations
# libx265 or libx264 or libvpx-vp9
ENCODER=libx264
if [[ "$ENCODER" == "libx264"  || "$ENCODER" == "libx265" ]]
then
    FILE_EXT=mp4
elif [ "$ENCODER" == "libvpx-vp9"  ]
then 
    FILE_EXT=webm
else 
    echo "ERROR: ENCODER not recognized"
    exit
fi
PRESET="-preset veryslow"


# CRF recommendations
# https://trac.ffmpeg.org/wiki/Encode/H.264
# https://trac.ffmpeg.org/wiki/Encode/VP9
# CRF 23 is the default for libx264, can keep 17
# CRF 28 is the default for libx265, can keep 20
# CRF 15-20 is the recommended range for libvpx-vp9, can keep 17
CRF=17

# bitrates recommendations
# https://developers.google.com/media/vp9/settings/vod/
# size @ fps | bitrate
# 1920x1080p @ 50,60	| 3000
# 2560x1440p @ 24,25,30	| 6000
# 3840x2160p @ 24,25,30	| 12000
# filesize (in Mb)= bitrate (in Mbps)* duration (in seconds )
# filesize (MB) = bitrate (Mbps) * duration (seconds) / 8
# below bitrate is in Mbps, so 12M = 12 Mbps
BITRATE_METHOD="auto" # can be manual or auto
BITRATE_REDUCER=0.5     # Used if auto
BITRATE=12M             # Used if manual

if [ "$COMPRESS_OPTIONS" == "1pass"  ]
then 
    OUTPUT_FILE_NAME=output_${COMPRESS_OPTIONS}_${FRAME_RATE}fps_${ENCODER}_crf${CRF}
elif [ "$COMPRESS_OPTIONS" == "2pass"  ]
then 
    OUTPUT_FILE_NAME=output_${COMPRESS_OPTIONS}_${FRAME_RATE}fps_${ENCODER}_crf${CRF}_${BITRATE}
else 
    echo "ERROR: COMPRESS_OPTIONS not recognized"
    exit
fi
LOGFILE=${OUTPUT_FILE_PATH}/${OUTPUT_FILE_NAME}.log
MOVIE_FILE=${OUTPUT_FILE_PATH}/${OUTPUT_FILE_NAME}.${FILE_EXT}
EXTRACT_PATH=ext_${OUTPUT_FILE_NAME}


if [ "$PROCESS" = "compress_images" ]; then

    du -h ${IMAGE_DIR} >> ${LOGFILE}
    pushd ${IMAGE_DIR}
    if [ "$COMPRESS_OPTIONS" == "1pass"  ]
    then 

        echo "============================================================================" | tee -a ${LOGFILE}
        if [ "$ENCODER" == "libx264"  ]
        then
            echo "----------------- ENCODING WITH libx264 ------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -framerate ${FRAME_RATE} \
                -pattern_type glob -i "${IMAGE_NAME_PATTERN}" \
                -c:v ${ENCODER} -crf ${CRF} ${PRESET} -tune stillimage \
                output_temp.mp4
            mv output_temp.mp4 ${MOVIE_FILE}
            du -h ${MOVIE_FILE} >> ${LOGFILE}
            ffmpeg -i ${MOVIE_FILE} >> ${LOGFILE} 2>&1
        elif [ "$ENCODER" == "libx265"  ]
        then
            echo "----------------- ENCODING WITH libx265 ------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -framerate ${FRAME_RATE} \
                -pattern_type glob -i "${IMAGE_NAME_PATTERN}" \
                -c:v ${ENCODER} -crf ${CRF} ${PRESET} \
                output_temp.mp4
            mv output_temp.mp4 ${MOVIE_FILE}
            du -h ${MOVIE_FILE} >> ${LOGFILE}
            ffmpeg -i ${MOVIE_FILE} >> ${LOGFILE} 2>&1
        elif [ "$ENCODER" == "libvpx-vp9"  ]
        then 
            echo "----------------- ENCODING WITH libvpx-vp9 ------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -framerate ${FRAME_RATE} \
                -pattern_type glob -i "${IMAGE_NAME_PATTERN}" \
                -c:v ${ENCODER} -crf ${CRF} -b:v 0 \
                output_temp.webm 
            mv output_temp.webm ${MOVIE_FILE}
            du -h ${MOVIE_FILE} >> ${LOGFILE}
            ffmpeg -i ${MOVIE_FILE} >> ${LOGFILE} 2>&1        
        else 
            echo "ERROR: ENCODER not recognized"
            exit
        fi
        echo "============================================================================" | tee -a ${LOGFILE}


    elif [ "$COMPRESS_OPTIONS" == "2pass"  ]
    then 
        echo "============================================================================" | tee -a ${LOGFILE}
        if [ "$ENCODER" == "libx264"  ]
        then
            echo "----------------- ENCODING WITH libx264 ------------------------------------" | tee -a ${LOGFILE}
            echo "----------------- INITIAL ENCODING PASS ------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -framerate ${FRAME_RATE} \
                -pattern_type glob -i "${IMAGE_NAME_PATTERN}" \
                -c:v ${ENCODER} -crf ${CRF} ${PRESET} -tune stillimage \
                output_temp.mp4
            echo "initial encoding pass" >> ${LOGFILE}
            du -h output_temp.mp4 >> ${LOGFILE}
            ffmpeg -i output_temp.mp4 >> ${LOGFILE} 2>&1

            # Get bitrate after initial pass and calculate new bitrate
            BITRATE_INITPASS=`ffmpeg -i output_temp.mp4 2>&1 | grep bitrate | awk '{print $6}'`
            if [ "$BITRATE_METHOD" == "auto"  ]
            then 
                BITRATE=`echo "$BITRATE_INITPASS * $BITRATE_REDUCER" | bc`
                # round off bitrate to nearest 1000
                BITRATE=`echo "($BITRATE + 500)/1000*1000" | bc`k
                echo "Using bitrate into auto mode: $BITRATE"
            fi

            echo "============================================================================" | tee -a ${LOGFILE}
            echo "----------------- 1st ENCODING PASS -------------------------------------"    | tee -a ${LOGFILE}
            ffmpeg -i output_temp.mp4 -c:v ${ENCODER} -crf ${CRF} -b:v ${BITRATE} -pass 1 -f mp4 output_temp_1stpass.mp4
            echo "============================================================================" | tee -a ${LOGFILE}
            echo "----------------- 2nd ENCODING PASS -------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -i output_temp.mp4 -c:v ${ENCODER} -crf ${CRF} -b:v ${BITRATE} -pass 2 ${MOVIE_FILE}
            echo "final encoding pass" >> ${LOGFILE}
            du -h ${MOVIE_FILE} >> ${LOGFILE}
            ffmpeg -i ${MOVIE_FILE} >> ${LOGFILE} 2>&1
            rm output_temp.mp4
            rm output_temp_1stpass.mp4
            rm ffmpeg2pass*
        elif [ "$ENCODER" == "libvpx-vp9"  ]
        then 
            echo "----------------- ENCODING WITH libvpx-vp9 ------------------------------------" | tee -a ${LOGFILE}
            echo "----------------- INITIAL ENCODING PASS ------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -framerate ${FRAME_RATE} \
                -pattern_type glob -i "${IMAGE_NAME_PATTERN}" \
                -c:v ${ENCODER} -crf ${CRF} -b:v 0 \
                output_temp.webm
            echo "initial encoding pass" >> ${LOGFILE}
            du -h output_temp.webm >> ${LOGFILE}
            ffmpeg -i output_temp.webm >> ${LOGFILE} 2>&1

            # Get bitrate after initial pass and calculate new bitrate
            BITRATE_INITPASS=`ffmpeg -i output_temp.webm 2>&1 | grep bitrate | awk '{print $6}'`
            if [ "$BITRATE_METHOD" == "auto"  ]
            then 
                BITRATE=`echo "$BITRATE_INITPASS * $BITRATE_REDUCER" | bc`
                # round off bitrate to nearest 1000
                BITRATE=`echo "($BITRATE + 500)/1000*1000" | bc`k
                echo "Using bitrate into auto mode: $BITRATE"
            fi

            echo "============================================================================" | tee -a ${LOGFILE}
            echo "----------------- 1st ENCODING PASS -------------------------------------"
            ffmpeg -i output_temp.webm -c:v ${ENCODER} -crf ${CRF} -b:v ${BITRATE} -pass 1 -f webm output_temp_1stpass.webm
            echo "============================================================================" | tee -a ${LOGFILE}
            echo "----------------- 2nd ENCODING PASS -------------------------------------" | tee -a ${LOGFILE}
            ffmpeg -i output_temp.webm -c:v ${ENCODER} -crf ${CRF} -b:v ${BITRATE} -pass 2 ${MOVIE_FILE}
            echo "final encoding pass" >> ${LOGFILE}
            du -h ${MOVIE_FILE} >> ${LOGFILE}
            ffmpeg -i ${MOVIE_FILE} >> ${LOGFILE} 2>&1
            rm output_temp.webm
            rm output_temp_1stpass.webm
            rm ffmpeg2pass*
        else 
            echo "ERROR: ENCODER not recognized"
            exit
        fi
    else 
        echo "ERROR: COMPRESS_OPTIONS not recognized"
        exit
    fi
    echo "============================================================================" | tee -a ${LOGFILE}
    popd

fi

if [ "$PROCESS" == "extract_frames" ]; then

    if [ -d "$EXTRACT_PATH" ]; then
        rm -rf ${EXTRACT_PATH}
    fi
    mkdir ${EXTRACT_PATH}
    pushd ${EXTRACT_PATH}
    ffmpeg -i ${MOVIE_FILE} output_%03d.jpeg
    popd

fi
