--
-- PL/SQL package parameters
--

-- Schema owner to keep database objects
define MVIEW_BASE_SCHEMA_OWNER = &&ORADBA_SYS_OWNER

-- Tablespace to keep tables
define MVIEW_BASE_TBSP_TBLS = &&ORADBA_TBSP_TBLS

-- Tablespace to keep indexes
define MVIEW_BASE_TBSP_INDX = &&ORADBA_TBSP_INDX

-- Role to refresh materialized views
define MVIEW_BASE_ROLE_NAME = ORADBA_REFRESH
