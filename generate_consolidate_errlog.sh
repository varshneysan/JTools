#!/usr/bin/env sh

function GenerateConsolidateErrorLogFile() {
error_pattern=( "error:"\
                "fatal" \
                "Error 1" \
                "Error 2" \
                "collect2: : ld returned 1 exit status" \
                "ld: cannot find" \
                "missing separator (did you mean TAB instead of 8 spaces)" \
                ": Command not found" \
                "invalid file suffix, cannot compile" \
                "No such file or directory compilation terminated" \
                "not found, and is required by PKG" \
                "Unable to open file" \
                "undefined reference to" \
                "No space left on device" \
                "pigz: abort: write  on" \
                "fork: Resource temporarily unavailable" \
                "javac: command not found" \
                "doesn't match the directory path in Makefile" \
                "file not recognized: File truncated" \
                "file changed as we read it" \
                "compilation terminated" \
                "File in wrong format" \
                "cp: cannot stat" \
                "references nonexistent")

all_error_pattern=( "${error_pattern[@]}")
consolidated_error_file="$ws_root_path/src_ne/parallelbuild_consolidated_err.log"
echo "workspace root path is $ws_root_path"
echo "consolidated error file is $consolidated_error_file"
find $ws_root_path/src_ne -name "parallel*.log" | while read logfile;
do
    for pattern in "${all_error_pattern[@]}"
    do
        echo "Searching pattern $pattern in $logfile"
        cat ${logfile} | grep -C1 "${pattern}" >> $consolidated_error_file
    done
done

}

ws_root_path=$1
if [ -f $consolidated_error_file ]
then
    rm -rf $consolidated_error_file
fi
GenerateConsolidateErrorLogFile $ws_root_path
exit 0
