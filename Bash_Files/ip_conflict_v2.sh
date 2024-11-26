#!/bin/bash
subnet="192.168.5"
for i in $(seq 1 254); do
    ip="${subnet}.${i}"
    ping -c 1 -W 1 $ip > /dev/null
    if [ $? -eq 0 ]; then
        echo "IP address ${ip} is in use."
    fi
done

