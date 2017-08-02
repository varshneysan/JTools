#!/usr/bin/env sh

Branch=$2
Host=`hostname`
Host=`echo $host | sed 's/\.infinera.com//g'`
Client=CLV_${Branch}_${Host}
templatefile=templates
tfile=""
bfound=0

if [ ! -f $templatefile ]; then
   echo "Template file list missing"
   exit 1
fi

function get_template {
   while read line 
   do 
      b=`echo $line | awk '{print $1}'` 
      t=`echo $line | awk '{print $2}'` 
      if [ "$b" == "$Branch" ]; then    
        tfile=$t
      fi 
    done < ${templatefile}
    if [ ! $tfile ]; then
       echo "Could not found build template for branch $Branch. Please make sure $templatefile is updated"
       exit 1
    fi
}

if [ -z ${Branch} ]; then
   echo "Branch Name is missing"
   exit 1
fi

get_template

while read line
do
 if [ "$line" = "$Branch" ]; then
    bfound=1
 fi
done< <(p4 clients | grep $Branch | awk '{print $2}')

if [ $bfound -eq 1 ]; then
   echo "Client $Client is already here."
else
   if [[ $host =~ in-* ]];
      RootFolder="/home/bangbuild/CLVERI/workspace/${Client}/"
   elif [[ $host =~ sv-* ]];
      RootFolder="/home/bangbuild/CLVERI/workspace/${Client}/"
   fi
   p4 -d $RootFolder -t $tfile -o ${Client} | p4 client -i
   if [ $? -ne 0 ];
      echo "Client ${Client} has not been created."
      exit 1
   fi
fi
