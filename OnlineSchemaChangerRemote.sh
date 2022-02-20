#!/bin/bash
 thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command started at $thisTime"
pt-online-schema-change --alter ' ADD KEY sapr_cfac_pbsa_type (sapr_cfac_id,sapr_pbsa_guid,sapr_type)' D=configuration,t=sapr_presentation_rules --host 10.54.0.8 --user root --password root --alter-foreign-keys-method auto --max-load Threads_running=150 --critical-load Threads_running=300 --nocheck-replication-filters --max-lag 600 --chunk-size 1000 --chunk-time 0.5 --chunk-size-limit 4.0 --progress time,10 --execute
thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command finished at $thisTime"
