#!/usr/bin/env sh 

Branch=$1
Host=`hostname | sed 's/\.infinera\.com//g'`
Client=CLV_${Branch}_${Host}
templatefile=templates
tfile=""
bfound=0
alias p4="p4 -u bangbuild -P BD09EFDFEEA034D237ADE61B256006A9"
echo "Info: Host Name is $Host"

if [ ! -f $templatefile ]; then
   echo "Error: Template file list missing"
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
       echo "Error: Could not found build template for branch $Branch. Please make sure $templatefile is updated"
       exit 1
    else
       echo "Info: Template is $tfile"
    fi
}

function cleanup_client {
   export P4CLIENT=$Client
   echo "Cleaning up client $Client"
   p4 -c $Client revert //...  
   rm -rf ${RootFolder}
   p4 client -d $Client
}

if [ -z ${Branch} ]; then
   echo "Error: Branch Name is missing"
   exit 1
fi

echo "Info: Client Name is $Client"
get_template

p4 clients | grep ${Client} | awk '{print $2}' > tempfile.txt
if [ ! -z tempfile.txt ]; then
   while read line
   do
      if [ "$line" = "$Client" ]; then
         bfound=1
      fi
   done < tempfile.txt
fi
rm -f tempfile.txt

if [[ $Host =~ IN-* ]] || [[ $Host =~ in-* ]]; then
      RootFolder="/home/bangbuild/CLVERI/workspace/"
elif [[ $Host =~ sv-* ]]; then
      RootFolder="/bld_home/bangbuild/CLVERI/workspace/"
fi


if [ $bfound -eq 1 ]; then
   echo "Info: Client $Client is already here."
   cleanup_client
fi

   if [ ! -d $RootFolder ]; then
      mkdir -p $RootFolder
   fi

   cd $RootFolder
   echo "Executng p4 client -t $tfile -o ${Client} | p4 client -i" 
   p4 client -t $tfile -o ${Client} | p4 client -i

   if [ $? -ne 0 ]; then
      echo "Error: Client ${Client} has not been created. Looks like there are some issue."
      exit 1
   else
      echo "Client $Client has been created" 
   fi
exit 0
