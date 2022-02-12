#!/bin/bash
MySQLHostRegion=$1
Port=$2
UserName=$3
Password=$4
Database=$5
AlterTable="$6"
AlterCommand=$(echo $7 | sed 's/##/ /g' | sed 's/~/ /g' | sed 's/"//g');
dryRun=$8
replicaLag=$9
array_EU="1.1.1.1,2.2.2.2,3.3.3.3"
array_US="11.11.11.11 22.22.22.22 33.33.33.33"
scriptDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
base_dir="/home/cpq"

# Links #
#cd /home/cpq
#wget https://downloads.percona.com/downloads/percona-toolkit/3.3.1/binary/debian/bionic/x86_64/percona-toolkit_3.3.1-1.bionic_amd64.deb
# missed packages: apt install libdbi-perl libdbd-mysql-perl libterm-readkey-perl libio-socket-ssl-perl
# dpkg -i percona-toolkit_3.3.1-1.bionic_amd64.deb

if [[ -z $replicaLag || $replicaLag -eq 0 ]]; then 
  replicaLag=1; 
fi
 
replicaLagSec=$((replicaLag * 60 ))

# Find master by region EU US TEST #
if [ $MySQLHostRegion == "TEST" ]; then
  host="10.70.1.9"
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
if [ $MySQLHostIP == ""]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Didn't find master on region $MySQLHostRegion. Process will stop."
  exit 1
fi

if [[ -n $replicaLagSec && $replicaLagSec -gt 0 ]]; then
#  replicationProperties="--check-slave-lag h=izzy-ubuntu-03,u=izzy,p=domain --max-lag  $replicaLagSec"
  replicationProperties=" --nocheck-replication-filters --max-lag  $replicaLagSec"
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


# Case of call script with empty DB & table from jenkins #
fixedCommand=$(echo $AlterCommand | sed "s/ALTER TABLE//g" | sed "s/alter table//g" | sed "s/;//g" | sed "s/$AlterTable//g" | sed "s|'|\"|g" | sed "s/\`//g")
if [[ $Database == "empty" && $AlterTable == "empty" ]]; then
  Database=$(echo $fixedCommand | cut -d'.' -f 1)
  AlterTable=$(echo $fixedCommand | cut -d'.' -f 2 | awk '{print $1}')
  fixedCommand=$(echo $fixedCommand | sed "s/$Database.$AlterTable//g")
fi

echo "Issued database is: $Database"
echo "Issued table is   : $AlterTable"
echo "Typed command is  : $AlterCommand"

# Constants #
max_load="Threads_running=150"
critical_load="Threads_running=1000"

echo "Fixed command is  : $fixedCommand"
#command="pt-online-schema-change --alter '$AlterCommand' D=$Database,t=$AlterTable  --host $MySQLHostName --user $UserName  --password $Password  \
# $execute  --no-drop-old-table  --max-lag  300  \ #--no-drop-new-table
# --check-interval 120 --statistics  --progress time,30  --print \
# --chunk-size 1000  --chunk-time 0.5 --chunk-size-limit 4.0  --nocheck-replication-filters"

command="pt-online-schema-change --alter '$fixedCommand' D=$Database,t=$AlterTable --host $MySQLHostIP --user $UserName  --password $Password \
 --alter-foreign-keys-method auto  --max-load Threads_running=150 --critical-load Threads_running=300 $replicationProperties \
 --chunk-size 1000  --chunk-time 0.5 --chunk-size-limit 4.0  $execute"

# Generate remote file #
echo $command > $base_dir/OnlineSchemaChangerRemote.txt
mv $base_dir/OnlineSchemaChangerRemote.txt $base_dir/OnlineSchemaChangerRemote.sh
sed -i '1s/^/#!\/bin\/bash\n /' $base_dir/OnlineSchemaChangerRemote.sh
sudo chmod +x $scriptDIR/OnlineSchemaChangerRemote.sh
sudo scp -o "StrictHostKeyChecking no" $base_dir/OnlineSchemaChangerRemote.sh root@$MySQLHostIP:$base_dir 

# Execute remotely #
ssh -o "StrictHostKeyChecking no" root@$MySQLHostIP $base_dir/OnlineSchemaChangerRemote.sh
#eval $command
