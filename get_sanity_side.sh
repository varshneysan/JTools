#!/usr/bin/env sh

IND_QUEUE=`curl -s -k -m 60 http://in-mvlb14:8080/queue/api/json | python -m json.tool | grep '"why": "Waiting for next available executor on' | grep IND_CSIM | wc -l`
SV_QUEUE=`curl -s -k -m 60 http://in-mvlb14:8080/queue/api/json | python -m json.tool | grep '"why": "Waiting for next available executor on' | grep SV_CSIM | wc -l`

if [ $IND_QUEUE -ge $SV_QUEUE ]; then  
   echo SV
elif [ $IND_QUEUE -lt $SV_QUEUE ]; then  
   echo IND
fi
