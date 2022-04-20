DELIMITER $$

USE `db_manager`$$

DROP PROCEDURE IF EXISTS `dump_entire_partition_account_data_v2`$$

CREATE DEFINER=`root`@`%` PROCEDURE `dump_entire_partition_account_data_v2`(IN p_account_name VARCHAR(50),IN p_path VARCHAR(50),IN p_new_account_id BIGINT)
BEGIN

DECLARE cur_schema_name VARCHAR(50);
DECLARE cur_table_name VARCHAR(50);
DECLARE cur_table_preffix CHAR(5);
DECLARE done INT DEFAULT 0;
DECLARE partition_name INT;
DECLARE path VARCHAR(50); 
DECLARE tables_list CURSOR FOR  SELECT schema_name, table_name,SUBSTRING(table_name,1,5) AS table_preffix
                                FROM   db_manager.partitions_by_instance
                                WHERE  skip_table = FALSE
                                AND schema_name<>'openapi';

DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

SET path = p_path;

SELECT a.`cfac_id`,a.`cfac_guid`,ap.account_name,ap.partition_id
INTO @v_cfac_id,@v_cfac_guid,@v_account_name,@v_partition_id
FROM `configuration`.`cfac_accounts` a
JOIN `db_manager`.`accounts_partitions` ap
 
 ON ap.partition_id = a.`cfac_id`
WHERE ap.`account_name` = IF(LENGTH(p_account_name)=0 ,ap.`account_name`,p_account_name)
LIMIT 1;

OPEN tables_list;

getrecords: LOOP
  FETCH tables_list INTO cur_schema_name, cur_table_name,cur_table_preffix;

  IF done = 1 THEN
                LEAVE getrecords;
  END IF;

					 SELECT CONCAT('echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start dump data from ',cur_schema_name,'.',cur_table_name,' table..."');
					 IF cur_table_name = 'dhht_html_template_backup' THEN
							SELECT CONCAT('mysqldump --replace --set-gtid-purged=OFF --no-create-info --skip-triggers --single-transaction --skip-add-locks --skip-disable-keys --complete-insert  --databases ',cur_schema_name,' --tables ',cur_table_name,' --where="',IF(cur_table_name='cfac_accounts','','dhht_cfht_'),'cfac_id=',@v_cfac_id,'" | sed "s/',@v_cfac_id,',/',p_new_account_id,',/g" > ',path,cur_schema_name,'.',cur_table_name,'.sql') AS '';
           ELSEIF cur_table_name NOT IN ('iams_in_app_messages','ifdq_deleted_quotes','pbch_playbook_changes','pbms_multi_system_attributes','qcns_quote_changes_notifications','uvrn_release_notes','uvsq_shared_quotes') THEN
             SELECT CONCAT('mysqldump --replace --set-gtid-purged=OFF --no-create-info --skip-triggers --single-transaction --skip-add-locks --skip-disable-keys --complete-insert  --databases ',cur_schema_name,' --tables ',cur_table_name,' --where="',IF(cur_table_name='cfac_accounts','',cur_table_preffix),'cfac_id=',@v_cfac_id,'" | sed "s/',@v_cfac_id,',/',p_new_account_id,',/g" > ',path,cur_schema_name,'.',cur_table_name,'.sql') AS '';
           ELSE 
             SELECT CONCAT('mysqldump --replace --set-gtid-purged=OFF --no-create-info --skip-triggers --single-transaction --skip-add-locks --skip-disable-keys --complete-insert  --databases ',cur_schema_name,' --tables ',cur_table_name,' --where="',IF(cur_table_name='cfac_accounts','',cur_table_preffix),'guid=',@v_cfac_id,'" | sed "s/',@v_cfac_id,',/',p_new_account_id,',/g" > ',path,cur_schema_name,'.',cur_table_name,'.sql') AS '';  
           END IF;  

END LOOP;

CLOSE tables_list;

END$$

DELIMITER ;