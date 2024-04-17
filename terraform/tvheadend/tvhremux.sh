
#!/bin/bash
# FFMPEG_OPTIONS:
#     - '-hide_banner'
#     - '-loglevel error'
#     - '-vsync 0'
#     - '-hwaccel auto'
#     - '-i {input_filename}'
#     - '-c:v hevc_nvenc'
#     - '-qmin:v 22'
#     - '-qmax:v 30'
#     - '-rc-lookahead 8' 
#     - '-weighted_pred 1'

# Modify to suit your server
HOME="/tmp"
TVH_USER="convert"
TVH_PASS="trevnoc"
TVH_IP="127.0.0.1" 
TVH_PORT="9981" 
API_ENDPOINT="/api/dvr/entry/filemoved" 
BIN_CURL="/usr/bin/curl" 
LOGFILE="/tmp/conversions.log" 

# remux $1 to $2 & notify TVH
remux()
{
SRC=$1
DST=$2
if [ -e $SRC ] && [ ! -e $DST ] ; then
	echo -e "$(date): Starting conversion of \n${SRC} to \n${DST}" | tee -a $LOGFILE
	ffmpeg -fflags +genpts -analyzeduration 15M -hide_banner -loglevel error -vsync 0 -hwaccel auto -c:v hevc_nvenc -qmin:v 22 -qmax:v 30 -rc-lookahead 8 -weighted_pred 1 -i $SRC -c copy $DST
	if [ $? -eq 0 -a -e $DST ] ; then
		echo -e "$(date): Notifying Tvheadend of the change from\n$(basename $SRC) to \n$(basename $DST)" | tee -a $LOGFILE
		SUCCESS=0
		REPEAT=0
		while [ "$REPEAT" -lt 5 ]; do
			if ${BIN_CURL} -s "http://${TVH_USER}:${TVH_PASS}@${TVH_IP}:${TVH_PORT}${API_ENDPOINT}" \
				--data-urlencode "src=${SRC}" \
				--data-urlencode "dst=${DST}" > /dev/null; then
				echo -e "$(date): Notification successful!" | tee -a $LOGFILE
		    		SUCCESS=1
    				break
		  	else
				let REPEAT++
    				echo -e "$(date): Notification attempt $REPEAT failed ..." | tee -a $LOGFILE
				sleep 30
			fi
		done
		if [ "$SUCCESS" -gt 0 ]; then
			echo -e "$(date): All done, deleting ${SRC}" | tee -a $LOGFILE
			rm $SRC
		else
			echo -e "$(date): Could not notify TVH about the change - deleting ${DST} and leaving original file" | tee -a $LOGFILE
			rm -f $DST
		fi
	else
		echo "$(date): Conversion task of ${SRC} FAILED" | tee -a $LOGFILE
		if [  -e $DST ] ; then
			rm $DST
		fi
	fi
else
	if [ ! -e $SRC ] ; then
		echo -e "$(date): ${SRC} not found" | tee -a $LOGFILE
	fi
	if [ -e $DST ] ; then
		echo -e "$(date): ${DST} already exits" | tee -a $LOGFILE
	fi
fi
}

# Do conversion of $1, handling multiple files if -n.ts suffix is present
convert()
{
FTYPE=mkv
INFILE=$1
NAME=$(basename $INFILE)
FILENAME=${NAME%.ts}
PATHNAME=$(dirname $INFILE)
VID=$PATHNAME/$FILENAME.$FTYPE
TERM=${FILENAME:(-2)}
TERM2=${TERM:0:1}
if [ "$TERM2" = "-" ] ; then
	SUFFIX=${TERM:1}
else
	SUFFIX=""
fi
# If we have a suffix of say, -3 - then we need to account for:
# PROG-NAME-YYYY-MM-DDHH-MM-3.xyz
# PROG-NAME-YYYY-MM-DDHH-MM-2.xyz
# PROG-NAME-YYYY-MM-DDHH-MM-1.xyz
# PROG-NAME-YYYY-MM-DDHH-MM.xyz
if [ -n "$SUFFIX" ] ; then
	FNAME=${FILENAME%%??}
	while [ $SUFFIX -gt 0 ]
	do
		remux $PATHNAME/$FNAME-$SUFFIX.ts $PATHNAME/$FNAME-$SUFFIX.$FTYPE
		let SUFFIX--
	done
	remux $PATHNAME/$FNAME.ts $PATHNAME/$FNAME.$FTYPE
else
	remux $INFILE $VID
fi
}

if [ $# -gt 0 ]; then
 	# Commandline usage - convert each parameter [full path to file].
	for FILE in $@ ; do
		convert $FILE
	done
else
	# Postprocessing - read all task files & convert
	#
	# Random delay of up to 10 sec to ensure when two
	# instances are started simultaneously, only 1 will continue
	#
	LOCK=/var/lock/$(basename $0).lock
	RANDOM=$$
	DELAY=$(expr $RANDOM % 10)
	echo Waiting for $DELAY sec
	sleep $DELAY
	if [ -e $LOCK ]; then
		echo exiting as $LOCK exists
		exit 0
	fi
	touch $LOCK

	# Check for new taskfiles
	for TASK in $HOME/*.tsk; do
		if [ -f "$TASK" ] ; then
        		# Get the first line from the file in $TSVIDEO
			TSVIDEO=""
			while IFS='' read -r TSVIDEO || [[ -n "$TSVIDEO" ]]; do
				break
			done < $TASK

			rm -f $TASK
			if [ -n "$TSVIDEO" -a -f "$TSVIDEO" ]; then
				echo -e "$(date): Conversion file found: ${TSVIDEO}" | tee -a $LOGFILE
				convert $TSVIDEO
			fi
		fi
	done
	rm -f $LOCK
fi

