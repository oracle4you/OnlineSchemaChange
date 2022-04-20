#!/bin/bash

MySQLHostRegion=$1
accountName=$2
sftp_home_directory=$3

array_EU="10.50.0.4,10.50.0.5,10.50.0.12"
array_US="10.54.0.4,10.54.0.5,10.54.0.8"
UserName="root"
Password="root"

if [ -z $sftp_home_directory ]; then
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] SFTP Home directory not provided. Process will stop."
    exit 1
fi

if [ $MySQLHostRegion == "EU" ]; then
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
      echo "Hello"
      aa=$(mysql -N -s -u$UserName -p$Password -h $host -e"show slave hosts" 2>&1 | grep -v mysql: | wc -l)
      if [ $aa -gt 0 ]; then
        break
      else
        host=""  
      fi
      
    done    
elif [ $MySQLHostRegion == "TS" ]; then
  host="10.70.1.10"
fi

if [ $MySQLHostRegion != "ALL" ]; then
  MySQLHostIPArray=$host
fi  

# No master found on replication cluster #
if [ $MySQLHostIPArray == "" ]; then
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Didn't find master on region $MySQLHostRegion. Process will stop."
    exit 1
else
    cfac_id=$(mysql -N -s -u$UserName -p$Password -h $MySQLHostIPArray -e"SELECT partition_id FROM db_manager.accounts_partitions WHERE account_name='$accountName';" 2>&1 | grep -v mysql:) 
fi

if [[ -n $cfac_id && $cfac_id -gt 0 ]]; then
    sqlStatement="UPDATE configuration.cfas_account_settings SET cfas_import_folder = '$sftp_home_directory' WHERE cfas_cfac_id = $cfac_id ;"
    mysql -N -s -u$UserName -p$Password -h $MySQLHostIPArray -e"$sqlStatement" 2>&1 | grep -v mysql: 

    sqlStatement="REPLACE INTO configuration.cfim_import_settings (cfim_cfac_id,cfim_import_dir,cfim_default_product_assignment,cfim_default_pricing_rule,cfim_in_process) \
                  VALUES ( $cfac_id, '$sftp_home_directory' ,'INSERT_NEVER','INSERT_SOLID',0);"
    mysql -N -s -u$UserName -p$Password -h $MySQLHostIPArray -e"$sqlStatement" 2>&1 | grep -v mysql:

    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Added sftp home directory $sftp_home_directory to account $accountName on region $MySQLHostRegion"    
else
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Can't find account $accountName"
    exit 1
fi