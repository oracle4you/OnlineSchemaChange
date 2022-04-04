#!/bin/bash
MySQLHostRegion=$1
Port=$2
UserName=$3
Password=$4
scriptDirectory=$(echo $5 | sed 's/##/ /g' | sed 's/~/ /g' | sed 's/"//g');
dryRun=$6
replicaLag=$7
scriptFilesArray=$8
array_EU="10.50.0.4,10.50.0.5,10.50.0.12"
array_US="10.54.0.4,10.54.0.5,10.54.0.8"
array_ALL="$array_EU,$array_US"
scriptDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
base_dir="/home/cpq"



# Links #
#cd /home/cpq
# wget https://downloads.percona.com/downloads/percona-toolkit/3.3.1/binary/debian/bionic/x86_64/percona-toolkit_3.3.1-1.bionic_amd64.deb
# missed packages: apt install libdbi-perl libdbd-mysql-perl libterm-readkey-perl libio-socket-ssl-perl
# dpkg -i percona-toolkit_3.3.1-1.bionic_amd64.deb

if [[ -z $replicaLag || $replicaLag -eq 0 ]]; then 
  replicaLag=1; 
fi
 
replicaLagSec=$((replicaLag * 60 ))

# Find master by region EU US TEST #
if [ $MySQLHostRegion == "STAGE-EU-DB01" ]; then
  host="10.101.2.4"
elif [ $MySQLHostRegion == "STAGE-US-DB01" ]; then
  host="10.102.2.4"
elif [ $MySQLHostRegion == "STAGE-CPQ" ]; then
  host="10.101.2.10"
elif [ $MySQLHostRegion == "TEST" ]; then
  host="10.70.1.8"
elif [ $MySQLHostRegion == "API-DB" ]; then
  host="10.66.0.20"

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
elif [ $MySQLHostRegion == "ALL" ]; then
  
  for host in $(echo $array_ALL | sed "s/,/ /g")
    do
      
      aa=$(mysql -N -s -u$UserName -p$Password -h $host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      echo "$host - $aa"
      if [ $aa -gt 0 ]; then
        MySQLHostIPArray="$MySQLHostIPArray $host"
      fi 
    done
fi

if [ $MySQLHostRegion != "ALL" ]; then
  MySQLHostIPArray=$host
fi  



# No master found on replication cluster #
if [ $MySQLHostIPArray == "" ]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Didn't find master on region $MySQLHostRegion. Process will stop."
  exit 1
fi

if [[ -n $replicaLagSec && $replicaLagSec -gt 0 ]]; then
#  replicationProperties="--check-slave-lag "
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

# Check array file names - if no sql file out with failure
for scriptFile in $(echo $scriptFilesArray | sed "s/,/ /g")
  do
    if ! [[ $scriptFile == *.sql ]]; then
      echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] File $scriptFile is not sql file. Process will stop."
      exit 1
    fi  
  done

# Install dos2unix if needed
dos2unixInstalled=$(which dos2unix | wc -l)
if [ $dos2unixInstalled -eq 0 ]; then
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] dos2unix package is not installed... installing dos2unix packages"
    apt install dos2unix -y
fi    


# Start working on array of hosts #
for MySQLHostIP in $(echo $MySQLHostIPArray)
  do
    # Start working on (for each file of picked host) #
    perconaInstalled=$(ssh -o "StrictHostKeyChecking no" root@$MySQLHostIP which pt-online-schema-change | wc -l)
    if  [ $perconaInstalled -eq 0 ]; then
      echo "$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Percona online schema change package not installed on destination host $MySQLHostIP. Process will be stopped"
      break
      exit 1
    fi

    for scriptFile in $(echo $scriptFilesArray | sed "s/,/ /g")
      do
        dos2unix ${scriptDirectory}/${scriptFile} 2> /dev/null
        # Clean remarked lines #       
        sed -i '/^\//d' ${scriptDirectory}/${scriptFile}
        sed -i '/^\s*--/ d' ${scriptDirectory}/${scriptFile}
        
        AlterCommand=$(cat ${scriptDirectory}/$scriptFile)

        echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Changes will be done on region: $MySQLHostRegion, host: $MySQLHostIP, Dry Run: $dryRun"
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Run script $scriptFile"
        # Command Splitter #
        AlterCommand=$(echo $AlterCommand | sed "s/';'/'|'/g" | sed "s/';;'/'||'/g" | sed "s/';;;'/'|||'/g") # Remove ';' incase DEFAULT ';' to not be caunted as multi-command delimiter 
        AlterCommand=$(echo $AlterCommand | sed "s/alter/ALTER/g" | sed "s/ table / TABLE /g")
        loopIds=$(echo $AlterCommand | grep -o ";" | wc -l)
        loop=1
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start splitting SQL command"
        while [ $loop -le $(($loopIds+1)) ]; 
          do
            isIndex=0
            fixedCommand=$(echo $AlterCommand | cut -d ";" -f ${loop})
            # CREATE INDEX ==> ALTER TABLE ADD KEY
            if [[ $(echo $fixedCommand | awk '{print $1}' | tr '[:lower:]' '[:upper:]') == "CREATE" && $(echo $fixedCommand | awk '{print $2}' | tr '[:lower:]' '[:upper:]') == "INDEX" ]]; then  
              indexName=$(echo $fixedCommand | awk '{print $3}')
              objectName=$(echo $fixedCommand | awk '{print $5}')
              indexProperty=$(echo $fixedCommand | cut -d "(" -f 2)
              fixedCommand="ALTER TABLE $objectName ADD KEY $indexName ($indexProperty"
              isIndex=1
            fi

            if [[ $(echo $fixedCommand | awk '{print $1}' | tr '[:lower:]' '[:upper:]') == "ALTER" && $(echo $fixedCommand | awk '{print $2}' | tr '[:lower:]' '[:upper:]') == "TABLE" ]]; then
              if [ $isIndex -eq 1 ]; then
                fixedCommand="$objectName ADD KEY $indexName ($indexProperty"
              else  
                fixedCommand=$(echo $AlterCommand | cut -d ";" -f ${loop} | sed "s/ALTER TABLE//g" | sed "s/alter table//g" | sed "s|'|\"|g" | sed "s/\`//g");
              fi
              Database=$(echo $fixedCommand | cut -d'.' -f 1)
              AlterTable=$(echo $fixedCommand | cut -d'.' -f 2 | awk '{print $1}')
              fixedCommand=$(echo $fixedCommand | sed "s/$Database.$AlterTable//g" | sed "s/|/;/g" | sed "s/||/;;/g" | sed "s/|||/;;;/g")

              # Constants #
              max_load="Threads_running=150"
              critical_load="Threads_running=1000"
              #command="pt-online-schema-change --alter '$fixedCommand' D=$Database,t=$AlterTable --host $MySQLHostIP --user $UserName  --password $Password \
              #--alter-foreign-keys-method auto  --max-load Threads_running=150 --critical-load Threads_running=300 $replicationProperties \
              #--chunk-size 1000  --chunk-time 0.5 --chunk-size-limit 4.0 --progress time,10 $execute"
 
              command="pt-online-schema-change --alter '$fixedCommand' D=$Database,t=$AlterTable --host $MySQLHostIP --user $UserName  --password $Password \
              --alter-foreign-keys-method auto  --max-load Threads_running=25 --critical-load Threads_running=50 $replicationProperties \
              --chunk-size 1000  --chunk-time 0.5 --chunk-size-limit 4.0 --progress time,10 $execute"

              # Generate remote file and call if DB & table != "empty"#
              echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Prompted command number [$loop] is: ALTER TABLE $fixedCommand"
              echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start changing objects on DB: $Database" 
              echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start changing table ${AlterTable} structure"
              echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Sent command to interpreter: ===> $fixedCommand"
              echo "thisTime=timeNow" > $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.txt
              echo "echo \"[INFO] Remote command started at AAA\"" >> $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.txt 
              echo $command >> $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.txt
              echo "thisTime=timeNow" >> $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.txt
              echo "echo \"[INFO] Remote command finished at AAA\"" >> $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.txt
              mv $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.txt $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.sh
              sed -i '1s/^/#!\/bin\/bash\n /' $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.sh
              sed -i 's/timeNow/$(date +%Y-%m-%d" "%H:%M:%S)/g' $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.sh
              sed -i 's/AAA/$thisTime/g' $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.sh
              sudo chmod +x $scriptDIR/OnlineSchemaChangerRemote_$MySQLHostRegion.sh
              sudo scp -o "StrictHostKeyChecking no" $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.sh root@$MySQLHostIP:$base_dir 

              # Execute remotely #
              ssh -o "StrictHostKeyChecking no" root@$MySQLHostIP $base_dir/OnlineSchemaChangerRemote_$MySQLHostRegion.sh
            else  # Regular commands
              fixedCommand=$(echo $AlterCommand | cut -d ";" -f ${loop} | sed "s|'|\"|g" | sed "s/\`//g");
              Database=$(echo $fixedCommand | cut -d "." -f 1 | awk '{print $NF}')

              AlterTable=$(echo $fixedCommand | cut -d'.' -f 2 | awk '{print $1}');
              fixedCommand=$(echo $fixedCommand | sed "s/|/;/g" | sed "s/||/;;/g" | sed "s/|||/;;;/g");

              if [ $dryRun == 'Yes' ]; then # Part of regular commands in dry run #
                # CREATE TABLE #
                if [[ $(echo $fixedCommand | awk '{print $1}') == "CREATE" && $(echo $fixedCommand | awk '{print $2}') == "TABLE" ]]; then
                  command="SELECT COUNT(1) FROM information_schema.tables where table_schema='$Database' AND table_name='$AlterTable';"
                  tableExists=$(mysql -u$UserName -p$Password -P$Port -h$MySQLHostIP -N -s -e"$command" 2>&1 | grep -v mysql:)
                  if [ $tableExists -gt 0 ]; then
                    echo "$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Table $Database.$AlterTable exists and can't be created twice. Process will stop."
                    exit 1
                  fi
                fi

                # DROP TABLE #
                if [[ $(echo $fixedCommand | awk '{print $1}') == "DROP" && $(echo $fixedCommand | awk '{print $2}') == "TABLE" ]]; then                
                  command="SELECT COUNT(1) FROM information_schema.tables where table_schema='$Database' AND table_name='$AlterTable';"
                  tableExists=$(mysql -u$UserName -p$Password -P$Port -h$MySQLHostIP -N -s -e"$command" 2>&1 | grep -v mysql:)
                  if [ $tableExists -eq 0 ]; then
                    echo "$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Table $Database.$AlterTable doesn't exists and can't be dropped. Process will stop."
                    exit 1
                  fi  
                fi
              fi # [ $dryRun == 'Yes' ]

              if [ $(echo ${#fixedCommand}) -gt 1 ]; then
                echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Run command $fixedCommand"
              fi

              if [ $dryRun == "No" ]; then             
                mysql -u$UserName -p$Password -P$Port -h$MySQLHostIP -N -s -e"$fixedCommand" 2>&1 | grep -v mysql:  
              fi
            fi  

            ((loop++))

          done

        # Clean object in case of DRY run #
        if  [ $(echo ${#dropCommand}) -gt 0 ]; then
          echo -e "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Clean tables after dry run - ${dropCommand}\n"
          mysql -u$UserName -p$Password -P$Port -h$MySQLHostIP -N -s -e"$dropCommand" 2>&1 | grep -v mysql:
          dropCommand=""
        fi    
        echo -e "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Run script $scriptFile finished\n"
      done 
  done