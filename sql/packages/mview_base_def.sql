create or replace package mview_base authid current_user as
  --
  -- Package to work with control table of ORADBA materialized view replication system.
  --
  -- Copyright (c) 2010,2013, Kryazhevskikh Sergey, <soliverr@gmail.com>
  --

  -- Check existence of OWNER.TABLE_NAME in control table
  --
  function is_table_in_control_table( tablename IN varchar2 ) return integer;

  --
  -- Get owner part of OWNER.TABLE_NAME
  function get_owner_name( tblname IN varchar2 ) return varchar2;

  --
  -- Get table part of OWNER.TABLE_NAME
  function get_table_name( tblname IN varchar2 ) return varchar2;

  --
  -- Generate materialized view logs
  procedure gen_mlog( tablespace IN varchar2 default '&&MVIEW_BASE_TBSP_TBLS' );

  --
  -- Grant privileges for refresh administrator
  procedure grant_refresh_admin( username IN varchar2 );

end;
/
