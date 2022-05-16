#!/bin/bash
# Autor: Izzy Fayon
# Ver  : 1.0
# 1.0  : Initial script

MySQLHostRegion=$1
array_NewUsers=$2
array_InactivateUsers=$3

array_EU="10.50.0.4,10.50.0.5,10.50.0.12"
array_US="10.54.0.4,10.54.0.5,10.54.0.8"
UserName="root"
Password="root"

#echo "Inactivate users: $array_InactivateUsers"
#echo "New users: $array_NewUsers"

if [ -z $MySQLHostRegion ]; then
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Region for changes not provided. Process will stop."
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

MySQLHostIPArray=$host
  

# No master found on replication cluster #
if [ $MySQLHostIPArray == "" ]; then
    echo -e "\n$(date +%Y-%m-%d" "%H:%M:%S) [ERROR] Didn't find master on region $MySQLHostRegion. Process will stop."
    exit 1
else
    retVal=$(mysql -N -s -u$UserName -p$Password -h $MySQLHostIPArray -e"call configuration.manage_support_users_jenkins('$array_NewUsers','$array_InactivateUsers');" 2>&1 | grep -v mysql:)
    echo "RetVal from MySQL is: $retVal"
fi