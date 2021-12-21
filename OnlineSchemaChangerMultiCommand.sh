#!/bin/bash
# Call from Jenkins #
MySQLHostRegion=$1
Port=$2
UserName=$3
Password=$4
Database=$5
AlterTable="$6"
AlterCommand=$(echo $7 | sed 's/##/ /g' | sed 's/~/ /g' | sed 's/"//g');
dryRun=$8
replicaLag=$9
array_EU="10.50.50.1,10.50.50.2,10.50.50.3" # Change IP's #
array_US="10.54.50.1,10.54.50.1,10.54.50.1" # Change IP's #
scriptDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
base_dir="/home/cpq"

# Links #
#cd /home/cpq
# wget https://downloads.percona.com/downloads/percona-toolkit/3.3.1/binary/debian/bionic/x86_64/percona-toolkit_3.3.1-1.bionic_amd64.deb
# missed packages: apt install libdbi-perl libdbd-mysql-perl libterm-readkey-perl libio-socket-ssl-perl
# dpkg -i percona-toolkit_3.3.1-1.bionic_amd64.deb

if [ -z $replicaLag ]; then 
  replicaLag=1; 
fi
 
replicaLagSec=$((replicaLag * 60 ))

# Find master by region EU US TEST #
if [ $MySQLHostRegion == "TEST" ]; then
  host="1.2.3.4" 
elif [ $MySQLHostRegion == "EU" ]; then
  for host in $(echo $array_EU | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$UserName -p$Password -h $host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      else
        host=""  
      fi
    done
elif [ $MySQLHostRegion == "US" ]; then
  for host in $(echo $array_US | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$UserName -p$Password -h $host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      else
        host=""  
      fi
      
    done
fi
MySQLHostIP=$host

# No master found on replication cluster #
if [ $MySQLHostIP == "" ]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Didn't find master on region $MySQLHostRegion. Process will stop."
  exit 1
fi

if [[ -n $replicaLagSec && $replicaLagSec -gt 0 ]]; then
#  replicationProperties="--check-slave-lag "
  replicationProperties=" --nocheck-replication-filters "
else
  replicationProperties=" --nocheck-replication-filters "
fi

if [ $dryRun == 'Yes' ]; then
  execute="--dry-run --print " #--drop-new-table"
  replicationProperties=""
else
  #execute="--execute --no-drop-old-table" # --no-drop-new-table"
  execute="--execute" # --no-drop-new-table"
  if [ $replicaLagSec -eq 0 ]; then
   replicaLagSec=60
  fi
fi

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Changes will be done on region : $MySQLHostRegion\n"
# Command Splitter #
AlterCommand=$(echo $AlterCommand | sed "s/';'/'|'/g" | sed "s/';;'/'||'/g" | sed "s/';;;'/'|||'/g") # Remove ';' incase DEFAULT ';' to not be caunted as multi-command delimiter 
loopIds=$(echo $AlterCommand | grep -o ";" | wc -l)
loop=1
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start splitting SQL command"
while [ $loop -le $(($loopIds+1)) ]
  do
    fixedCommand=$(echo $AlterCommand | cut -d ";" -f ${loop} | sed "s/ALTER TABLE//g" | sed "s/alter table//g" | sed "s|'|\"|g" | sed "s/\`//g");
    if [[ $Database == "empty" && $AlterTable == "empty" ]]; then
      
      Database=$(echo $fixedCommand | cut -d'.' -f 1)
      AlterTable=$(echo $fixedCommand | cut -d'.' -f 2 | awk '{print $1}')
      fixedCommand=$(echo $fixedCommand | sed "s/$Database.$AlterTable//g" | sed "s/|/;/g" | sed "s/||/;;/g" | sed "s/|||/;;;/g")
      

      # Constants #
      max_load="Threads_running=150"
      critical_load="Threads_running=1000"
      command="pt-online-schema-change --alter '$fixedCommand' D=$Database,t=$AlterTable --host $MySQLHostIP --user $UserName  --password $Password \
      --alter-foreign-keys-method auto  --max-load Threads_running=150 --critical-load Threads_running=300 $replicationProperties \
      --chunk-size 1000  --chunk-time 0.5 --chunk-size-limit 4.0  $execute"
      
      # Generate remote file and call if DB & table != "empty"#
      if [[ $Database != "" && $AlterTable != "" && $Database != "empty" && $AlterTable != "empty" ]]; then 
        echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Prompted command number [$loop] is: ALTER TABLE $fixedCommand\n"
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start changing objects on DB: $Database" 
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start changing table ${AlterTable} structure"
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Sent command to interpreter: $fixedCommand"

        echo $command > $base_dir/OnlineSchemaChangerRemote.txt
        mv $base_dir/OnlineSchemaChangerRemote.txt $base_dir/OnlineSchemaChangerRemote.sh
        sed -i '1s/^/#!\/bin\/bash\n /' $base_dir/OnlineSchemaChangerRemote.sh
        sudo chmod +x $scriptDIR/OnlineSchemaChangerRemote.sh
        sudo scp -o "StrictHostKeyChecking no" $base_dir/OnlineSchemaChangerRemote.sh root@$MySQLHostIP:$base_dir 

        # Execute remotely #
        ssh -o "StrictHostKeyChecking no" root@$MySQLHostIP $base_dir/OnlineSchemaChangerRemote.sh
        #eval $command
      fi

    fi
    
    Database="empty"
    AlterTable="empty"  
    ((loop++))

  done





