#!/bin/bash
 pt-online-schema-change --alter ' ADD COLUMN myNumber int not null default 0' D=izzy,t=test1 --host 1.1.1.1 --user root --password root --alter-foreign-keys-method auto --max-load Threads_running=150 --critical-load Threads_running=300 --chunk-size 1000 --chunk-time 0.5 --chunk-size-limit 4.0 --dry-run --print
