#!/usr/bin/env sh

action=$1
action_side=$2
debug=$3
file=Sanity_Load.txt
sanity_lock="$HOME/.Sanity_Load.lock"
print_error=0

[ -z ${action} ] && print_error=1
[[ $action != "LM"  &&  $action != "CUTLM" ]] && print_error=1
[[ $action == "CUTLM"  &&  -z ${action_side} ]]  && print_error=1 

[ ${debug} ] && echo "
Warning : Debug for this tool is enabled.
          Please make sure debug should be disable in live env.
"

[ $print_error -eq 1 ] && echo "
Error : LM/CUTLM and SITE SV/IND required to proceed 

Usage :
    -- To Get the Sanity Side
       $0 LM  -- OR -- $0 LM

    -- To GiveBack the Sanity Side
       $0 CUTLM SV -- OR -- $0 CUTLM IND
" && exit 1

while true
do
   [ -f $sanity_lock ] && sleep 2
   [ ! -f $sanity_lock ] && touch $sanity_lock && break
done

[ ! -f $file ] && echo "SV:2" > $file && echo "IND:1" >> $file && echo SV && rm -f $sanity_lock && exit 0

[ -f $file ] && \
while read line
do
    sanity_side=`echo $line | awk -F":" '{print $1}'`
    sanity_load=`echo $line | awk -F":" '{print $2}'`
    [ $sanity_side == "SV" ] && SV_LOAD=$sanity_load
    [ $sanity_side == "IND" ] && IND_LOAD=$sanity_load
done < $file

#echo "SV_LOAD=$SV_LOAD"
#echo "IND_LOAD=$IND_LOAD"
if [ $action == "LM" ]; then 
   [ $SV_LOAD -eq $IND_LOAD ] && SV_LOAD_ADD=`expr $SV_LOAD + 1` && sed -i "s/SV:$SV_LOAD/SV:$SV_LOAD_ADD/" $file && echo SV
   [ $SV_LOAD -gt $IND_LOAD ] && IND_LOAD_ADD=`expr $IND_LOAD + 1` && sed -i "s/IND:$IND_LOAD/IND:$IND_LOAD_ADD/" $file && echo IND
elif [ $action == "CUTLM" ]; then
   [ $action_side == "SV" ] && SV_LOAD_ADD=`expr $SV_LOAD - 1` && sed -i "s/SV:$SV_LOAD/SV:$SV_LOAD_ADD/" $file 
   [ $action_side == "IND" ] && IND_LOAD_ADD=`expr $IND_LOAD - 1` && sed -i "s/IND:$IND_LOAD/IND:$IND_LOAD_ADD/" $file 
fi
[ $debug ] && cat $file
rm -f $sanity_lock
