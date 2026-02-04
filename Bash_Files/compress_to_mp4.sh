#!/bin/bash

# Note:
# Work in progress. This was able to compress jpeg images by 10x 
# TODOs:
# 1. Ability to extract frames from movie
# 2. Store metadata about frames so that we can extract meaningfully
# 3. Ability to use MVC filename output to store
# 4. Image quality difference between original jpeg and extracted jpeg
# 5. Compression in scenarios - store 1 component to 1 movie vs store 1 virtual camera into 1 movie
# 6. Ability to seek to a certain frame and extract

FRAME_RATE=10
START_FRAME=1
END_FRAME=10
IMAGE_FILENAME_PREFIX=Basler_acA2440-20gc__23986406__20230609_104738310_
MOVIE_FILENAME=test.mp4

ffmpeg -r $FRAME_RATE \
       -start_number $START_FRAME \
       -i ${IMAGE_FILENAME_PREFIX}%2d.jpeg \
       -vframes ${END_FRAME} \
       -vcodec libx265 \
       -crf 25  -pix_fmt yuv420p \
       ${MOVIE_FILENAME}


