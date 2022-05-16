#!/bin/bash
# example account liveu_sb
account=$1
source=$2
destination=$3

set -e

if [ $source == "EU" ]; then
  s_host="10.50.0.5"
  d_host="10.70.1.7"
elif [ $source == "US" ]; then
  s_host="10.70.1.7"
  d_host="10.50.0.5"
fi
echo $s_host

zipInstalled=$(which zip | wc -l)
if [ $zipInstalled -eq 0 ]; then
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] ZIP package is not installed... installing ZIP packages"
  apt install zip
else
  echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] ZIP package is installed... No installation needed"
fi

echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start export of account $account"

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Creating work directory"
if [ ! -d "/home/cpq/account_transfer_dump" ]; then
  mkdir /home/cpq/account_transfer_dump
else
  rm -rf /home/cpq/account_transfer_dump
  mkdir /home/cpq/account_transfer_dump
fi

# Generate dump command dynamicly using procedure #
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Populating work directory with dump commands"
mysql -h $s_host -N -s -e"call db_manager.dump_entire_partition_account_data('$account')" > /home/cpq/account_transfer_dump/result_dmp.txt
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Populating work directory with dump comands finished"


# Prepare result_dmp file as bash
sed -i '1s/^/#!\/bin\/bash\n /' /home/cpq/account_transfer_dump/result_dmp.txt
mv /home/cpq/account_transfer_dump/result_dmp.txt /home/cpq/account_transfer_dump/result_dmp.sh
chmod +x /home/cpq/account_transfer_dump/result_dmp.sh

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start dump data of $account"
/home/cpq/account_transfer_dump/result_dmp.sh
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Dump data of $account finished"

rm -rf /home/cpq/account_transfer_dump/result_dmp.sh

echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start compressing dump files to $account.zip"
zip -r -j $account.zip /home/cpq/account_transfer_dump/*.sql
echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Compressing dump files to $account.zip finished"
# Here must be some scp to transfer zip file to the destinatiom
