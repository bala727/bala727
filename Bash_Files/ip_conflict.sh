 #!/bin/bash 
# Script to check ipconflict
# Grep the word "Dup" and enable a pop up to show that there is ip conflict

sudo arp-scan -I wlp1s0 -l | grep DUP

if [[ $? == 0 ]]; then
  notify-send "IP-conflict detected"
fi
