#!/usr/bin/env sh

Branch=$2
Host=`hostname`
Host=`echo $host | sed 's/\.infinera.com//g'`
Client=CLV_${Branch}_${Host}

if [ -z ${Branch} ]; then
   echo "Branch Name is missing"
   exit 1
fi

p4 clients | grep $Client > /dev/null
if [ $? -eq 0 ]; then
   echo "Client $Client is already here."
else
   if [[ $host =~ in-* ]];
      RootFolder="/home/bangbuild/CLVERI/workspace/${Client}/"
   elif [[ $host =~ sv-* ]];
      RootFolder="/home/bangbuild/CLVERI/workspace/${Client}/"
   fi
   p4 -d $RootFolder -t ${Branch}_template -o ${Client} | p4 client -i
   if [ $? -ne 0 ];
      echo "Client ${Client} has not been created."
      exit 1
   fi
fi