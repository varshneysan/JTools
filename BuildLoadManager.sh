#!/usr/bin/env sh

rm -f parameter.txt IN-MVLB* sv-mvbld* parameter.txt
CLs=""
brs=""
brtype=""
counter=0
mailer=""

rm -f tmpfile 
touch tmpfile

#OUT=`/usr/bin/perl osubmit_utility.pl --fetchChangelist | tr ',' ' '`
#OUT="1819237://swdepot/main/:NONDEV NONE NONE"
#OUT="1819237://swdepot/2dParty/:NONDEV NONE://swdepot/main/:NONDEV "
#OUT="1819237://swdepot/2dParty/:NONDEV 777777://swdepot/main/:NONDEV 1819237://swdepot/2dParty/:NONDEV  NONE" 
OUT="777777://swdepot/main/:NONDEV 1819237://swdepot/2dParty/:NONDEV  NONE" 
#OUT="777777://swdepot/main/:NONDEV 1820534://swdepot/cx-main/:NONDEV NONE"
if [ "${OUT}" == "None" ] || [ -z "${OUT}" ] ; then
    echo "No Changelist to proceed...Existing."
    exit 0
fi

for out in $OUT
do
   br=""
   cl=`echo $out | awk -F":" '{print $1}'`
   type=`echo $out | awk -F":" '{print $3}'`

   if [ ! "${type}" ]; then break; fi
   if [ "${type}" == "NONDEV" ]; then
      br=`echo $out | awk -F":" '{print $2}' | sed 's/\/\/swdepot//' | awk -F"/" '{print $2}'`
      IsDev=No
   else
      br=`echo $out | awk -F":" '{print $2}' | sed 's/\/\/swdepot//' | awk -F"/" '{print $3}'`
      IsDev=Yes
   fi

#   if [ $cl == "NONE" ] && [ ! ${br} ]; then
#      break
#   fi
   
   if [ "${br}" == "2dParty" ]; then
          cl_2dparty=$cl
   elif [ "${cl}" == "NONE" ] && [ $cl_2dparty ]; then
          cl=$cl_2dparty
          Branch=$br
          brs="$brs $br"
          if [ ${CLs} ]; then CLs="${CLs},$cl"; else CLs="$cl"; fi

   elif [ "${br}" != "2dParty" ] && [ $br ] && [ "${cl}" != "${cl_2dparty}" ]; then
        Branch=$br
        brtype="$type"
        brs="$brs $br"
        #[ ${cl_2dparty} ] && CLs="${CLs},${cl_2dparty}" && cl_2dparty=""
	[ ${cl_2dparty} ] && if [ ${CLs} ]; then CLs="${CLs},${cl_2dparty}" ; else CLs="$cl_2dparty" && cl_2dparty=""; fi
        if [ ${CLs} ]; then CLs="${CLs},$cl"; else CLs="$cl"; fi
   fi

done
if [ "${cl_2dparty}" ]; then CLs="${CLs},${cl_2dparty}"; fi
   
num_br=`echo $brs | tr ' ' '\n' | uniq | wc -l`
if [ $num_br -gt 1 ] || [ -z ${Branch} ] ; then
   echo "Can not handle this set of CLs or development branch not found"
   exit 1
fi

echo "ChangeList=${CLs}"
echo "Branch=${Branch}"
echo "IsDev=${IsDev}"


#echo "mailer=svarshney@infinera.com,mkrishan@infinera.com" >> ${BuildBox}
#perl osubmit_utility.pl --getClOwner --p4cl 
exit 
binfo="${CLs} ==> ${BuildBox}"

echo "binfo=${binfo}"

for cl in `echo ${CLs} | tr "," " "`
do
   perl  osubmit_utility.pl --setclstate -changelist ${cl} --state INPROGRESS
   owner=`perl osubmit_utility.pl --getClOwner --p4cl ${cl}`
   if [ ${owner} == "None" ]; then
      echo "Error: Looks like the CLs ${cl} has been deleted from the db."
      exit 1
   fi
   if grep "${owner}" tmpfile > /dev/null
   then
    echo "Already in the mailer list"
   else
    mailer="${mailer},${owner}"
   	echo ${owner} >> tmpfile 
   fi
   
done

mailer=`echo $mailer | sed 's/^,//'`
echo "mailer=${mailer}" >> ${BuildBox}

perl osubmit_utility.pl --lockUnLockBuildBox --server ${BuildBox} --status YES
