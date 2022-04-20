#! /bin/bash -x
# MySQL replication-failover  monitor for maxscale
#
#
#set +x
d=$(date)
for i in "$@"
do
	case $i in
	    initiator=*)
	    INITIATOR="${i#*=}"
	    shift # past argument=value
	    ;;
	    event=*)
	    EVENT="${i#*=}"
	    shift # past argument=value
	    ;;
	    live_nodes=*)
	    LIVE_NODES="${i#*=}"
	    shift # past argument=value
	    ;;
	    slave_list=*)
	    SLAVE_LIST="${i#*=}"
	    shift # past argument=value
	    ;;
	    *)
	exit 1
	    ;;
esac
done
set -x
SELECTED_SLAVE=$( echo $SLAVE_LIST | cut -d',' -f 1 )
SLAVE_HOST=$( echo $SELECTED_SLAVE | cut -d':' -f 1 )
SLAVE_PORT=$( echo $SELECTED_SLAVE | cut -d':' -f 2 )
SERVER_DOWN=$(echo ${INITIATOR} |cut -d':' -f 1)
USER=root
PASSWORD=root
MASTER1="10.54.0.8"
MASTER2="10.54.0.4"
ALIVE_SLAVE1="10.54.0.5"
ALIVE_SLAVE2="10.56.0.4"
FLOAT_HOST_NAME="PROD-US-FLOATING"

secs=0  # Increase/Decrease time of connection retry

endTime=$(( $(date +%s) + secs ))
failoverLogPath="/var/log/maxscale/failover.log"
echo "[${d}] [from: ${INITIATOR}] - event: ${EVENT}" >> $failoverLogPath

SIMPLE_SERVER_DOWN=$( echo ${INITIATOR} |cut -d':' -f 1 | cut -d '[' -f 2 | cut -d ']' -f 1);
SIMPLE_SLAVE_HOST=$( echo $SELECTED_SLAVE | cut -d':' -f 1 | cut -d '[' -f 2 | cut -d ']' -f 1);
OLD_MASTER=$(echo $SIMPLE_SERVER_DOWN | xargs);

# if event is server doan run failover

# wait $sec to check is stil down
if [ ${EVENT} = "master_down" ];then

	while [[ $(date +%s) -lt $endTime && ${EVENT} = "master_down" ]]; do # try to reconnect only for master_down event
	  	reconnect=$((reconnect+1))
	  	echo "$(date +%Y-%m-%d" "%H:%M:%S) Trying to connect to down master $SIMPLE_SERVER_DOWN for $reconnect time" >>  $failoverLogPath

	  	conn_master=$(mysql -u ${USER} -p$PASSWORD -h $SIMPLE_SERVER_DOWN -N -e"select 1;");
	  	sleep 1
	  	if [ $conn_master -eq 1 ]; then
			echo "$(date +%Y-%m-%d" "%H:%M:%S) Restored connection to $SIMPLE_SERVER_DOWN... terminating event ${EVENT}. No changes needed" >>  $failoverLogPath
			exit 1
	  	fi
	done

	echo "[${d}] [from: ${INITIATOR}] - event: ${EVENT}, Master is down, failover started" >>  $failoverLogPath
	echo "serverdown : ${SERVER_DOWN}"  >>  $failoverLogPath
	if [ $SIMPLE_SERVER_DOWN = ${MASTER1} ]; then
		NEW_MASTER=${MASTER2}
	else
    	NEW_MASTER=${MASTER1}
	fi
	echo "find new master: ${NEW_MASTER} disable server: ${SERVER_DOWN}"  >>  $failoverLogPath

	#reset slave status on new master
	sql="stop slave;reset slave all;reset master;SET GLOBAL read_only = 0;"
	echo $sql | mysql -u ${USER} -p${PASSWORD} -h ${NEW_MASTER} 2>&1 | grep -v mysql:

	# change mysql03 to be slave on new master #
	sql="stop slave;reset slave all;reset master;change master to MASTER_PORT=3306,MASTER_HOST='${NEW_MASTER}',MASTER_USER='${USER}',MASTER_PASSWORD='${PASSWORD}',MASTER_AUTO_POSITION=1;start slave;SET GLOBAL read_only = 1;"
	echo $sql | mysql -u ${USER} -p${PASSWORD} -h ${ALIVE_SLAVE1} 2>&1 | grep -v mysql:

	# change mysql04 to be slave on new master
	sql="stop slave;reset slave all;reset master;change master to MASTER_PORT=3306,MASTER_HOST='${NEW_MASTER}',MASTER_USER='root',MASTER_PASSWORD='root',MASTER_AUTO_POSITION=1;start slave;SET GLOBAL read_only = 1;"
	echo $sql | mysql -u ${USER} -p${PASSWORD} -h ${ALIVE_SLAVE2} 2>&1 | grep -v mysql:

	echo "[${d}] [from: ${INITIATOR}] - event: ${EVENT}, Done failover" >>  $failoverLogPath
    #maxctrl -u admin -p mariadb set server ${SERVER_DOWN}  maintenance
        
    # Rearrange conf file of mysqlrouter #
    if [ $SIMPLE_SERVER_DOWN == $OLD_MASTER ]; then
      	sudo sed -i "s/${OLD_MASTER} ${FLOAT_HOST_NAME}/${NEW_MASTER} ${FLOAT_HOST_NAME}/g" /etc/hosts
    fi

    sudo service mysqlrouter stop
    sleep .5
    sudo service mysqlrouter start

elif [ ${EVENT} = "slave_down" ];then
	echo "[${d}] [from: ${INITIATOR}] - event: ${EVENT}, Slave is down, no action needed" >>  $failoverLogPath
fi

##send mail on event###
#DATE=`date`
#MAIL_TO="izzy@gmail.com"
#ssmtp $MAIL_TO  << EOFMAIL
#To: $MAIL_TO
#From: izzy@gmail.com
#Subject: critical MySQl  EVENT from `hostname`

#local time :$DATE
#MySQL EVENT from `hostname`:
#${EVENT}
#EOFMAIL
