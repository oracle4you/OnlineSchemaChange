#!/bin/bash

db_user="root"
db_pass="root"
time=$(date +%Y-%m-%d-%H:%M:%S)

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start cleaning /var/log/mysql/error.log"
# Backup error log #
cp /var/log/mysql/error.log /var/log/mysql/error.log.$time

# Clean error log #
cat /dev/null > /var/log/mysql/error.log

master_host=$(mysql -u$db_user -p$db_pass -e"show slave status \G" 2>&1 | grep -v mysql: | grep Master_Host: | awk '{print $NF}')
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Get master address - $master_host"
if [ -z $master_host ]; then
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] This host is not slave"
  exit 0
else
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Stop slave"
  mysql -u $db_user -p$db_pass -e"stop slave" 2>&1 | grep -v mysql:

  position=$(cat /var/log/mysql/error.log | grep "replication stopped" | awk '{print $NF}')
  log_file=$(cat /var/log/mysql/error.log | grep "replication stopped" | cut -d" " -f 15)
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Replication stopped at log file $log_file and position $position"

  command1="stop slave; reset slave all; reset master"
  command2="change master to master_host='$master_host',master_user='$db_user',master_password='$db_pass',master_log_file=$log_file,master_log_pos=$position; start slave;"

  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Reset slave and re-establish replication"
  mysql -u$db_user -p$db_pass -e"$command1" 2>&1 | grep -v mysql:
  mysql -u$db_user -p$db_pass -e"$command2" 2>&1 | grep -v mysql:

  if [[ -n $master_host && -n $log_file && -n $position ]]; then
    io_run=$(mysql -u$db_user -p$db_pass -e"show slave status \G"  2>&1 | grep -v mysql: | grep Slave_IO_Running: | awk '{print $NF}')
    sql_run=$(mysql -u$db_user -p$db_pass -e"show slave status \G" 2>&1 | grep -v mysql: | grep Slave_SQL_Running: | awk '{print $NF}')
  fi

  if [[ $io_run == "Yes" && $sql_run == "Yes" ]]; then
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Replication errant transactions fixed"
  else
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Replication errant transactions not fixed"
  fi
fi
echo -e "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Script finished\n"
