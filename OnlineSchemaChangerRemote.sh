#!/bin/bash
 thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command started at $thisTime"
pt-online-schema-change --alter ' ADD COLUMN test_stam2 BOOLEAN NOT NULL DEFAULT "0"' D=configuration,t=uvli_line_items --host 10.70.1.8 --user root --password root --alter-foreign-keys-method auto --max-load Threads_running=1000 --critical-load Threads_running=10000 --nocheck-replication-filters --max-lag 1200 --chunk-size 5000 --chunk-time 0.5 --chunk-size-limit 4.0 --progress time,10 --execute
thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command finished at $thisTime"
