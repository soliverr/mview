create or replace package body mview_base as
--
-- Package to work with control table of ORADBA materialized view replication system.
--
-- Copyright (c) 2010,2013, Kryazhevskikh Sergey, <soliverr@gmail.com>
--

------------------------------------------------------------------------------------------------
-- Public procedures
------------------------------------------------------------------------------------------------
--
-- Check existence of OWNER.TABLE_NAME in control table
function is_table_in_control_table( tablename IN varchar2 ) return integer as
  type cur_t is ref cursor;
  run$c      varchar2(1024);
  i$cnt      integer;
begin
   begin
     select count(1) into i$cnt from mviews
       where upper(table_name) = upper(get_owner_name(tablename)||'.'||get_table_name(tablename));
   exception
      when NO_DATA_FOUND then
       i$cnt := 0;
   end;

   return i$cnt;
end is_table_in_control_table;

--
-- Get owner part of OWNER.TABLE_NAME
function get_owner_name( tblname IN varchar2 ) return varchar2 as
  t$owner varchar2(128);
  i$i     integer;
begin
   if tblname is NULL then
      i$i := 0;
   else
      i$i := instr(tblname,'.');
   end if;

   if i$i = 0 then
      t$owner := sys_context( 'userenv', 'session_user' );
   else
      t$owner := substr(tblname, 1, i$i - 1);
   end if;

   return t$owner;
end get_owner_name;

--
-- Get table part of OWNER.TABLE_NAME
function get_table_name( tblname IN varchar2 ) return varchar2 as
  t$name varchar2(128);
  i$i     integer;
begin
   if tblname is NULL then
      i$i := 0;
   else
      i$i := instr(tblname,'.');
   end if;

   if i$i = 0 then
     t$name := tblname;
   else
     t$name := substr(tblname, i$i + 1);
   end if;

   return t$name;
end get_table_name;

--
-- Generate materialized view logs
procedure gen_mlog( tablespace IN varchar2 ) as
  type cur_t is ref cursor;
  pk$i          integer;
  ret$c         integer := 0;
  cod$e         number;
  run$c         varchar2(1024);
  res$c         varchar2(1024);
  cur1$c        cur_t;
begin
  dbms_application_info.set_module( 'mview_base.gen_mlog', 'start' );
  for rec in (select cr.table_name from mviews cr
                                  where cr.mview_name is not null
                                    and cr.refresh_group is not null
                                    and not exists ( select 1 from all_snapshot_logs
                                                      where log_owner = mview_base.get_owner_name(cr.table_name)
                                                        and master = mview_base.get_table_name(cr.table_name))
  ) loop

    run$c := 'select count(1)
              from all_constraints uc
              where uc.owner=:o
                and uc.table_name=:t
                and uc.CONSTRAINT_TYPE=''P'' and uc.status!=''DISABLED''';

    execute immediate run$c into pk$i
      using mview_base.get_owner_name(rec.table_name),
            mview_base.get_table_name(rec.table_name);

    res$c := 'create materialized view log on ' || rec.table_name || ' tablespace ' || tablespace;
    if pk$i = 0 then
       res$c := res$c || ' with rowid';
    end if;

    plog.debug( res$c );
    dbms_application_info.set_action( rec.table_name );
    begin
       execute immediate res$c;
       plog.info( 'Created mviewlog for ' || rec.table_name );
    exception when OTHERS then
       ret$c := ret$c + 1;
       cod$e := SQLCODE;
       plog.error( 'Error creating mviewlog for ' || rec.table_name || ': ' || SQLERRM(SQLCODE) );
    end;
  end loop;
  dbms_application_info.set_module( 'mview_base.gen_mlog', 'stop' );

  if ret$c > 0 then
    raise_application_error( -20101, 'There is '||ret$c||' errors :' || SQLERRM(cod$e), true );
  end if;

end gen_mlog;

--
-- Grant privileges for refresh administrator
procedure grant_refresh_admin( username IN varchar2 ) as
  type cur_t is ref cursor;
  type row_t is record (
        privilege     dba_tab_privs.privilege%type,
        owner         dba_tab_privs.owner%type,
        table_name    dba_tab_privs.table_name%type );
  run$c         varchar2(1024);
  cur$c         cur_t;
  priv$c        row_t;
begin
    plog.debug( 'Grant role &&MVIEW_BASE_ROLE_NAME privileges to ' || username );

    -- Grant system privileges
    execute immediate 'grant create database link to ' || username;
    execute immediate 'grant create materialized view to ' || username;
    execute immediate 'grant create synonym to ' || username;
    execute immediate 'grant create public synonym to ' || username;
    execute immediate 'grant create procedure to ' || username;
    execute immediate 'grant create table to ' || username;
    execute immediate 'grant create sequence to ' || username;
    execute immediate 'grant select on dba_jobs_running to ' || username;

    -- Grant role
    execute immediate 'grant &&MVIEW_BASE_ROLE_NAME to ' || username;

    -- Grant objects privileges to schema owners (for PL/SQL procedures)
    run$c := 'select privilege, owner, table_name
               from sys.dba_tab_privs where grantee = :o';

    open cur$c for run$c using upper('&&MVIEW_BASE_ROLE_NAME');

    loop
        begin
            fetch cur$c into priv$c;
        exception when others then
            plog.error( 'Error get role &&MVIEW_BASE_ROLE_NAME privileges ' || SQLERRM(SQLCODE) );
            exit;
        end;
        exit when cur$c%notfound;

       execute immediate 'grant ' || priv$c.privilege || ' on ' || priv$c.owner || '.' || priv$c.table_name || ' to ' || username;
    end loop;

end grant_refresh_admin;

--
-- Constructor
begin
    -- Set logging level
    plog.setlevel( plog.linfo );
end;
/
