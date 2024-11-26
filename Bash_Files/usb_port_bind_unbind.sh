#!/bin/bash

port="usb1" # replace '1' with actual bus number as shown by lsusb -t: {bus}-{port}(.{subport})

bind_usb() {
  echo "$1" >/sys/bus/usb/drivers/usb/bind
}

unbind_usb() {
  echo "$1" >/sys/bus/usb/drivers/usb/unbind
}

unbind_usb "$port"
# sleep 1 # enable delay here
bind_usb "$port"
