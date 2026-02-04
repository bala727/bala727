#!/bin/bash

function usage() {

    echo -e "This converts all images in the current folder into jpeg. Images are saved in jpeg folder within current dir"
    echo -e "Please specify the image type to convert from (eg: png, bmp, tiff)"
    echo -e "Example: "
    echo -e "`basename $0` png"

}


if [ "$#" -ne 1 ]
then 
    usage 
    exit 
fi


IMAGE_TYPE=$1
CURR_DIR=`pwd`

echo "Currently in $CURR_DIR"

mkdir -p jpeg

for IMG_TO_CONVERT in `ls *.${IMAGE_TYPE}`
do 
    
    filename=$(basename -- "$IMG_TO_CONVERT")
    extension="${filename##*.}"
    filename="${filename%.*}"

    IMG_CONVERTED=${filename}.jpeg
    echo "Converting $IMG_TO_CONVERT to $IMG_CONVERTED" 
    
    convert ${IMG_TO_CONVERT} ${IMG_CONVERTED}
    mv ${IMG_CONVERTED} jpeg/

done 
