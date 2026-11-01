-- ------------------------------------------------------------------------------------------
-- Lab 2 · Rama empresarial · BORRA todo lo que creó setup-oracle-dx.sql (usuarios con sus
-- tablas, roles y tablespaces del JCR) para repetir la transferencia desde cero.
-- ⚠️ Destructivo: elimina todos los datos de DX en la PDB.
--   sqlplus / as sysdba @clean-oracle-dx.sql
-- Los errores "user/role does not exist" se pueden ignorar.
-- ------------------------------------------------------------------------------------------
SET VERIFY OFF
ACCEPT PDB_NAME   CHAR DEFAULT 'WPSDB'   PROMPT 'PDB de DX [WPSDB]: '
ACCEPT DX_DB_USER CHAR DEFAULT 'wpsuser' PROMPT 'Usuario de conexion de DX [wpsuser]: '

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
