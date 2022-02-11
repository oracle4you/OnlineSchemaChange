#!/bin/bash
# Autor: Izzy Fayon
# Ver  : 1.10
# 1.0  : Initial script
# 1.1  : Added internal log rotator
# 1.3  : Add support for slack
# 1.4  : Add check of service mysql is up
# 1.5  : Send message when replica is back to normal - todo
# 1.6  : Check replication lags
# 1.7  : Separate condition sending to Slack & TelegramS
# 1.8  : Global variables configurated from external cnf file ==> cnf_file=$scriptDIR/$(basename $0 | sed -e 's/.sh/.cnf/g')
# 1.9  : Added check for master machines too
# 1.10 : Internal hostname resolver
# set -x
mysqlArray=(10.54.0.8 10.54.0.4 10.54.0.5 10.56.0.4 10.50.0.4 10.50.0.5 10.50.0.12 10.52.0.4)
mysqlResolved=(PROD-US1-DB06 PROD-US1-DB03 PROD-US1-DB04 PROD-US2-DB01 PROD-EU1-DB03 PROD-EU1-DB04 PROD-EU1-DB06 PROD-EU2-DB02)

maxscaleArray=(10.54.0.11 10.54.0.12 10.50.0.7 10.50.0.8)
maxscaleResolved=(PROD-US1-MAXSCALE01 PROD-US1-MAXSCALE02 PROD-EU1-MAXSCALE01 PROD-EU1-MAXSCALE02)

logFile="/var/log/MysqlOrchestrator.log"
# Log rotator every monday #
logReportRetention=15
DOW=$(date +%u) # day of week
WOY=$(date +%V) # week of year
HOD=$(date +%H) # hour of day
MOD=$(date +%M) # minute of day

if [[ $DOW = "1" && $HOD == "00" && $MOD == "00" ]]; then
  echo "$(date +%F" "%H:%M:%S) Today is Monday, day for log rotation"
  mv $logFile /var/log/MysqlOrchestrator.week."$WOY".log
  find /var/log/ -mtime +$logReportRetention -name "MysqlOrchestrator.week*" -exec rm {} \;
fi

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) Script started" >> $logFile

scriptDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

isUp=0
isNumber='^[0-9]+$'

# Internal configuration file #
cnf_file=$scriptDIR/$(basename $0 | sed -e 's/.sh/.cnf/g');
if [ ! -f $cnf_file ]; then
    touch $cnf_file
    echo "cnf_minSlaveLag=10"                   >> $cnf_file
    echo "cnf_maxSlaveLag=3600"                 >> $cnf_file
    echo "cnf_sendToTelegram=0"                 >> $cnf_file
    echo "cnf_sendToSlack=1"                    >> $cnf_file
    echo "cnf_MaxScaleCheck=1"                  >> $cnf_file
    echo "cnf_MySQLCheck=1"                     >> $cnf_file
    echo "cnf_MySQLSlaves=3"                    >> $cnf_file
    echo "cnf_MaxScalePpenPorts=8989"           >> $cnf_file
    echo "cnf_MySqlRouterCheck=1"               >> $cnf_file
    echo "cnf_MySqlRouterOpenPorts=3306"        >> $cnf_file
fi

# Functions #
sendToSlack() {
sURL="https://hooks.slack.com/services/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"
json="{\"text\": \"$1\"}"
runCURL="curl -s -X POST -H 'Content-type: application/json' --data  '$json' $sURL"
eval $runCURL > /dev/null
}

sendToTelegram() {
tToken="2030224278:AAGKxRubbjOoIHe93qC-Wq_FX3DbOxbyb0E"
tID=147547052
tURL="https://api.telegram.org/bot$tToken/sendMessage"
curl -s -X POST $tURL -d chat_id=$tID -d text="$1" > /dev/null
}

# Set / Get variables from config file #
minSlaveLag=$(cat $cnf_file | grep cnf_minSlaveLag | sed "s/cnf_minSlaveLag=//g");
maxSlaveLag=$(cat $cnf_file | grep cnf_maxSlaveLag | sed "s/cnf_maxSlaveLag=//g");
sendToTelegram=$(cat $cnf_file | grep cnf_sendToTelegram | sed "s/cnf_sendToTelegram=//g");
sendToSlack=$(cat $cnf_file | grep cnf_sendToSlack | sed "s/cnf_sendToSlack=//g");
checkMaxScale=$(cat $cnf_file | grep cnf_MaxScaleCheck | sed "s/cnf_MaxScaleCheck=//g");
checkMySQL=$(cat $cnf_file | grep cnf_MySQLCheck | sed "s/cnf_MySQLCheck=//g");
checkMySQLNumberOfSlaves=$(cat $cnf_file | grep cnf_MySQLSlaves | sed "s/cnf_MySQLSlaves=//g");
checkMySqlRouter=$(cat $cnf_file | grep cnf_MySqlRouterCheck | sed "s/cnf_MySqlRouterCheck=//g")
getMaxScaleOpenPorts=$(cat $cnf_file | grep cnf_MaxScalePpenPorts | sed "s/cnf_MaxScalePpenPorts=//g"); 
getMySqlRouterOpenPorts=$(cat $cnf_file | grep cnf_MySqlRouterOpenPorts | sed "s/cnf_MySqlRouterOpenPorts=//g"); 

scriptname=$(basename $0 | sed -e 's/.sh/.pid/g');
pidfile="/var/run/${scriptname}"

# In case process is stuck #
line_scriptFinished=$(cat -n $logFile | grep finished | tail -1 | awk '{print $1}');
a=`tail -n +1 $logFile | head -n $((line_scriptFinished-1+1)) | grep started | tail -1 | sed -e 's/Script started//'`;
b=$(cat $logFile | grep finished | tail -1 | sed -e 's/Script finished//');
uxA=$(date +%Y-%m-%d" "%H:%M:%S -d "$a");
uxB=$(date +%Y-%m-%d" "%H:%M:%S -d "$b");
uxAA=$(date -d "$uXA" +%s);
uxBB=$(date -d "$uXB" +%s);
secs=$((uxBB-uxAA));

if [[ -n $secs && $secs -eq 0 ]]; then
    rm -f $pidfile
fi

for i in "${!mysqlArray[@]}"
    do
        mysqlHost=${mysqlArray[$i]}
        mysqlHostResolved=${mysqlResolved[$i]}
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Checking mysql host $mysqlHostResolved IP:$mysqlHost"
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Checking mysql host $mysqlHostResolved IP:$mysqlHost" >> $logFile
        # Check if mysql is up
        if [ $checkMySQL -eq 1 ]; then
            nc -zv $mysqlHost 3306 2> /dev/null
            if [ $? -ne 0 ]; then
                message="$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] MySQL port on host $mysqlHostResolved IP:$mysqlHost not responding. MySQL service is down or in backup process."
                echo "$message" >> $logFile
                if [[ $sendToSlack -eq 1 || $i -eq 1 || $i -eq 5 ]]; then # for master US [i]=1 or master EU [i]=5 do aletr
                    sendToSlack "$message"
                fi
                if [ $sendToTelegram -eq 1 || $i -eq 1 || $i -eq 5 ]; then # for master US [i]=1 or master EU [i]=5 do aletrtail -f 
                    sendToTelegram "$message"
                fi    
                break 
            fi

            isMaster=$(mysql -N -s -u root -proot -h $mysqlHost -e"show slave hosts"  2>&1 | grep -v mysql: | wc -l);      
            if [[ $isMaster -eq 0 ]]; then # we have 3 slaves on every cluster
                Slave_IO_Running=$(mysql -u root -proot -h $mysqlHost -e"SHOW SLAVE STATUS \G" 2>&1 | grep -v mysql: | grep Slave_IO_Running: | awk '{print $2}')
                Slave_SQL_Running=$(mysql -u root -proot -h  $mysqlHost -e"SHOW SLAVE STATUS \G" 2>&1 | grep -v mysql: | grep Slave_SQL_Running: | awk '{print $2}')
                Seconds_Behind_Master=$(mysql -u root -proot -h  $mysqlHost -e"SHOW SLAVE STATUS \G" 2>&1 | grep -v mysql: | grep Seconds_Behind_Master: | awk '{print $2}')

                if [[ ( $Slave_IO_Running != "Yes" || $Slave_SQL_Running != "Yes" ) ]]; then
                    message="$(date +%Y-%m-%d" "%H:%M:%S) [WARNING] Check replica on $mysqlHostResolved IP:$mysqlHost. Replication Slave_SQL_Running=$Slave_IO_Running, Slave_SQL_Running=$Slave_SQL_Running."
                    echo "$message" >> $logFile
                    if [ $sendToSlack -eq 1 ]; then
                        sendToSlack "$message"
                    fi
                    if [ $sendToTelegram -eq 1 ]; then 
                        sendToTelegram "$message"
                    fi
                fi         

                if [[ $Slave_IO_Running == "Yes" && $Slave_SQL_Running == "Yes" && $Seconds_Behind_Master -gt $maxSlaveLag ]]; then
                    message="$(date +%Y-%m-%d" "%H:%M:%S) [WARNING] Replication lag of $Seconds_Behind_Master on $mysqlHostResolved IP:$mysqlHost."
                    echo "$message" >> $logFile
                    sendToSlack "$message"
                    sendToTelegram "$message"           
                elif [[ $Slave_IO_Running == "Yes" && $Slave_SQL_Running == "Yes"  && $Seconds_Behind_Master -eq $Seconds_Behind_Master ]]; then # send slave lag value on log file
                    message="$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Replication lag on $mysqlHostResolved IP:$mysqlHost is $Seconds_Behind_Master"
                    echo "$message" >> $logFile    
                fi

                 # Proactive change of innodb_flush_log_at_trx_commit #    
                if [[ $Slave_IO_Running == "Yes" && $Slave_SQL_Running == "Yes"  && $Seconds_Behind_Master -ge 100 ]]; then # send slave lag value on log file    
                    # Proactive change on replica lag #
                    currVal=$(mysql -N -s -u root -proot -h $mysqlHost -e"show variables where variable_name = 'innodb_flush_log_at_trx_commit'" 2>&1 | grep -v mysql: | awk '{print $2}')
                    if [ $currVal -ne 2 ]; then
                        command="set global innodb_flush_log_at_trx_commit = 2;" 
                        mysql -u root -proot -h $mysqlHost -e"$command" 2>&1 | grep -v mysql:
                    fi    
                elif [[ $Slave_IO_Running == "Yes" && $Slave_SQL_Running == "Yes"  && $Seconds_Behind_Master -le 10 ]]; then # send slave lag value on log file    
                    # Proactive change on replica lag #
                    currVal=$(mysql -N -s -u root -proot -h $mysqlHost -e"show variables where variable_name = 'innodb_flush_log_at_trx_commit'" 2>&1 | grep -v mysql: | awk '{print $2}')
                    if [ $currVal -ne 1 ]; then
                        command="set global innodb_flush_log_at_trx_commit = 1;" 
                        mysql -u root -proot -h $mysqlHost -e"$command" 2>&1 | grep -v mysql:
                    fi    
                fi    
            else
                if [ $isMaster -lt $checkMySQLNumberOfSlaves ]; then
                    message="$(date +%Y-%m-%d" "%H:%M:%S) [WARNING] Number of connected slaves to master $mysqlHostResolved IP:$mysqlHost is less than $checkMySQLNumberOfSlaves ($isMaster). Probably slave disconnected, stopped or in backup process."
                    echo "$message" >> $logFile
                    if [ $sendToSlack -eq 1 ]; then
                        sendToSlack "$message"
                    fi
                    if [ $sendToTelegram -eq 1 ]; then 
                        sendToTelegram "$message"
                    fi    
                fi    
    
            fi         
        fi    
    done

for i in "${!maxscaleArray[@]}"
    do
        
        maxscaleHost=${maxscaleArray[$i]}
        maxscaleHostResolved=${maxscaleResolved[$i]}
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Checking MaxScale/MySQL Router host $maxscaleHostResolved IP:$maxscaleHost" >> $logFile
        if [ $checkMySqlRouter -eq 1 ]; then
            nc -zv $maxscaleHost $getMySqlRouterOpenPorts 2> /dev/null
            if [ $? -ne 0 ]; then
                message="$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] MysqlRouter port on host $maxscaleHostResolved IP:$maxscaleHost not responding. MysqlRouter service is down."
                echo "$message" >> $logFile
                if [ $sendToSlack -eq 1 ]; then
                    sendToSlack "$message"
                fi
                if [ $sendToTelegram -eq 1 ]; then 
                    sendToTelegram "$message"
                fi    
                break               
            fi
        fi 

        if [ $checkMaxScale -eq 1 ]; then   
            nc -zv $maxscaleHost $getMaxScaleOpenPorts 2> /dev/null
            if [ $? -ne 0 ]; then
                message="$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] MaxScale port on host $maxscaleHostResolved IP:$maxscaleHost not responding. MaxScale service is down."
                echo "$(date +%Y-%m-%d" "%H:%M:%S) $message" >> $logFile
                if [ $sendToSlack -eq 1 ]; then
                    sendToSlack "$message"
                fi
                if [ $sendToTelegram -eq 1 ]; then 
                    sendToTelegram "$message"
                fi    
                break               
            fi
        fi

    done

#message="[INFO] Last check at $(date +%Y-%m-%d" "%H:%M:%S) UTC"
#if [ $sendToSlack -eq 1 ]; then
#    sendToSlack "$message"
#fi
  
# Debug #
# if [ $sendToSlack -eq 1 ]; then
#     sendToSlack "$message"
# fi
# if [ $sendToTelegram -eq 1 ]; then 
#     sendToTelegram "$message"
# fi    

echo "$(date +%Y-%m-%d" "%H:%M:%S) Script finished" >> $logFile
