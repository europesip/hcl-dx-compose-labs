-- ------------------------------------------------------------------------------------------
-- Lab 2 · Enterprise branch · DELETES everything created by setup-oracle-dx.sql (users with
-- their tables, roles and JCR tablespaces) to repeat the transfer from scratch.
-- ⚠️ Destructive: removes all DX data in the PDB.
--   sqlplus / as sysdba @clean-oracle-dx.sql
-- "user/role does not exist" errors can be ignored.
-- ------------------------------------------------------------------------------------------
SET VERIFY OFF
ACCEPT PDB_NAME   CHAR DEFAULT 'WPSDB'   PROMPT 'DX PDB [WPSDB]: '
ACCEPT DX_DB_USER CHAR DEFAULT 'wpsuser' PROMPT 'DX connection user [wpsuser]: '

ALTER SESSION SET CONTAINER = &&PDB_NAME;

DROP USER &&DX_DB_USER CASCADE;
DROP USER jcr CASCADE;
DROP USER release CASCADE;
DROP USER community CASCADE;
DROP USER customization CASCADE;
DROP USER feedback CASCADE;
DROP USER likeminds CASCADE;

DROP ROLE WP_BASE_CONFIG_USERS;
DROP ROLE WP_BASE_RUNTIME_USERS;
DROP ROLE WP_JCR_CONFIG_USERS;
DROP ROLE WP_JCR_RUNTIME_USERS;
DROP ROLE WP_PZN_CONFIG_USERS;
DROP ROLE WP_PZN_RUNTIME_USERS;

DROP TABLESPACE ICMLFQ32 INCLUDING CONTENTS AND DATAFILES;
DROP TABLESPACE ICMLNF32 INCLUDING CONTENTS AND DATAFILES;
DROP TABLESPACE ICMVFQ04 INCLUDING CONTENTS AND DATAFILES;
DROP TABLESPACE ICMSFQ04 INCLUDING CONTENTS AND DATAFILES;
DROP TABLESPACE ICMLSNDX INCLUDING CONTENTS AND DATAFILES;
