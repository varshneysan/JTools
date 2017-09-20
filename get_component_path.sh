#!/usr/bin/env sh

ToolPath=`dirname $0`
CLs=$1
tool=ShowApplicableBranches
TMPFILE=$(mktemp)
Flist="final_list.txt"
cpaths=""

p4 -u bangbuild -P BD09EFDFEEA034D237ADE61B256006A9 print //swdepot/2dParty/etc2.0/component_root_paths.sh | tail -n +2 > $TMPFILE
source $TMPFILE
rm $TMPFILE

touch ${Flist} ${TMPFILE}

for cl in `echo $CLs | tr ',' ' '`
do
        p4 -u bangbuild -P BD09EFDFEEA034D237ADE61B256006A9 describe $cl > tfile.txt
        snum=`cat tfile.txt | grep -n "Affected files ..." | cut -d ":" -f 1`
        fcount=`cat tfile.txt | grep "//swdepot/2dParty" | cut -d"#" -f 1 | wc -l`
        if [ $fcount -ne 0 ]; then
		`${ToolPath}/${tool} $cl | awk '{print $1 "  " $2}' | uniq >> ${TMPFILE}`
        fi
done

rm -f tfile.txt
cat ${TMPFILE} | uniq > ${Flist}

while read line
do
#COMPONENT_ROOT_PATHS
cname=`echo $line | cut -d " " -f 1`
cvers=`echo $line | cut -d " " -f 2`
tpath="//swdepot/2dParty/${COMPONENT_ROOT_PATHS[$cname]}/${cvers}/"
cpaths="$cpaths $tpath" 
done < ${Flist}
rm -f ${TMPFILE} ${Flist} 
echo $cpaths
