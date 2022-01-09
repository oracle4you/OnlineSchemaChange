#!/bin/bash
 pt-online-schema-change --alter ' DROP COLUMN cfas_production_date' D=configuration,t=cfas_account_settings --host 10.70.1.10 --user root --password root --alter-foreign-keys-method auto --max-load Threads_running=150 --critical-load Threads_running=300 --chunk-size 1000 --chunk-time 0.5 --chunk-size-limit 4.0 --dry-run --print
