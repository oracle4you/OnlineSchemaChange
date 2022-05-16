#!/bin/bash
# example account liveu_sb
account=$1
source=$2
destination=$3

set -e

if [ $source == "EU" ]; then
  s_host="10.50.0.4"
  d_host="10.220.1.11"
elif [ $source == "US" ]; then
  s_host="10.220.1.11"
  d_host="10.50.0.4"
fi

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start export of account $account"

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Creating work directory"
if [ ! -d "/home/cpq/acount_transfer_dump" ]; then
  ssh  -o "StrictHostKeyChecking no" cpq@$s_host mkdir /home/cpq/acount_transfer_dump
else
  ssh  -o "StrictHostKeyChecking no" cpq@$s_host rm -rf /home/cpq/acount_transfer_dump
  ssh  -o "StrictHostKeyChecking no" cpq@$s_host mkdir /home/cpq/acount_transfer_dump
fi

# Generate dump command dynamicly using procedure #
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Populating work directory with dump commands"
ssh  -o "StrictHostKeyChecking no" cpq@$s_host sudo mysql -u root -proot -h $s_host -N -s -e"call db_manager.dump_entire_partition_account_data('$account')" > /home/cpq/acount_transfer_dump/result_dmp.txt
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Populating work directory with dump comands finished"


# Prepare result_dmp file as bash
ssh  -o "StrictHostKeyChecking no" cpq@$s_host sed -i '1s/^/#!\/bin\/bash\n /' /home/cpq/acount_transfer_dump/result_dmp.txt
ssh  -o "StrictHostKeyChecking no" cpq@$s_host mv /home/cpq/acount_transfer_dump/result_dmp.txt /home/cpq/acount_transfer_dump/result_dmp.sh
ssh  -o "StrictHostKeyChecking no" cpq@$s_host chmod +x /home/cpq/acount_transfer_dump/result_dmp.sh

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start dump data of $account"
ssh  -o "StrictHostKeyChecking no" cpq@$s_host /home/cpq/acount_transfer_dump/result_dmp.sh
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Dump data of $account finished"

ssh  -o "StrictHostKeyChecking no" cpq@$s_host rm -rf /home/cpq/acount_transfer_dump/result_dmp.sh

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start compressing dump files to $account.zip"
ssh  -o "StrictHostKeyChecking no" cpq@$s_host zip -r -j $account.zip /home/cpq/acount_transfer_dump/*.sql
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Compressing dump files to $account.zip finished"
# Here must be some scp to transfer zip file to the destinatiom
