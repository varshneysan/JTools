#!/usr/bin/env sh

IND_QUEUE=`curl -s -k -m 60 http://in-mvlb14:8080/queue/api/json | python -m json.tool | grep '"why": "Waiting for next available executor on' | grep IND_CSIM | wc -l`
SV_QUEUE=`curl -s -k -m 60 http://in-mvlb14:8080/queue/api/json | python -m json.tool | grep '"why": "Waiting for next available executor on' | grep SV_CSIM | wc -l`

if [ $IND_QUEUE -eq 0 ] && [ $SV_QUEUE -eq 0 ]; then
curl -s -k -m 60 http://in-mvlb14:8080/job/IND_Pre-iSubmit_CSIM_Sanity//api/json | python -m json.tool > IND_Pre-iSubmit_CSIM_Sanit.txt
curl -s -k -m 60 http://in-mvlb14:8080/job/SV_Pre-iSubmit_CSIM_Sanity/api/json | python -m json.tool > SV_Pre-iSubmit_CSIM_Sanit.txt

lastBuild_SV1=`grep -n "lastBuild" SV_Pre-iSubmit_CSIM_Sanit.txt | awk -F":" '{print $1}'`
lastBuild_IN1=`grep -n "lastBuild" IND_Pre-iSubmit_CSIM_Sanit.txt | awk -F":" '{print $1}'`

lastBuild_SV1=`expr $lastBuild_SV1 + 2`
lastBuild_IN1=`expr $lastBuild_IN1 + 2`

lastBuild_SV=`awk "NR==$lastBuild_SV1" SV_Pre-iSubmit_CSIM_Sanit.txt | cut -d":" -f2 | sed 's/[ ,]//g'`
lastBuild_IN=`awk "NR==$lastBuild_IN1" IND_Pre-iSubmit_CSIM_Sanit.txt | cut -d":" -f2 | sed 's/[ ,]//g'`

lastCompletedBuild_SV1=`grep -n "lastCompletedBuild" SV_Pre-iSubmit_CSIM_Sanit.txt | awk -F":" '{print $1}'`
lastCompletedBuild_IN1=`grep -n "lastCompletedBuild" IND_Pre-iSubmit_CSIM_Sanit.txt | awk -F":" '{print $1}'`

lastCompletedBuild_SV1=`expr $lastCompletedBuild_SV1 + 2`
lastCompletedBuild_IN1=`expr $lastCompletedBuild_IN1 + 2`

lastCompletedBuild_SV=`awk "NR==$lastCompletedBuild_SV1" SV_Pre-iSubmit_CSIM_Sanit.txt | cut -d":" -f2 | sed 's/[ ,]//g'`
lastCompletedBuild_IN=`awk "NR==$lastCompletedBuild_IN1" IND_Pre-iSubmit_CSIM_Sanit.txt | cut -d":" -f2 | sed 's/[ ,]//g'`

#echo "lastBuild_SV : $lastBuild_SV   lastCompletedBuild_SV=$lastCompletedBuild_SV"
#echo "lastBuild_IN=$lastBuild_IN  lastCompletedBuild_IN=$lastCompletedBuild_IN"

LoadOnSV=`expr $lastBuild_SV - $lastCompletedBuild_SV`
LOADOnIN=`expr $lastBuild_IN - $lastCompletedBuild_IN`

if [ $LOADOnIN -lt 4 ]; then
   if [[ `hostname` == "in-"* ]] || [[ `hostname` == "IN-"* ]]; then
      echo IND
      exit 0
   fi
fi
if [ $LoadOnSV -lt 4 ]; then
   if [[ `hostname` == "sv-"* ]] || [[ `hostname` == "SV-"* ]]; then
      echo SV  
      exit 0
   fi
fi
if [ $LoadOnSV -lt $LOADOnIN ]; then
   echo SV
   exit 0
elif [ $LoadOnSV -gt $LOADOnIN ]; then
   echo IND
   exit 0
elif [ $LoadOnSV -eq $LOADOnIN ]; then 
   if [[ `hostname` == "in-"* ]] || [[ `hostname` == "IN-"* ]]; then
      echo IND
      exit 0
   fi
   if [[ `hostname` == "sv-"* ]] || [[ `hostname` == "SV-"* ]]; then
      echo SV
      exit 0
   fi
fi
#echo "Load on SV is $LoadOnSV"
#echo "Load on IND is $LOADOnIN"

#echo "IND_QUEUE=$IND_QUEUE  SV_QUEUE=$SV_QUEUE"
else
if [ $IND_QUEUE -ge $SV_QUEUE ]; then  
   echo SV
elif [ $IND_QUEUE -lt $SV_QUEUE ]; then  
   echo IND
fi
