#!/bin/bash
# Autor: Izzy Fayon
# Ver  : 1.0
# 1.0  : Initial script

account=$1
source=$2
destination=$3
source_storage_dir=$4
RED='\033[0;31m'
GRE='\033[0;32m'
YEL='\033[0;33m'
NOC='\033[0m'
base_dir="/home/cpq"

set -e

zipInstalled=$(which zip | wc -l)
if [ $zipInstalled -eq 0 ]; then
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] ZIP package is not installed... installing ZIP packages"
    apt install zip -y
else
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] ZIP package is installed... No installation needed"
fi

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start export of account $account"

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Creating work directory"
if [ ! -d "$source_storage_dir/account_transfer_dump" ]; then
    mkdir $source_storage_dir/account_transfer_dump
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Directory $source_storage_dir/account_transfer_dump created"
else
    rm -rf $source_storage_dir/account_transfer_dump
    mkdir $source_storage_dir/account_transfer_dump
    echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Directory $source_storage_dir/account_transfer_dump wiped"
fi

# Delete old vanish files #
if [ $(ls $source_storage_dir/*.atrn | wc -l) -gt 0 ]; then
    for path in `ls $source_storage_dir/*.atrn | cut -d'.' -f 1 `; 
    do
        sudo rm -rf ${path}.*
    done
fi

rm -rf ${source_storage_dir}/${account}.*
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start process on source" > ${source_storage_dir}/${account}.atrn

# Generate dump command dynamicly using procedure #
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Populating work directory with dump commands"
mysql -h localhost -N -s -e"call db_manager.dump_entire_partition_account_data('$account','${source_storage_dir}/account_transfer_dump/')" > $source_storage_dir/account_transfer_dump/result_dmp.txt
mysql -h localhost -N -s -e"call db_manager.dump_entire_partition_account_objects('$account')" > ${source_storage_dir}/${account}.txt
partitionId=$(mysql -h localhost -N -s -e"select partition_id from db_manager.accounts_partitions where account_name = '$account'");
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Populating work directory with dump comands finished"


# Prepare result_dmp file as bash
sed -i '1s/^/#!\/bin\/bash\n /' ${source_storage_dir}/account_transfer_dump/result_dmp.txt
mv ${source_storage_dir}/account_transfer_dump/result_dmp.txt ${source_storage_dir}/account_transfer_dump/result_dmp.sh
chmod +x ${source_storage_dir}/account_transfer_dump/result_dmp.sh

# Prepare partition reorganizer file
sed -i '1s/^/#!\/bin\/bash\n /' ${source_storage_dir}/${account}.txt
mv ${source_storage_dir}/${account}.txt ${source_storage_dir}/${account}.sh
chmod +x ${source_storage_dir}/${account}.sh

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start dump data of $account"
${source_storage_dir}/account_transfer_dump/result_dmp.sh
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Dump data of $account finished"

rm -rf ${source_storage_dir}/account_transfer_dump/result_dmp.sh

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start compressing dump files to ${account}.zip"
zip -r -j ${source_storage_dir}/${account}.zip $source_storage_dir/account_transfer_dump/*.sql
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Compressing dump files to ${account}.zip finished"
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] End process on source" >> ${source_storage_dir}/${account}.atrn
