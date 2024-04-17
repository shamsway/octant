
#!/bin/bash

# Modify to suit your server
HOME=/tmp/
LOGFILE="/tmp/conversions.log" 
BINDIR="/config/comskip"
# variables
TSVIDEO=$1    #Full path to recording
error=$2      #error from tvheadend recorder        "OK" if no error


filedate=`date '+%Y%m%d%H%M'`
filename=`basename $TSVIDEO`
filepath=`dirname $TSVIDEO`
taskfile="$HOME${filename%.*}-${filedate}.tsk" # Full path to task file

echo "\n\n$(date): *** Creating conversion task for ${TSVIDEO} ***"  | tee -a $LOGFILE

if [ ! -d "$HOME" ]; then
	mkdir "$HOME"
fi

if [ $error = "OK" ]; then
	echo "${TSVIDEO}" >> $taskfile
	# Kick off remuxer
	$BINDIR/tvhremux.sh &
else
	echo "$(date): TVH returned error for recording of ${TSVIDEO}"  | tee -a $LOGFILE
	exit 1
fi

exit 0

