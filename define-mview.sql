--
-- PL/SQL package parameters
--

-- Schema owner to keep database objects
define ORA_SCHEMA_OWNER = &&MVIEW_BASE_SCHEMA_OWNER

-- Tablespace to keep tables
define ORA_TBSP_TBLS = &&MVIEW_BASE_TBSP_TBLS

-- Tablespace to keep indexes
define ORA_TBSP_INDX = &&MVIEW_BASE_TBSP_INDX

-- Database link name to run replication
define ORA_DB_LINK_NAME = ORADBA_MVIEW
