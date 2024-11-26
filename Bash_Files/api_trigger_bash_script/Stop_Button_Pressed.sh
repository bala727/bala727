 #!/bin/bash
google-chrome "http://localhost:3001/api/mode?mode='productionmode'&stop=true&prev="stop"" &
n=$((RANDOM%90+30))
echo $n
sleep $n
killall  google-chrome 
echo "all done!"

