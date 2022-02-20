/*
SQLyog Ultimate v12.3.1 (64 bit)
MySQL - 5.7.35-0ubuntu0.18.04.1-log : Database - db_manager
*********************************************************************
*/


/*!40101 SET NAMES utf8 */;

/*!40101 SET SQL_MODE=''*/;

/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
USE `db_manager`;

/* Procedure structure for procedure `dump_entire_partition_account_data` */

/*!50003 DROP PROCEDURE IF EXISTS  `dump_entire_partition_account_data` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `dump_entire_partition_account_data`(IN p_account_name VARCHAR(50),IN p_path VARCHAR(50))
BEGIN
/*
call db_manager.dump_entire_partition_account_data('izzy')
*/
DECLARE cur_schema_name VARCHAR(50);
DECLARE cur_table_name VARCHAR(50);
DECLARE cur_table_preffix CHAR(5);
DECLARE done INT DEFAULT 0;
DECLARE partition_name INT;
DECLARE path VARCHAR(50); -- DEFAULT '/home/cpq/account_transfer_dump/';
DECLARE tables_list CURSOR FOR  SELECT schema_name, table_name,SUBSTRING(table_name,1,5) AS table_preffix
                                FROM   db_manager.partitions_by_instance
                                WHERE  skip_table = FALSE;

DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

SET path = p_path;

SELECT a.`cfac_id`,a.`cfac_guid`,ap.account_name,ap.partition_id
INTO @v_cfac_id,@v_cfac_guid,@v_account_name,@v_partition_id
FROM `configuration`.`cfac_accounts` a
JOIN `db_manager`.`accounts_partitions` ap
 -- ON ap.`account_name` COLLATE latin1_general_ci = a.`cfac_company_name_orig`
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
           IF cur_table_name NOT IN ('iams_in_app_messages','ifdq_deleted_quotes','pbch_playbook_changes','pbms_multi_system_attributes','qcns_quote_changes_notifications','uvrn_release_notes','uvsq_shared_quotes') THEN
             SELECT CONCAT('mysqldump --replace --set-gtid-purged=OFF --no-create-info --skip-triggers --single-transaction --skip-add-locks --skip-disable-keys --complete-insert  --databases ',cur_schema_name,' --tables ',cur_table_name,' --where="',IF(cur_table_name='cfac_accounts','',cur_table_preffix),'cfac_id=',@v_cfac_id,'" > ',path,cur_schema_name,'.',cur_table_name,'.sql') AS '';
           ELSE 
             SELECT CONCAT('mysqldump --replace --set-gtid-purged=OFF --no-create-info --skip-triggers --single-transaction --skip-add-locks --skip-disable-keys --complete-insert  --databases ',cur_schema_name,' --tables ',cur_table_name,' --where="',IF(cur_table_name='cfac_accounts','',cur_table_preffix),'guid=',@v_cfac_id,'" > ',path,cur_schema_name,'.',cur_table_name,'.sql') AS '';  
           END IF;  

END LOOP;

CLOSE tables_list;

SELECT CONCAT('echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start dump data from db_manager.accounts_partitions"');
SELECT CONCAT('mysqldump --replace --set-gtid-purged=OFF --no-create-info --skip-triggers --single-transaction --skip-add-locks --skip-disable-keys --complete-insert  --databases db_manager --tables accounts_partitions --where="account_name=''',@v_account_name,''' and partition_id=',@v_partition_id,'" > ',path,'db_manager.accounts_partitions.sql') AS '';

END */$$
DELIMITER ;

/* Procedure structure for procedure `dump_entire_partition_account_objects` */

/*!50003 DROP PROCEDURE IF EXISTS  `dump_entire_partition_account_objects` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `dump_entire_partition_account_objects`(IN p_account_name VARCHAR(50))
BEGIN
/*
call db_manager.dump_entire_partition_account_objects ('izzy')
*/
DECLARE cur_schema_name VARCHAR(50);
DECLARE cur_table_name VARCHAR(50);
DECLARE cur_table_preffix CHAR(5);
DECLARE done INT DEFAULT 0;
DECLARE partition_name INT;
DECLARE path VARCHAR(50); -- DEFAULT '/home/cpq/account_transfer_dump/';

DECLARE tables_list CURSOR FOR  SELECT schema_name, table_name,SUBSTRING(table_name,1,5) AS table_preffix
                                FROM   db_manager.partitions_by_instance
                                WHERE  skip_table = 0;

DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

SELECT a.`cfac_id`,a.`cfac_guid`,ap.account_name,ap.partition_id
INTO @v_cfac_id,@v_cfac_guid,@v_account_name,@v_partition_id
FROM `configuration`.`cfac_accounts` a
JOIN `db_manager`.`accounts_partitions` ap
 -- ON ap.`account_name` COLLATE latin1_general_ci = a.`cfac_company_name_orig`
-- WHERE ap.`account_name` = IF(LENGTH(p_account_name)=0 ,ap.`account_name`,p_account_name)
  ON a.`cfac_id`  = ap.partition_id
where ap.`account_name` =  IF(LENGTH(p_account_name)=0 ,ap.`account_name`,p_account_name) 
LIMIT 1;

OPEN tables_list;

getrecords: LOOP
  FETCH tables_list INTO cur_schema_name, cur_table_name,cur_table_preffix;

  IF done = 1 THEN
                LEAVE getrecords;
  END IF;

					 SELECT CONCAT('echo "$(date +%Y-%m-%d" "%H:%M:%S) [INFO] Start generate sql partition ',@v_account_name,'_',@v_cfac_id,' on table ',cur_schema_name,'.',cur_table_name,'..."');
           IF cur_table_name NOT IN ('iams_in_app_messages','ifdq_deleted_quotes','pbch_playbook_changes','pbms_multi_system_attributes','qcns_quote_changes_notifications','uvrn_release_notes','uvsq_shared_quotes') THEN
             SELECT CONCAT("mysql -N -s -u root -proot -h localhost -e""CALL db_manager.dump_entire_partition_account_reorganize(",@v_cfac_id,",'",cur_schema_name,"','",cur_table_name,"','",@v_account_name,"');"" 2>&1 | grep -v mysql:") as '';   
           ELSE 
             SELECT CONCAT("mysql -N -s -u root -proot -h localhost -e""CALL db_manager.dump_entire_partition_account_reorganize(",@v_cfac_id,",'",cur_schema_name,"','",cur_table_name,"','",@v_account_name,"');"" 2>&1 | grep -v mysql:") AS '';   
           END IF;  

END LOOP;
CLOSE tables_list;

END */$$
DELIMITER ;

/* Procedure structure for procedure `dump_entire_partition_account_reorganize` */

/*!50003 DROP PROCEDURE IF EXISTS  `dump_entire_partition_account_reorganize` */;

DELIMITER $$

/*!50003 CREATE  DEFINER=`root`@`%` PROCEDURE `dump_entire_partition_account_reorganize`(IN p_account_id INT,IN p_schema_name VARCHAR(128),IN p_table_name VARCHAR(128),IN p_account_name VARCHAR(50))
BEGIN

/*
call db_manager.dump_entire_partition_account_reorganize(izzy,'configuration','cfac_accounts')
*/

SET @statement='';
IF EXISTS (SELECT 1 FROM `information_schema`.`PARTITIONS` 
           WHERE TABLE_NAME = p_table_name -- COLLATE utf8_general_ci
           AND TABLE_SCHEMA = p_schema_name -- COLLATE utf8_general_ci
           AND PARTITION_DESCRIPTION > p_account_id + 1) THEN

	SELECT TABLE_SCHEMA,TABLE_NAME,PARTITION_NAME,PARTITION_DESCRIPTION, PARTITION_ORDINAL_POSITION 
	INTO @v_table_schema,@v_table_name,@v_partition_name,@v_partition_description,@v_partition_ordinal_position
	FROM `information_schema`.`PARTITIONS` 
	WHERE TABLE_NAME = p_table_name -- COLLATE utf8_general_ci
	AND TABLE_SCHEMA = p_schema_name -- COLLATE utf8_general_ci
	AND partition_description >= p_account_id+1
	LIMIT 1; 

  SET @statement =  CONCAT("ALTER TABLE `",@v_table_schema,"`.`",@v_table_name,"` REORGANIZE PARTITION `",@v_partition_name,"` INTO (PARTITION `",p_account_name,"_",p_account_id,"` VALUES LESS THAN (",p_account_id+1,"),PARTITION `",@v_partition_name,"` VALUES LESS THAN (",@v_partition_description,"));");
ELSE 
  SET @statement =  CONCAT("ALTER TABLE `",p_schema_name,'`.`',p_table_name,'` REORGANIZE PARTITION pmax INTO (PARTITION `',p_account_name,'_',p_account_id,'` VALUES LESS THAN (',p_account_id+1,'),PARTITION pmax VALUES LESS THAN (MAXVALUE));');          
END IF;

PREPARE stmt FROM @statement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

END */$$
DELIMITER ;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

