#!/bin/bash
# Autor: Izzy Fayon
# Ver  : 1.5
# 1.0  : Initial script
# 1.1  : Better validation on parameters
# 1.2  : Sync of export & import on source and destination hosts
# 1.3  : Sync of SP's on MySQL on source & destination
# 1.4  : Set status of cfac_id as NOT ACTIVE by 4-th parameter if provided (default is N)
# 1.5  : Added list of missing partitioned tables on error message

s_region=$1
d_region=$2
account=$3
disableOnSource=$4
rewriteInDestination=$5
impersonateEmails=$6
dryRun=$7
array_EU="10.50.0.5,10.50.0.12,10.50.0.4" # EU Hosts - On this list first slaves and first between slaves is non snapshoted
array_US="10.54.0.5,10.54.0.4,10.54.0.8"  # US Hosts - On this list first slaves and first between slaves is non snapshoted
array_TS="10.70.1.10"
array_STAGE_US="10.102.2.4"
array_STAGE_EU="10.101.2.4"
base_dir="/home/cpq"
dbUserName="root"
dbPassword="root"
source_storage_dir="/datadrive"
destination_storage_dir="/datadrive"
scriptDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RED='\033[0;31m'
GRE='\033[0;32m'
YEL='\033[0;33m'
NOC='\033[0m'
#set -x

if [[ $s_region == *"help"* || $d_region == *"help"* || $account == *"help"* ]]; then
  echo -e "\n[USAGE] $scriptDIR/process_account_orchestrator.sh <Source Region> <Destination Region> <Account name> <Disable on source>"
  echo "[INFO] <Source Region> - mandatory - Possible values EU, US, TS" 
  echo "[INFO] <Destination Region> - mandatory - Possible values EU, US, TS"
  echo "[INFO] <Account name> - mandatory - account name from db_manager.accounts_partitions table"
  echo "[INFO] <Disable on source> - not mandatory, default N possible values Y/N - disable account on source after transfer, "
  echo -e "${GRE}[EXAMPLE] $scriptDIR/process_account_orchestrator.sh US EU testAccount Y \n${NOC}"
  exit 1
fi

if [ -z $disableOnSource ]; then
  disableOnSource="N"
elif [[ -n $disableOnSource && $(echo $disableOnSource | tr a-z A-Z) != "Y" && $(echo $disableOnSource | tr a-z A-Z) != "N" ]]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Possible values Y or N${NOC}"
  exit 1
fi

if [[ ${s_region} == ${d_region} || -z $s_region || -z $d_region ]]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Mandatory parameters omitted or equal source and destination region${NOC}"
  exit 1
elif [[ ! $s_region == "US" && ! $s_region == "EU" && ! $s_region == "TS" && ! $s_region == "STAGE-US" && ! $s_region == "STAGE-EU" ]]; then
   echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Source region doesnt exists. Possible values are US or EU or TS${NOC}"
   exit 1
elif [[ ! $d_region == "US" && ! $d_region == "EU" && ! $d_region == "TS" && ! $s_region == "STAGE-US" && ! $s_region == "STAGE-EU" ]]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Destination region doesnt exists. Possible values are US or EU or TS${NOC}"
  exit 1
fi

# Find source  --> master to sync procedures 
if [ $s_region == "EU" ]; then
  for s_host in $(echo $array_EU | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      fi
    done
elif  [ $s_region == "US" ]; then
  for s_host in $(echo $array_US | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      fi
    done
elif [ $s_region == "STAGE-US" ]; then
  s_host=$array_STAGE_US
elif [ $s_region == "STAGE-EU" ]; then
  s_host=$array_STAGE_EU
elif [ $s_region == "TS" ]; then
  s_host=$array_TS         
fi
m_s_host=$s_host
#mysql -N -s -u$dbUserName -p$dbPassword -h $m_s_host -D db_manager 2>&1 < $base_dir/process_account_procedures.sql | grep -v mysql:

# Find source --> read from slave only to prevent potential locks !!! #
if [ $s_region == "EU" ]; then
  for s_host in $(echo $array_EU | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -eq 0 ]; then
        break
      fi
    done
elif  [ $s_region == "US" ]; then
  for s_host in $(echo $array_US | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -eq 0 ]; then
        break
      fi
    done
elif [ $s_region == "STAGE-US" ]; then
  s_host=$array_STAGE_US
elif [ $s_region == "STAGE-EU" ]; then
  s_host=$array_STAGE_EU         
fi

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Found slave for region $s_region $s_host"

# Check if account exists on source #
account_exists_source=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"select count(1) from db_manager.accounts_partitions where account_name='$account'" 2>&1 | grep -v mysql:)
cfac_id=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"select partition_id from db_manager.accounts_partitions where account_name='$account'" 2>&1 | grep -v mysql:)
if [ $account_exists_source -eq 0 ]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Account doesn't exists on region $s_region ${NOC}"
  exit 1
fi



# Find destiation --> write to master !!! #
if [ $d_region == "EU" ]; then
  for d_host in $(echo $array_EU | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      fi
    done
elif  [ $d_region == "US" ]; then
  for d_host in $(echo $array_US | sed "s/,/ /g")
    do
      aa=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      fi
    done
elif [ $d_region == "TS" ]; then    # For test purposes 
  d_host=$array_TS
elif [ $d_region == "STAGE-US" ]; then    # For test purposes 
  d_host=$array_STAGE_US  
elif [ $d_region == "STAGE-EU" ]; then    # For test purposes 
  d_host=$array_STAGE_EU  
fi

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Found master for region $d_region $d_host"

# Sync procedures on source --> write to master or TS as stand alone #
mysql -N -s -u$dbUserName -p$dbPassword -h $m_s_host -D db_manager 2>&1 < $base_dir/process_account_procedures_v2.sql | grep -v mysql:


# Sync procedures on destination --> write to master or TS as stand alone #
mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -D db_manager 2>&1 < $base_dir/process_account_procedures_v2.sql | grep -v mysql:

# Check if account exists on destination #
account_exists_dest=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"select count(1) from db_manager.accounts_partitions where account_name='$account'" 2>&1 | grep -v mysql:)
if [[ $account_exists_dest -ne 0 && $rewriteInDestination == "N" ]]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Account with same name exists on destination $d_region region ${NOC}"
  exit 1
elif [[ $account_exists_dest -eq 0 && $rewriteInDestination == "Y" ]]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] System can't do rewrite if account does not exsists on destination $d_region region ${NOC}"
  exit 1
fi




# Compare number of partitions #
count_part_sour=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"select count(1) from db_manager.partitions_by_instance where skip_table=0" 2>&1 | grep -v mysql:)
partTables_source=$(mysql -N -s -u$dbUserName -p$dbPassword -h $s_host -e"select concat(schema_name,'.',table_name) from db_manager.partitions_by_instance where skip_table=0" 2>&1 >  $base_dir/source.txt | grep -v mysql:)

count_part_dest=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"select count(1) from db_manager.partitions_by_instance where skip_table=0" 2>&1 | grep -v mysql:)
partTables_dest=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"select concat(schema_name,'.',table_name) from db_manager.partitions_by_instance where skip_table=0" 2>&1 >  $base_dir/dest.txt | grep -v mysql:)
if [ $count_part_sour -gt $count_part_dest ]; then
  #thisDiff=$(diff $base_dir/source.txt $base_dir/dest.txt)
  thisDiff=$(comm -3 $base_dir/source.txt $base_dir/dest.txt | sed 's/^\t//')
  missingTables=$(echo $thisDiff)
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Number of partitioned tables on $s_region ($s_host) not same as $d_region ($d_host). Process will stop.${NOC}"
  echo -e "$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Missing tables: $missingTables.${NOC}"
  rm -rf $base_dir/source.txt $base_dir/dest.txt
  exit 1
fi

################ V2 ##################
# get new id on destination db and create destination partitions #
if [ $dryRun == "N" ]; then
  if [ $rewriteInDestination == "N" ]; then
    new_partition_id=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"call db_manager.add_partitions_for_account('$account',@result); select @result as '';" 2>&1 | grep -v mysql:)
    if [[ $new_partition_id == ?(-)+([0-9]) ]]; then
      echo  "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Generated partitions on  $d_region $d_host under instance id $new_partition_id" 
      echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Account $account (cfac_id=$cfac_id) will be transfered from $s_region to $d_region as $account (cfac_id=$new_partition_id)"
    else
      echo -e "$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Empty or error generating instance id on destination $d_region $d_host"
      exit 1 
    fi
  else
    new_partition_id=$(mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"SELECT partition_id from db_manager.accounts_partitions where account_name='$account';" 2>&1 | grep -v mysql:)
    echo  "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Found partitions on  $d_region $d_host under instance id $new_partition_id" 
  fi
    

  # Sync process_account_export to last version on source host#
  #rsync $base_dir/process_account_export.sh root@$s_host:$base_dir/
  scp -o "StrictHostKeyChecking no" -r $base_dir/process_account_export_v2.sh root@$s_host:$base_dir/
  ssh -o "StrictHostKeyChecking no" root@$s_host chmod +x $base_dir/process_account_export_v2.sh

  # # Sync process_account_import to last version on destination host#
  #rsync $base_dir/process_account_import.sh root@$d_host:$base_dir/
  scp -o "StrictHostKeyChecking no" -r $base_dir/process_account_import_v2.sh root@$d_host:$base_dir/
  ssh -o "StrictHostKeyChecking no" root@$d_host chmod +x $base_dir/process_account_import_v2.sh

  # # Start generating data & transfers #
  ssh -o "StrictHostKeyChecking no" root@$s_host $base_dir/process_account_export_v2.sh $account $s_region $d_region $source_storage_dir $new_partition_id
  sudo scp -o "StrictHostKeyChecking no" root@$s_host:${source_storage_dir}/${account}.* $base_dir/
  if [ -f $base_dir/${account}.zip ]; then
    # Clean files from source after transfer to mid station (Jenkins) #
    ssh -o "StrictHostKeyChecking no" root@$s_host rm -rf ${source_storage_dir}/${account}.*
    ssh -o "StrictHostKeyChecking no" root@$s_host rm -rf ${source_storage_dir}/account_transfer_dump/

    # Clean old files on destination from previous processes
    ssh -o "StrictHostKeyChecking no" root@$d_host rm -rf ${destination_storage_dir}/*.zip $destination_storage_dir/*.sh $destination_storage_dir/*.atrn
    
    # Start transfer data from mid station (Jenkins) to destination #
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start transfer ${account} data to destination region $d_region on host $d_host"
    sudo scp -o "StrictHostKeyChecking no" $base_dir/${account}.* root@${d_host}:$destination_storage_dir/
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Transfer of ${account} data to destination region $d_region on host $d_host finished"
    ssh -o "StrictHostKeyChecking no" root@$d_host $base_dir/process_account_import_v2.sh $account $destination_storage_dir $rewriteInDestination

    # Write to log table log messages - source #
    sqlStatement="INSERT INTO db_manager.log_messages (logger, msg_date, log_msg) VALUES ('ACCOUNT TRANSFER',now(),'Account ${account}, old_cfac_id=${cfac_id} transfered from ${s_host} ${s_region} to ${d_host} ${d_region} as new_cfac_id=$new_partition_id');"
    mysql -N -s -u$dbUserName -p$dbPassword -h $m_s_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    # Write to log table log messages - destination #
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:
    
  else
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Account data doesn't exists or is not transfered from the source${NOC}"
    exit 1  
  fi

  # Convert account to not active #
  if [ $disableOnSource == "Y" ]; then
    # ToDo ==> Ask Alon if we need to remove record from `db_manager`.`accounts_partitions`
    sqlStatement="UPDATE configuration.cfas_account_settings SET cfas_cfac_id = ${cfac_id}*1000000 WHERE cfas_cfac_id = ${cfac_id};"
    mysql -N -s -u$dbUserName -p$dbPassword -h $m_s_host -e"$sqlStatement" 2>&1 | grep -v mysql:
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Value of ${account} cfac_id on source $s_region, changed on table configuration.cfas_account_settings from ${cfac_id} to ${cfac_id}000000"
  fi  

  # Impersonate emails #
  if [ $impersonateEmails == "Y" ]; then
    # ToDo ==> Ask Alon if we need to remove record from `db_manager`.`accounts_partitions`
    sqlStatement="UPDATE configuration.cfus_users set cfus_email = 'valooto.lockwait@gmail.com';"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="UPDATE configuration.cfco_contacts set cfco_email=concat(cfco_email, '_stage') WHERE cfco_email is not null AND cfco_email != '' AND cfco_email NOT LIKE '%s_stage%s';"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="UPDATE dealhub.dhus_users set dhus_email=concat(dhus_email, '_stage') WHERE dhus_email is not null AND dhus_email != '' AND dhus_email NOT LIKE '%s_stage%s';"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="UPDATE dealhub.guus_guest_users set guus_email=concat(guus_email, '_stage') WHERE guus_email is not null AND guus_email != '' AND guus_email NOT LIKE '%s_stage%s';"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="UPDATE configuration.cfus_users set cfus_password ='\$2a\$12\$jwx4jHFMm/LcWYuiBALO2uM3mkbLq5HISt17cpm3YRs2J/EZ.5IKa';"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="UPDATE configuration.cfss_server_settings SET cfss_value= '' WHERE cfss_key='webhook.auth.key';"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="TRUNCATE TABLE openapi.webhook_events; TRUNCATE TABLE openapi.webhooks;"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    sqlStatement="UPDATE configuration.cfas_account_settings SET cfas_integration_type = 'NONE' WHERE cfas_cfac_id = $new_partition_id;"
    mysql -N -s -u$dbUserName -p$dbPassword -h $d_host -e"$sqlStatement" 2>&1 | grep -v mysql:

    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] email data impersonated."
  fi

  # Clean files from middle Jenkins #
  rm -rf ${base_dir}/${account}.*
else
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Dry run finished successfully. Account $account can be transferred from $s_region to $d_region"    
fi # dryRun


