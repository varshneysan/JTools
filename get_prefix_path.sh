#!/usr/bin/env sh

function longest_common_prefix()
{
    declare -a names
    declare -a parts
    declare i=0

    names=("$@")
    name="$1"
    while x=$(dirname "$name"); [ "$x" != "/" ]
    do
        parts[$i]="$x"
        i=$(($i + 1))
        name="$x"
    done

    for prefix in "${parts[@]}" /
    do
        for name in "${names[@]}"
        do
            if [ "${name#$prefix/}" = "${name}" ]
            then continue 2
            fi
        done
        #echo "$prefix"
	all_files="$all_files $prefix" 
        break
    done
}

CLs=$1
all_files=""
for cl in `echo $CLs | tr ',' ' '`
do
	p4 -u bangbuild -P BD09EFDFEEA034D237ADE61B256006A9 describe $cl > tfile.txt
	snum=`cat tfile.txt | grep -n "Affected files ..." | cut -d ":" -f 1`
	fcount=`cat tfile.txt | grep "//swdepot/2dParty" | cut -d"#" -f 1 | wc -l`
	if [ $fcount -ne 0 ]; then
		files=`cat tfile.txt | grep "//swdepot/2dParty" | cut -d"#" -f 1  | cut -d " " -f 2 | tr '\n' ' '`
		longest_common_prefix $files
	fi
done
echo $all_files
