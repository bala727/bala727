 #!/bin/bash
google-chrome "http://localhost:3001/api/mode?user=qa1&mode=%27productionmode%27&productname=HiFiBiscuits&batchid=Bala&quantity=10000&start=true&prev=%22stop%22" &
n=$((RANDOM%90+30))
echo $n
sleep $n
killall  google-chrome 
echo "all done!"

