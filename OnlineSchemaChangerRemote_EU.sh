#!/bin/bash
 thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command started at $thisTime"
pt-online-schema-change --alter ' ADD COLUMN uvli_include_positive_price BOOLEAN NOT NULL DEFAULT "0" AFTER uvli_mdpi_disable_rounding' D=configuration,t=uvli_line_items --host 10.50.0.4 --user root --password root --alter-foreign-keys-method auto --max-load Threads_running=25 --critical-load Threads_running=50 --nocheck-replication-filters --max-lag 1200 --chunk-size 1000 --chunk-time 0.5 --chunk-size-limit 4.0 --progress time,10 --execute
thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command finished at $thisTime"
