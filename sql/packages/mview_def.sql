create or replace package mview authid current_user as
  --
  -- ORADBA materialized view replication system
  --
  -- Copyright (c) 2008-2010,2013, Kryazhevskikh Sergey, <soliverr@gmail.com>
  --

  -- Global variables and types
  --
  -- Database link name
  mview$dblink constant varchar2(32) := '&&ORA_DB_LINK_NAME';

  -- Rows return type
  type mview_sql is table of varchar2(2048);
  type chk_index_t is record (
       table_name user_indexes.table_name%type,
       index_name user_indexes.index_name%type,
       index_type user_indexes.index_type%type);
  type ret_chk_index_t is table of chk_index_t;

  -- Generate DCL to create materialized view logs
  --
  --  tablename  - generate DCL for this table only
  --  tablespace - set tablespace for materialized view logs
  --
  --  select * from table(gen_mlog_sql());
  --
  function gen_mlog_sql( tablename  IN varchar2 default NULL,
                         tablespace IN varchar2 default '&&ORA_TBSP_TBLS' ) return mview_sql pipelined;

  -- Create refresh groups
  --
  --  refreshgroup       - create this refresh group only
  --  drop_before_create - if true, then drop existent refresh group
  --
  procedure create_refresh_groups( refreshgroup IN varchar2 default NULL,
                                   drop_before_create IN boolean default FALSE );

  -- Create materialized views
  --
  --  tablename          - process this table only
  --  drop_before_create - if true, then drop existent materialized view
  --  refreshgroup       - process all tables into this refresh group only
  --
  procedure create_mviews( tablename IN varchar2 default NULL,
                           drop_before_create IN boolean default FALSE,
                           refreshgroup IN varchar2 default NULL );

  -- Drop materialized views
  --
  --  tablename          - process this table only
  --  refreshgroup       - process all tables into this refresh group only
  --
  procedure drop_mviews( tablename IN varchar2 default NULL,
                         refreshgroup IN varchar2 default NULL );

  -- Create indexes for materialized views according to source database
  --
  --  tablename          - create indexes for this table only
  --  drop_before_create - if true, then drop existent index
  --  refreshgroup       - create indexes for all tables into this refresh group only
  --  tablespace         - set tablespace to create indexes
  --
  procedure create_indexes( tablename IN varchar2 default NULL,
                            drop_before_create IN boolean default FALSE,
                            refreshgroup IN varchar2 default NULL,
                            tablespace IN varchar2 default '&&ORA_TBSP_INDX' );

  -- Create sequences according to source database
  --
  procedure create_sequences;

  -- Check index correctness
  --  tablename - check indexes for this table only
  --
  -- select * from table(check_indexes());
  --
  function check_indexes( tablename  IN varchar2 default NULL ) return ret_chk_index_t pipelined;

  -- Set/unset handler for refresh jobs errors
  --  job - job number to process or NULL (all available refresh dobs)
  --
  procedure refresh_jobs_wrap( job IN integer default NULL );
  procedure refresh_jobs_unwrap( job IN integer default NULL );

  -- Run all broken refresh jobs
  --
  procedure refresh_all;

  -- Add materialized view into refresh group
  --
  procedure add_to_rf_group( mviewname IN varchar2, refgroup IN varchar2 );

  -- Erase materialized view from refresh group
  --
  procedure del_from_rf_group( mviewname IN varchar2, refgroup IN varchar2 );

end;
/
