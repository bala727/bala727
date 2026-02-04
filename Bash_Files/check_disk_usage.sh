#!/bin/bash


INSTALL=false
USE_GDU=false 

if [ "$INSTALL" == "true" ]
then 
    curl -L https://github.com/dundee/gdu/releases/latest/download/gdu_linux_amd64.tgz | tar xz
    chmod +x gdu_linux_amd64
    sudo mv gdu_linux_amd64 /usr/bin/gdu
fi 

if [ "$USE_GDU" == "true" ]
then 
    gdu
else 
    echo "Copy-paste the following command in relevant directory: "
    echo "sudo du -hsx */ | sort -rh | head -n 40"
fi