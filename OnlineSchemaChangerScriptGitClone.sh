#!/bin/bash

dirDate=$(date +%Y-%m-%d)

if [ -d "/home/cpq/OnlineSchemaChange/Latest" ]; then
  rm -rf /home/cpq/OnlineSchemaChange/Latest
fi

mkdir /home/cpq/OnlineSchemaChange/Latest

if [ -d /home/cpq/OnlineSchemaChange/work ]; then
  sudo rm -rf /home/cpq/OnlineSchemaChange/work
fi

sudo mkdir /home/cpq/OnlineSchemaChange/work

cd /home/cpq/OnlineSchemaChange/work

git clone git@bitbucket.org:dealhubio/prod.git -b "release/20220522"

mv /home/cpq/OnlineSchemaChange/work/prod/erd/*.sql  /home/cpq/OnlineSchemaChange/Latest
sudo rm -rf /home/cpq/OnlineSchemaChange/work
