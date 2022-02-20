#!/bin/bash
# Autor: Izzy Fayon
# Ver  : 1.0
# 1.0  : Initial script

account=$1
destination_storage_dir=$2
rewriteInDestination=$3
path=$4
base_dir="/home/cpq"
dbUserName="root"
dbPassword="root"
RED='\033[0;31m'
GRE='\033[0;32m'
YEL='\033[0;33m'
NOC='\033[0m'


# Check if account data file exists #
if ! [ -f ${destination_storage_dir}/${account}.zip ]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Account data file doesn't exist. Process stopped !!!${NOC}"
  exit 1
fi  

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start importing  data of $account"
if [ -z $path ]; then
  path="${destination_storage_dir}/account_transfer_dump"
fi

getDBName() {
  string=$1
  a=$(echo $string |awk -v s=. '{print index($1,s)}')
  echo ${string:0:$a-1}
}


if [ ! -d "$path" ]; then
  mkdir "$path"
else
  rm -rf "$path"
  mkdir "$path"
fi

file=$(find $destination_storage_dir -name $account.zip -type f)

unzipInstalled=$(which unzip | wc -l)
if [ $unzipInstalled -eq 0 ]; then
  apt install unzip
fi

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Extract data of $account from $account.zip started"
unzip $file -d $path
if [ $(ls -la ${destination_storage_dir}/account_transfer_dump | wc -l) -gt 5 ]; then
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Extract data of $account from $account.zip finished"
else
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Missig files from $account.zip or $account.zip is corrupted. Process stopped !!!${NOC}"
  exit 1
fi  

reorgRoutineExists=$(mysql -N -s -u$dbUserName -p$dbPassword -h localhost -e"SELECT count(1) from information_schema.routines where routine_name='dump_entire_partition_account_reorganize' and routine_schema='db_manager'" 2>&1 | grep -v mysql:)
if [[ $reorgRoutineExists -eq 0 ]]; then
  echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Missig routine db_manager.dump_entire_partition_account_reorganize on destination MySQL. Process stopped !!!${NOC}"
  exit 1
fi  

if [ $rewriteInDestination == "N" ]; then
  if [ -f ${destination_storage_dir}/${account}.sh ]; then
    #chmod +x $base_dir/${account}.sh
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start reorganizing partitions on the DB."
    ${destination_storage_dir}/${account}.sh
  else
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${RED}[ERROR] Missig file $account.sh. Process stopped!!!${NOC}" 
    exit 1
  fi   
fi  

for i in  `ls $path/*.sql` ; do
        db=$(getDBName $i | sed "s|$path||g" | sed "s/\///g")
        echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Insert data from $i"
        mysql -N -s -u$dbUserName -p$dbPassword -D $db 2>&1 < $i | grep -v mysql:
done


# Delete old vanish files #
#if [ $(find ${base_dir}/*.atrn | wc -l) -gt 0 ]; then
#    for path in `find ${base_dir}/*.atrn | cut -d'.' -f 1 `; 
#    do
#        sudo rm -rf ${path}.*
#    done
#fi
echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) ${GRE}[INFO] Transfer $account data finished.${NOC}"