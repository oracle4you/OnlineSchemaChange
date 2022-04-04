#!/bin/bash
 thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command started at $thisTime"
pt-online-schema-change --alter ' ADD cfas_enable_approver_duplication BOOLEAN DEFAULT false NOT NULL AFTER cfas_enable_open_api, ADD COLUMN cfas_enable_product_rules_lazy_loading BOOLEAN NOT NULL DEFAULT false AFTER cfas_enable_uvpd_cache' D=configuration,t=cfas_account_settings --host 10.50.0.4 --user root --password root --alter-foreign-keys-method auto --max-load Threads_running=25 --critical-load Threads_running=50 --nocheck-replication-filters --max-lag 1200 --chunk-size 1000 --chunk-time 0.5 --chunk-size-limit 4.0 --progress time,10 --execute
thisTime=$(date +%Y-%m-%d" "%H:%M:%S)
echo "[INFO] Remote command finished at $thisTime"
