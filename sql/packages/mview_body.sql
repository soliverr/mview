create or replace package body mview as
--
-- ORADBA materialized view replication system
--
-- Copyright (c) 2008-2010,2013, Kryazhevskikh Sergey, <soliverr@gmail.com>
--

------------------------------------------------------------------------------------------------
-- Global variables
------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------
-- Internal procedures and functions
------------------------------------------------------------------------------------------------
--
-- Create table
procedure create_one_table( tblname IN varchar2, getdata IN char default 'N' ) as
  run$c   varchar2(3000) := NULL;
begin
  run$c := 'create table ' || mview_base.get_table_name(tblname) ||
           ' as select * from ' ||
           mview_base.get_owner_name(tblname) || '.' || mview_base.get_table_name(tblname) ||
           '@' || mview$dblink;
  if ( upper(getdata) = 'N' ) then
      run$c := run$c || ' where rownum < 1';
  end if;

  plog.debug( run$c );
  execute immediate run$c;

end create_one_table;

--
-- Create materialized view
procedure create_one_mview( mviewname IN varchar2, tblname IN varchar2, do_refresh boolean default true ) as
  run$c   varchar2(3000) := NULL;
  pk$i    integer        := 0;
begin
   run$c := 'select count(1)
               from all_constraints@' || mview$dblink || ' uc
              where uc.table_name=upper(:t)
                    and uc.owner=upper(:o)
                    and uc.CONSTRAINT_TYPE=''P'' and uc.status != ''DISABLED''';

  plog.debug( run$c || ' ' || mview_base.get_table_name(tblname) ||
                       ' ' || mview_base.get_owner_name(tblname) );
  execute immediate run$c into pk$i
    using mview_base.get_table_name(tblname), mview_base.get_owner_name(tblname);

  if pk$i = 0 then
    run$c := 'create materialized view ' || mviewname ||
             ' refresh on demand with rowid as select * from ';
  else
    run$c := 'create materialized view ' || mviewname ||
             ' refresh on demand with primary key as select * from ';
  end if;

  run$c := run$c || mview_base.get_owner_name(tblname) || '.' ||
                    mview_base.get_table_name(tblname) || '@' || mview$dblink;

  plog.debug( run$c );
  execute immediate run$c;

  if do_refresh then
    begin
      run$c := 'begin dbms_mview.refresh(''' || mviewname || ''', ''f''); end;';
      plog.debug( run$c );
      execute immediate run$c;
    exception when others then
      plog.error( 'Error refreshing matview ' || mviewname || ': ' || SQLERRM(SQLCODE) );
      raise;
    end;
  end if;
end create_one_mview;

-- Create refresh group procedure
procedure create_refresh_proc( refreshgroup IN varchar2 ) as
  type cur_t is ref cursor;

  l$job       number;
  run$c       varchar2(1024);
  proc$n      varchar2(64);
  new_what$c  varchar2(1024) := '';
  cur$c       cur_t;

begin
  run$c := 'select job from user_jobs
             where what like :t';

  plog.debug( run$c || upper(mview_base.get_owner_name(NULL)) );

  open cur$c for run$c
       using '%dbms_refresh.refresh%' || 
             upper(mview_base.get_owner_name(NULL)) || '%' || refreshgroup || '%';
  loop
    fetch cur$c into l$job;
    exit when cur$c%notfound;

    dbms_application_info.set_module( 'mview.create_refresh_proc', 'processing ' || l$job);

    proc$n := 'ORADBA_REFRESH_' || upper(refreshgroup);
    run$c := '
create or replace procedure ' || proc$n || ' as
l$sid number;
begin
  begin
    select sid into l$sid from dba_jobs_running where job = ' || l$job ||';
  exception when NO_DATA_FOUND then
    dbms_job.run( ' || l$job || ' );
  end;
end;';
    begin
        plog.debug( run$c );
        execute immediate run$c;

        -- Set error handler for this job
        refresh_jobs_wrap( l$job );

        -- Grant execute privilege 
        run$c := 'grant execute on "' || upper(mview_base.get_owner_name(NULL)) || '".' ||
                 proc$n || ' to &&MVIEW_BASE_ROLE_NAME';

        plog.debug( run$c );
        execute immediate run$c;

        /* FIXME: Name conflict for several schemas
        run$c := 'create or replace public synonym ' || proc$n ||
                 ' for "' || upper(mview_base.get_owner_name(NULL)) || '".' || proc$n;
        plog.debug( run$c );
        execute immediate run$c;
        */

        plog.info( 'Created refresh procedure oradba_refresh_' || refreshgroup );
    exception when others then
        close cur$c;
        plog.error( 'Error creating refresh procedure oradba_refresh_' || refreshgroup ||
                    ': ' || SQLERRM(SQLCODE) );
        raise_application_error( -20101, run$c, true );
    end;
  end loop;
  close cur$c;
end;

------------------------------------------------------------------------------------------------
-- Public procedures
------------------------------------------------------------------------------------------------

--
-- Run all broken refresh jobs
--
procedure refresh_all as
  type cur_t is ref cursor;

  l$job       number;
  run$c       varchar2(1024);
  proc$n      varchar2(64);
  new_what$c  varchar2(1024) := '';
  cur$c       cur_t;
  pCTX        plog.log_ctx   := plog.init ( pLEVEL       => plog.linfo,
                                            pLOG4J       => FALSE,
                                            pLOGTABLE    => TRUE,
                                            pOUT_TRANS   => FALSE,
                                            pALERT       => FALSE,
                                            pTRACE       => FALSE,
                                            pDBMS_OUTPUT => TRUE );
begin
  dbms_application_info.set_module( 'refresh_all', 'start' );
  run$c := 'select job from user_jobs
             where what like :t
               and (broken = ''Y''
                    or (failures > 0 and to_char(next_date, ''HH24-MI-SS'') = ''00-00-00''))';

  open cur$c for run$c
     using '%dbms_refresh.refresh%' || upper(mview_base.get_owner_name(NULL)) || '%';

  loop
    fetch cur$c into l$job;
    exit when cur$c%notfound;

    dbms_application_info.set_action( 'refresh job ' || l$job);
    plog.warn( pCTX, 'Run refresh job ' || l$job );

    begin
      dbms_job.run( l$job );
    exception when OTHERS then
      plog.error( pCTX, 'Error running refresh job ' || l$job || ' :' || SQLERRM(SQLCODE) );
    end;
  end loop;
  close cur$c;
  dbms_application_info.set_module( 'refresh_all', 'stop' );
end;

--
-- Add materialized view into refresh group
procedure add_to_rf_group( mviewname IN varchar2, refgroup IN varchar2 ) as
  run$c VARCHAR2(1024);
begin
  if refgroup is not NULL then
    run$c := 'begin dbms_refresh.add(name =>''"'
             || upper(mview_base.get_owner_name(NULL)) || '".' || refgroup
             || ''', list => ''' || mviewname || '''); end;';
    plog.debug( run$c );
    execute immediate run$c;
  end if;
end add_to_rf_group;

--
-- Erase materialized view from refresh group
procedure del_from_rf_group( mviewname IN varchar2, refgroup IN varchar2 ) as
  run$c VARCHAR2(1024);
begin
  if refgroup is not NULL then
    run$c := 'begin dbms_refresh.subtract(name =>''"'
             || upper(mview_base.get_owner_name(NULL)) || '".'
             || refgroup || ''', list => ''' || mviewname || '''); end;';
    plog.debug( run$c );
    execute immediate run$c;
  end if;
end del_from_rf_group;

--
-- Create refresh groups
procedure create_refresh_groups( refreshgroup IN varchar2, drop_before_create IN boolean ) as
  type cur_t is ref cursor;
  type row_t is record (
    group_name   refresh_groups.group_name%type,
    refresh_time refresh_groups.refresh_time%type);

  interval$c varchar2(300);
  run$c      varchar2(1024):=NULL;
  ret$c      integer := 0;
  cod$e      number;
  count$r    number := 0;
  i$c        number := 0;
  cur$c      cur_t;
  rec        row_t;

begin
  dbms_application_info.set_module( 'mview.create_refresh_groups', 'start' );

  -- Count records to proceed
  run$c := 'select count(1)
              from refresh_groups cg
             where lower(cg.group_name) = case
                                          when :t is NULL then lower(cg.group_name)
                                          else lower(:t)
                                          end
               and not exists (select 1 from user_refresh where rname = upper(cg.group_name))';

  open cur$c for run$c using refreshgroup, refreshgroup;
  loop
    fetch cur$c into count$r;
    exit when cur$c%notfound;
  end loop;
  close cur$c;

  run$c := 'select *
              from refresh_groups cg
             where lower(cg.group_name) = case
                                          when :t is NULL then lower(cg.group_name)
                                          else lower(:t)
                                          end
               and not exists (select 1 from user_refresh where rname = upper(cg.group_name))
             order by cg.group_name';

  open cur$c for run$c using refreshgroup, refreshgroup;
  loop
    fetch cur$c into rec;
    exit when cur$c%notfound;

    i$c := cur$c%rowcount;
    dbms_application_info.set_action( i$c || '/' || count$r || ': ' || rec.group_name );

    if drop_before_create = true then
      -- FIXME: check refresh group existence
      begin
        run$c:='begin dbms_refresh.destroy( '''||rec.group_name||''' ); end;';
        plog.debug( run$c );
        execute immediate run$c;
        plog.info( 'Refresh group ' || rec.group_name || ' deleted' );
      exception when OTHERS then
        ret$c := ret$c + 1;
        cod$e := SQLCODE;
        plog.error( 'Error deleting refresh group ' || rec.group_name || ': ' || SQLERRM(SQLCODE) );
      end;
    end if;

    begin
        run$c:='begin dbms_refresh.make(
                  name             => '''|| rec.group_name || ''',
                  list             => '''',
                  next_date        => SYSDATE,
                  interval         => ''' || rec.refresh_time || ''',
                  implicit_destroy => false,
                  lax              => true);
                 end;';
         plog.debug( run$c );
         execute immediate run$c;
         plog.info( 'Refresh group ' || rec.group_name || ' created(' || i$c || ' of ' || count$r || ')'  );

         --
         -- Create refresh procedure for this group
         create_refresh_proc( rec.group_name );

    exception when others then
         ret$c := ret$c + 1;
         cod$e := SQLCODE;
         plog.error( 'Error creating refresh group ' || rec.group_name || ': ' || SQLERRM(SQLCODE) );
    end;
  end loop;
  close cur$c;
  commit;

  dbms_application_info.set_module( 'mview.create_refresh_groups', 'stop' );

  if ret$c > 0 then
    raise_application_error( -20101, 'There are '||ret$c||' errors :' || SQLERRM(cod$e), true );
  end if;
end;

--
-- Generate DCL to create materialized view logs
function gen_mlog_sql( tablename IN varchar2, tablespace IN varchar2 ) return mview_sql pipelined as
  type cur_t is ref cursor;
  type row_t is record (
    mview_name    mviews.mview_name%type,
    table_name    mviews.table_name%type,
    refresh_group mviews.refresh_group%type );

  pk$i          integer;
  run$c         varchar2(1024);
  res$c         varchar2(1024);
  table_space$c varchar2(300);
  cur1$c        cur_t;
  rec           row_t;

begin
  if tablespace is not NULL then 
     table_space$c:=' tablespace '|| tablespace; 
  end if;

  run$c := 'select cm.mview_name, cm.table_name, cm.refresh_group
              from mviews cm
             where cm.refresh_group is not NULL
                   and lower(cm.table_name) = case
                                              when :t is NULL then lower(cm.table_name)
                                              else lower(:t)
                                              end
             order by process_order';

  plog.debug( run$c );

  open cur1$c for run$c using tablename, tablename;

  run$c := 'select count(1)
              from user_constraints@' || mview$dblink || ' uc
              where uc.table_name=upper(:t)
                    and uc.CONSTRAINT_TYPE=''P'' and uc.status!=''DISABLED''';
  loop
    fetch cur1$c into rec;
    exit when cur1$c%notfound;

    execute immediate run$c into pk$i using mview_base.get_table_name(rec.table_name);

    res$c := 'create materialized view log on ' || rec.table_name || table_space$c;
    if pk$i > 0 then
       res$c := res$c || ';';
    else
       res$c := res$c || ' with rowid;';
    end if;

    pipe row ( res$c );
  end loop;

  close cur1$c;
  return;
end;

--
-- Create materialized views
procedure create_mviews( tablename IN varchar2, drop_before_create IN boolean, refreshgroup IN varchar2 ) as
  type cur_t is ref cursor;
  type row_t is record (
    mview_name    mviews.mview_name%type,
    table_name    mviews.table_name%type,
    refresh_group mviews.refresh_group%type,
    get_data      mviews.get_data%type );

  rc$c    integer := 0;
  drf$c   boolean;
  ret$c   integer := 0;
  cod$e   number;
  count$r number :=0;
  i$c     number := 0;
  run$c   varchar2(1024);
  nam$t   varchar2(256);
  cur$c   cur_t;
  rec     row_t;

begin

  dbms_application_info.set_module( 'mview.create_mviews', 'check' );

  -- If table exists in control table
  if tablename is not NULL then
    select count(1) into count$r from mviews where table_name = upper( tablename );
    if count$r = 0 then
      run$c := 'There is no record in control table: ' || tablename || ': ' || SQLERRM(SQLCODE);
      plog.error( run$c );
      raise_application_error( -20101, run$c, true );
    end if;
  end if;

  dbms_application_info.set_module( 'mview.create_mviews', 'start' );

  -- Count records to proceed
  run$c := 'select count(1)
              from mviews cm
             where lower(cm.table_name) = case
                                          when :t is NULL then lower(cm.table_name)
                                          else lower(:t)
                                          end
                   and nvl2(cm.refresh_group, lower(cm.refresh_group), 1) =
                         case
                         when :r is NULL then nvl2(cm.refresh_group,lower(cm.refresh_group), 1)
                         else lower(:r)
                         end';

  open cur$c for run$c using tablename, tablename, refreshgroup, refreshgroup;
  loop
    fetch cur$c into count$r;
    exit when cur$c%notfound;
  end loop;
  close cur$c;

  run$c := 'select cm.mview_name, cm.table_name, cm.refresh_group, cm.get_data
              from mviews cm
             where lower(cm.table_name) = case
                                          when :t is NULL then lower(cm.table_name)
                                          else lower(:t)
                                          end
                   and nvl2(cm.refresh_group, lower(cm.refresh_group), 1) =
                         case
                         when :r is NULL then nvl2(cm.refresh_group,lower(cm.refresh_group), 1)
                         else lower(:r)
                         end
             order by process_order';

  open cur$c for run$c using tablename, tablename, refreshgroup, refreshgroup;
  loop
    fetch cur$c into rec;
    exit when cur$c%notfound;

    i$c := cur$c%rowcount;
    dbms_application_info.set_action( i$c || '/' || count$r || ': ' || rec.table_name );

    if drop_before_create = true then
       -- Check synonym name
       begin
         select synonym_name into nam$t from user_synonyms
          where synonym_name = upper(rec.mview_name);
         if length( nam$t ) > 0 then
            execute immediate 'drop synonym ' || nam$t;
            plog.info( 'Same synonym ' || nam$t || ' droped' );
         end if;

         begin
           if rec.mview_name is not NULL then
             run$c := 'drop materialized view ' || rec.mview_name;
           else
             run$c := 'drop table ' || rec.table_name;
           end if;
           execute immediate run$c;
           plog.info( 'Current table/matview ' || nvl(rec.mview_name,rec.table_name) || ' droped' );
         exception when OTHERS then
           ret$c := ret$c + 1;
           cod$e := SQLCODE;
           plog.error( 'Error deleting current table/matview ' || nvl(rec.mview_name,rec.table_name) || ': ' || SQLERRM(SQLCODE) );
         end;
       exception when NO_DATA_FOUND then
         NULL;
       end;

       -- Check for table
       select count(1) into rc$c from user_tables
        where upper(table_name) = upper(rec.mview_name)
              or upper(table_name) = upper(mview_base.get_table_name(rec.table_name));
       if rc$c > 0 then
         begin
           if rec.mview_name is not NULL then
              run$c := 'drop materialized view ' || rec.mview_name;
           else
             run$c := 'drop table ' || rec.table_name;
           end if;
           plog.debug( run$c );
           execute immediate run$c;
           plog.info( 'Table/matview ' || nvl(rec.mview_name,rec.table_name) || ' droped' );
         exception when OTHERS then
           ret$c := ret$c + 1;
           cod$e := SQLCODE;
           plog.error( 'Error deleting table/matview ' || nvl(rec.mview_name,rec.table_name) || ': ' || SQLERRM(SQLCODE) );
         end;
         begin
           execute immediate 'drop synonym ' || mview_base.get_table_name(rec.table_name);
           plog.info( 'Synonym for ' || rec.table_name || ' droped' );
         exception when others then
           NULL;
         end;
       end if;
    end if;

    if rec.mview_name is NULL then
       select count(1) into rc$c from user_tables
        where upper(table_name) = upper(mview_base.get_table_name(rec.table_name));
       if rc$c = 0 then
         -- Create table
         begin
           create_one_table( rec.table_name, rec.get_data );
           plog.info( 'Table ' || rec.table_name || ' created(' || i$c || ' of ' || count$r || ')' );
         exception when OTHERS then
           ret$c := ret$c + 1;
           cod$e := SQLCODE;
           run$c := 'Error createing table ' || rec.table_name || ': ' || SQLERRM(SQLCODE);
           plog.error( run$c );
         end;
       end if;
    else
       select count(1) into rc$c from user_tables where table_name = upper(rec.mview_name);
       if rc$c = 0 then
         -- Create materialized view
         begin
           -- nvl2(rec.refresh_group, true, false) is not allowed in PL/SQL
           if rec.refresh_group is NULL then
             drf$c := false;
           else
             drf$c := true;
           end if;
           create_one_mview( rec.mview_name, rec.table_name, drf$c );
           plog.info( 'Matview ' || rec.mview_name || ' created(' || i$c || ' of ' || count$r || ')');

           -- Add matview into refresh group
           begin
             add_to_rf_group( rec.mview_name, rec.refresh_group );
           exception when OTHERS then
             ret$c := ret$c + 1;
             cod$e := SQLCODE;
             plog.error( 'Error adding matview ' || rec.mview_name || ' into refresh group ' ||
                          rec.refresh_group || ': ' || SQLERRM(SQLCODE) );
           end;

           -- Create synonym
           begin
             nam$t := substr(rec.table_name, instr(rec.table_name,'.') + 1);
             run$c := 'create or replace synonym ' || nam$t || ' for ' || rec.mview_name;
             plog.debug( run$c );
             execute immediate run$c;
             plog.info( 'Synonym ' || nam$t || ' created' );
           exception when OTHERS then
             ret$c := ret$c + 1;
             cod$e := SQLCODE;
             plog.error( 'Error creating synonym ' || nam$t || ': ' || SQLERRM(SQLCODE) );
           end;

         exception when OTHERS then
           ret$c := ret$c + 1;
           cod$e := SQLCODE;
           run$c := 'Error creating matview ' || rec.mview_name || ': ' || SQLERRM(SQLCODE);
           plog.error( run$c );
         end;
       end if;
    end if;
    commit;
  end loop;
  close cur$c;
  commit;

  dbms_application_info.set_module( 'mview.create_mviews', 'stop' );

  if ret$c > 0 then
    raise_application_error( -20101, 'There are '||ret$c||' errors :' || SQLERRM(cod$e), true );
  end if;

end;

--
-- Drop materialized views
procedure drop_mviews( tablename IN varchar2, refreshgroup IN varchar2 ) as
  type cur_t is ref cursor;
  type row_t is record (
    mview_name    mviews.mview_name%type,
    table_name    mviews.table_name%type,
    refresh_group mviews.refresh_group%type,
    get_data      mviews.get_data%type );

  rc$c    integer := 0;
  ret$c   integer := 0;
  cod$e   number;
  count$r number := 0;
  i$c     number := 0;
  run$c   varchar2(1024);
  nam$t   varchar2(256);
  cur$c   cur_t;
  rec     row_t;

begin
  dbms_application_info.set_module( 'mview.drop_mviews', 'check' );

  -- If table exists in control table
  if tablename is not NULL then
    select count(1) into count$r from mviews where table_name = upper( tablename );
    if count$r = 0 then
      run$c := 'Нет данных в управляющей таблице: ' || tablename || ': ' || SQLERRM(SQLCODE);
      plog.error( run$c );
      raise_application_error( -20101, run$c, true );
    end if;
  end if;

  dbms_application_info.set_module( 'mview.drop_mviews', 'start' );

  -- Count records to proceed
  run$c := 'select count(1)
              from mviews cm
             where lower(cm.table_name) = case
                                          when :t is NULL then lower(cm.table_name)
                                          else lower(:t)
                                          end
                   and nvl2(cm.refresh_group, lower(cm.refresh_group), 1) = 
                         case
                         when :r is NULL then nvl2(cm.refresh_group,lower(cm.refresh_group), 1)
                         else lower(:r)
                         end';

  open cur$c for run$c using tablename, tablename, refreshgroup, refreshgroup;
  loop
    fetch cur$c into count$r;
    exit when cur$c%notfound;
  end loop;
  close cur$c;

  run$c := 'select cm.mview_name, cm.table_name, cm.refresh_group, cm.get_data
              from mviews cm
             where lower(cm.table_name) = case
                                          when :t is NULL then lower(cm.table_name)
                                          else lower(:t)
                                          end
                   and nvl2(cm.refresh_group, lower(cm.refresh_group), 1) =
                         case
                         when :r is NULL then nvl2(cm.refresh_group,lower(cm.refresh_group), 1)
                         else lower(:r)
                         end
             order by process_order';

  open cur$c for run$c using tablename, tablename, refreshgroup, refreshgroup;
  loop
    fetch cur$c into rec;
    exit when cur$c%notfound;

    i$c := cur$c%rowcount;
    dbms_application_info.set_action( i$c || '/' || count$r || ': ' || rec.table_name );

    select count(1) into rc$c from user_tables
     where upper(table_name) = upper(rec.mview_name)
           or upper(table_name) = upper(mview_base.get_table_name(rec.table_name));
    if rc$c > 0 then
      begin
        if rec.mview_name is not NULL then
           run$c := 'drop materialized view ' || rec.mview_name;
        else
           run$c := 'drop table ' || rec.table_name;
        end if;
        plog.debug( run$c );
        execute immediate run$c;
        plog.info( 'Table/matview ' || nvl(rec.mview_name,rec.table_name) || ' droped('
                   || i$c || ' of ' || count$r || ')' );
      exception when OTHERS then
        ret$c := ret$c + 1;
        cod$e := SQLCODE;
        plog.error( 'Error deleting ' || nvl(rec.mview_name,rec.table_name) || ': ' || SQLERRM(SQLCODE) );
      end;
      begin
        execute immediate 'drop synonym ' || mview_base.get_table_name(rec.table_name);
        plog.info( 'Synonym for ' || rec.table_name || ' droped' );
      exception when others then
        NULL;
      end;
    end if;

    commit;
  end loop;
  close cur$c;
  commit;

  dbms_application_info.set_module( 'mview.drop_mviews', 'stop' );

  if ret$c > 0 then
    raise_application_error( -20101, 'There are '||ret$c||' errors :' || SQLERRM(cod$e), true );
  end if;

end;

--
-- Create indexes for materialized views according to source database
procedure create_indexes( tablename IN varchar2, drop_before_create IN boolean, 
                          refreshgroup IN varchar2, tablespace IN varchar2 ) as

  type cur_t is ref cursor;
  type row_t is record (
        table_name    mviews.table_name%type,
        mview_name    mviews.mview_name%type,
        refresh_group mviews.refresh_group%type,
        index_name    user_indexes.index_name%type,
        uniq          user_indexes.uniqueness%type );

  items$c varchar2(3000) := '';
  tbl$c   varchar2(300)  := NULL;
  col$c   varchar2(300)  := NULL;
  --col$e   varchar2(300)  := NULL;
  col$n   number;
  tbl$o   varchar2(128);
  tbl$n   varchar2(300);
  run$c   varchar2(3000) := NULL;
  rc$c    integer        := 0;
  ret$c   integer        := 0;
  del$c   integer;
  cod$e   number;
  count$r number         := 0;
  i$c     number         := 0;
  cur1$c  cur_t;
  cur2$c  cur_t;
  cur3$c  cur_t;
  ind     row_t;

begin
  dbms_application_info.set_module( 'mview.create_indexes', 'check' );

  -- If table exists in control table
  if tablename is not NULL then
    select count(1) into count$r from mviews where table_name = upper( tablename );
    if count$r = 0 then
      run$c := 'Control table has no data: ' || tablename || ': ' || SQLERRM(SQLCODE);
      plog.error( run$c );
      raise_application_error( -20101, run$c, true );
    end if;
  end if;

  dbms_application_info.set_module( 'mview.create_indexes', 'start' );

  if tablespace is not NULL then
    tbl$c:=' TABLESPACE ' || tablespace;
  end if;

  -- Count records to proceed
  run$c := 'select count(1)
              from mviews cm, all_indexes@' || mview$dblink || ' uin
             where     uin.owner = upper(substr(cm.table_name, 1, instr(cm.table_name,''.'') - 1))
                   and uin.table_name = upper(substr(cm.table_name, instr(cm.table_name,''.'') + 1))
                   and lower(cm.table_name) = case
                                              when :t is NULL then lower(cm.table_name)
                                              else lower(:t)
                                              end
                   and nvl2(cm.refresh_group, lower(cm.refresh_group), ''1'') =
                         case
                         when :r is NULL then nvl2(cm.refresh_group,lower(cm.refresh_group), ''1'')
                         else lower(:r)
                         end
                   and uin.status != ''DISABLED''
                   and uin.index_type = ''NORMAL''
                   and not exists ( select 1 from mviews_exclude_idx ci
                                            where ci.table_name = cm.table_name
                                                  and ci.index_name = uin.index_name )
                   and (not exists (select 1 from all_constraints@' || mview$dblink || ' uco
                                            where uco.table_name = uin.table_name
                                                  and uco.owner = uin.owner
                                                  and uco.index_name = uin.index_name
                                                  and uco.constraint_type = ''P''
                                                  and uco.status = ''ENABLED'')
                         or cm.mview_name is NULL)';

  open cur1$c for run$c using tablename, tablename, refreshgroup, refreshgroup;

  loop
    fetch cur1$c into count$r;
    exit when cur1$c%notfound;
  end loop;
  close cur1$c;

  run$c := 'select cm.table_name, cm.mview_name, cm.refresh_group, uin.index_name,
                   case
                   when uin.uniqueness = ''UNIQUE'' then uin.uniqueness
                   else ''''
                   end as uniq
              from mviews cm, all_indexes@' || mview$dblink || ' uin
             where     uin.owner = upper(substr(cm.table_name, 1, instr(cm.table_name,''.'') - 1))
                   and uin.table_name = upper(substr(cm.table_name, instr(cm.table_name,''.'') + 1))
                   and lower(cm.table_name) = case
                                              when :t is NULL then lower(cm.table_name)
                                              else lower(:t)
                                              end
                   and nvl2(cm.refresh_group, lower(cm.refresh_group), ''1'') =
                         case
                         when :r is NULL then nvl2(cm.refresh_group,lower(cm.refresh_group), ''1'')
                         else lower(:r)
                         end
                   and uin.status != ''DISABLED''
                   and uin.index_type = ''NORMAL''
                   and not exists ( select 1 from mviews_exclude_idx ci
                                            where ci.table_name = cm.table_name
                                                  and ci.index_name = uin.index_name )
                   and (not exists (select 1 from all_constraints@' || mview$dblink || ' uco
                                            where uco.table_name = uin.table_name
                                                  and uco.owner = uin.owner
                                                  and uco.index_name = uin.index_name
                                                  and uco.constraint_type = ''P''
                                                  and uco.status = ''ENABLED'')
                         or cm.mview_name is NULL)
             order by cm.process_order';

  open cur1$c for run$c using tablename, tablename, refreshgroup, refreshgroup;

  -- For all indexes except PK
  loop
    begin
      fetch cur1$c into ind;
    exception when others then
      plog.debug( 'Fetch cur1$c ' || SQLERRM(SQLCODE) );
      exit;
    end;
    exit when cur1$c%notfound;

    i$c := cur1$c%rowcount;
    dbms_application_info.set_action( i$c || '/' || count$r );

    -- Check index existence
    select count(1) into rc$c from user_indexes
     where index_name = ind.index_name;

    -- Get owner and table names
    tbl$o := mview_base.get_owner_name(ind.table_name);
    tbl$n := mview_base.get_table_name(ind.table_name);

    -- Remove materialized view from refresh group while building indexes
    del$c := 0;
    if ind.refresh_group is not NULL then
      begin
        del_from_rf_group( ind.mview_name, ind.refresh_group );
        del$c := 1;
      exception when OTHERS then
        ret$c := ret$c + 1;
        cod$e := SQLCODE;
        plog.error( 'Error temporary deleting matview ' || ind.mview_name || ' from refresh group ' ||
                     ind.refresh_group || ': ' || SQLERRM(SQLCODE) );
      end;
    end if;

    if drop_before_create = true then
      -- Удалить, если индекс существует
      if rc$c > 0 then
        begin
          run$c := 'drop index ' || ind.index_name;
          plog.debug( run$c );
          execute immediate run$c;
          plog.info( 'Index ' || ind.index_name || ' on table ' || nvl(ind.mview_name,ind.table_name) || ' droped' ); 
          rc$c := 0;
        exception when others then
          ret$c := ret$c + 1;
          cod$e := SQLCODE;
          plog.error( 'Error deleting index '  || ind.index_name || ' on table ' 
                       || nvl(ind.mview_name,ind.table_name) || SQLERRM(SQLCODE) );
        end;
      end if;
    end if;

    if rc$c = 0 then
      -- Get all fields
      run$c := 'select uc.column_name, uc.column_position
                  from all_ind_columns@' || mview$dblink || ' uc
                  where uc.index_owner = upper(:o)
                        and uc.index_name = :i
                        and upper(uc.table_name) = upper(:t)
                  order by uc.column_position';
      plog.debug ( run$c || ' :o=' || tbl$o || ' :i=' || ind.index_name || ' :t=' || tbl$n );
      items$c:='';
      open cur2$c for run$c using tbl$o, ind.index_name, tbl$n;
      loop
        begin
          fetch cur2$c into col$c, col$n;
        exception when others then
          plog.debug( 'Fetch cur2$c ' || SQLERRM(SQLCODE) );
          exit;
        end;

        exit when cur2$c%notfound;
        -- Column name may be reserved
        begin
          run$c := 'select column_expression
                      from all_ind_expressions@' || mview$dblink || '
                     where index_owner = upper(:o)
                           and index_name = :i
                           and column_position = :c';
          plog.debug( run$c || ' :o=' || tbl$o || ' :i=' || ind.index_name || ' :c=' || col$n  );
          open cur3$c for run$c using tbl$o, ind.index_name, col$n;
          fetch cur3$c into col$c;
          close cur3$c;
          --if col$e is not NULL then
          --  col$c := col$e;
          --end if;
        exception
          when OTHERS then
           plog.debug( 'Fetch cur$3 ' || SQLERRM(SQLCODE) );
        end;
        items$c := items$c || ',' || col$c;
      end loop;
      close cur2$c;

      -- Create index
      items$c := substr( items$c, 2 );
      begin
        dbms_application_info.set_action( i$c || '/' || count$r || ': ' || ind.table_name );

        -- Sould be non-unique index to avoid refresh errors
        if ind.mview_name is not NULL then
           ind.uniq := '';
        end if;
        run$c := 'create ' || ind.uniq || ' index ' || ind.index_name || ' on ';
        --run$c := 'create index ' || ind.index_name || ' on ';
        if ind.mview_name is not NULL then
          run$c := run$c || ind.mview_name;
        else
          run$c := run$c || substr(ind.table_name, instr(ind.table_name,'.') + 1);
        end if;
        run$c := run$c || ' (' || items$c || ') ' || tbl$c;

        plog.debug( run$c );
        execute immediate run$c;
        plog.info( 'Index ' || ind.index_name || ' on table ' || nvl(ind.mview_name,ind.table_name) || ' created('
                   || i$c || ' of ' || count$r || ')' );
      exception when others then
        ret$c := ret$c + 1;
        cod$e := SQLCODE;
        plog.error( 'Error creating index '  || ind.index_name || ' on table ' 
                     || nvl(ind.mview_name,ind.table_name) || ' :' || SQLERRM(SQLCODE) );
      end;
    end if;

    -- Restore materialized view into refresh group
    if del$c > 0 then
      begin
        add_to_rf_group( ind.mview_name, ind.refresh_group );
      exception when OTHERS then
        ret$c := ret$c + 1;
        cod$e := SQLCODE;
        plog.error( 'Error restoring matview ' || ind.mview_name || ' into refresh group ' ||
                     ind.refresh_group || ': ' || SQLERRM(SQLCODE) );
      end;
    end if;

  end loop;

  close cur1$c;

  dbms_application_info.set_module( 'mview.create_indexes', 'stop' );

  if ret$c > 0 then
    raise_application_error( -20101, 'There are '||ret$c||' errors :' || SQLERRM(cod$e), true );
  end if;

end;

-- Create sequences according to source database
procedure create_sequences as
  type cur_t is ref cursor;
  type row_t is record (
    sequence_name    user_sequences.sequence_name%type,
    last_number      user_sequences.last_number%type,
    increment_by     user_sequences.increment_by%type,
    min_value        user_sequences.min_value%type,
    cache_size       user_sequences.cache_size%type
  );

  run$c   varchar2(3000) := NULL;
  ret$c   integer        := 0;
  cod$e   number;
  count$r number         := 0;
  i$c     number         := 0;
  cur$c   cur_t;
  rec     row_t;

begin
  dbms_application_info.set_module( 'mview.create_sequences', 'start' );

  run$c := 'select count(1) from user_sequences@' || mview$dblink || ' seq
             where lower(seq.sequence_name) in
                     (select distinct  lower(substr(w1.x, instr(w1.x,''('',-1)+1)) y from
                       (select w.*, substr(w.t, instr(w.t,'' '',-1)+1) x from
                         (select us.*, substr(text,0, instr(lower(text),''nextval'')-2) t
                            from user_source us
                           where lower(us.text) like ''%nextval%''
                         ) w
                       ) w1
                     )
                     and not exists (select 1 from user_sequences seql
                                      where seql.sequence_name=seq.sequence_name)';

  open cur$c for run$c;
  loop
    fetch cur$c into count$r;
    exit when cur$c%notfound;
  end loop;
  close cur$c;

  run$c := 'select sequence_name, last_number, increment_by, min_value, cache_size
              from user_sequences@' || mview$dblink || ' seq
             where lower(seq.sequence_name) in
                     (select distinct  lower(substr(w1.x, instr(w1.x,''('',-1)+1)) y from
                       (select w.*, substr(w.t, instr(w.t,'' '',-1)+1) x from
                         (select us.*, substr(text,0, instr(lower(text),''nextval'')-2) t
                            from user_source us
                           where lower(us.text) like ''%nextval%''
                         ) w
                       ) w1
                     )
                     and not exists (select 1 from user_sequences seql
                                     where seql.sequence_name=seq.sequence_name)';

  open cur$c for run$c;
  loop
    fetch cur$c into rec;
    exit when cur$c%notfound;

    i$c := cur$c%rowcount;
    dbms_application_info.set_action( i$c || '/' || count$r || ': ' || rec.sequence_name );

    run$c := 'CREATE SEQUENCE ' || rec.sequence_name ||
             ' START WITH ' || rec.last_number ||
             ' INCREMENT BY ' || rec.increment_by ||
             ' MINVALUE ' || rec.min_value ||
             ' CACHE 20' ||
             ' NOCYCLE NOORDER';
    begin
      plog.debug( run$c );
      execute immediate run$c;
      plog.info( 'Sequence ' || rec.sequence_name || ' created('
                   || i$c || ' of ' || count$r || ')' );
      exception when OTHERS then
        ret$c := ret$c + 1;
        cod$e := SQLCODE;
        plog.error( 'Error creating sequence ' || rec.sequence_name || ': ' || SQLERRM(SQLCODE) );
      end;
  end loop;
  close cur$c;
  commit;

  dbms_application_info.set_module( 'mview.create_sequences', 'stop' );

  if ret$c > 0 then
    raise_application_error( -20101, 'There are '||ret$c||' errors :' || SQLERRM(cod$e), true );
  end if;
end;

--
--  Check index correctness
function check_indexes( tablename  IN varchar2 ) return ret_chk_index_t pipelined as
  type cur_t is ref cursor;
  run$c   varchar2(3000) := NULL;
  cur$c   cur_t;
  rec$c   chk_index_t;

begin
  run$c := 'select table_name,index_name,index_type from all_indexes@' || mview$dblink || '
            where index_name in
              (select uin.index_name
                 from mviews cm, all_indexes@' || mview$dblink || ' uin
                where uin.owner = upper(substr(cm.table_name, 1, instr(cm.table_name,''.'') - 1))
                  and uin.table_name = upper(substr(cm.table_name, instr(cm.table_name,''.'') + 1))
                  and lower(cm.table_name) = case
                                             when :t is NULL then lower(cm.table_name)
                                             else lower(:t)
                                             end
                  and not exists ( select 1 from mviews_exclude_idx ci
                                           where ci.table_name = cm.table_name
                                            and ci.index_name = uin.index_name )
               minus
               select index_name from user_indexes
                where table_name in ( select substr(nvl(mview_name,table_name),
                                             instr(nvl(mview_name,table_name),''.'') + 1) table_name
                                        from mviews)
              )';

  open cur$c for run$c using tablename, tablename;

  loop
    fetch cur$c into rec$c;
    exit when cur$c%notfound;
    pipe row ( rec$c );
  end loop;

  close cur$c;

  return;
end;

--
-- Set handler for refresh jobs errors
procedure refresh_jobs_wrap( job IN integer ) as
  type cur_t is ref cursor;
  type row_t is record (
    job    user_jobs.job%type,
    what   user_jobs.what%type );

  run$c       varchar2(1024);
  new_what$c  varchar2(1024) := '';
  cur$c       cur_t;
  rec         row_t;

begin
  dbms_application_info.set_module( 'mview.refresh_jobs_wrap', 'start' );
  run$c := 'select job, what from user_jobs
             where what like :t
               and instr(what,chr(10)) = 0';
  if job is NOT NULL then
    run$c := run$c || ' and job = ' || job;
  end if;

  plog.debug( run$c );

  open cur$c for run$c
     using '%dbms_refresh.refresh%' || upper(mview_base.get_owner_name(NULL)) || '%';

  loop
    fetch cur$c into rec;
    exit when cur$c%notfound;

    dbms_application_info.set_action( rec.job );

    new_what$c :=
'declare
  fail number;
begin
   ' || rec.what || '
exception
   when OTHERS then
      begin
       plog.setlevel( plog.linfo );
       plog.error( ''Error refreshing group :'' || SQLERRM(SQLCODE) );
       select failures into fail from user_jobs where job='||rec.job||';
       if fail <= 10 then
         RAISE;
       end if;
      end;
end;
';
      begin
        dbms_job.what( rec.job, new_what$c );
        plog.info( 'Error handler is setted for job ' || rec.job );
        commit;
      exception when others then 
        plog.error( 'Error setting handler for job ' || rec.job || ': ' || SQLERRM(SQLCODE) );
        raise_application_error( -20101, run$c, true );
        rollback;
      end;
  end loop;
  close cur$c;
  dbms_application_info.set_module( 'mview.refresh_jobs_wrap', 'stop' );
end;

--
-- Unset handler for refresh jobs errors
procedure refresh_jobs_unwrap( job IN integer ) as
  type cur_t is ref cursor;
  type row_t is record (
    job    user_jobs.job%type,
    what   user_jobs.what%type );

  run$c       varchar2(1024);
  new_what$c  varchar2(1024) := '';
  beg$c       integer;
  end$c       integer;
  cur$c       cur_t;
  rec         row_t;

begin
  dbms_application_info.set_module( 'mview.refresh_jobs_unwrap', 'start' );

  run$c := 'select job, what from user_jobs
             where what like :t
               and instr(what,chr(10)) > 0';
  if job is NOT NULL then
    run$c := run$c || ' and job = ' || job;
  end if;

  plog.debug( run$c );

  open cur$c for run$c
     using '%dbms_refresh.refresh%' || upper(mview_base.get_owner_name(NULL)) || '%';

  loop
    fetch cur$c into rec;
    exit when cur$c%notfound;

    dbms_application_info.set_action( rec.job );

    beg$c := instr( rec.what, 'dbms_refresh.refresh' );
    end$c := instr( rec.what, ';', beg$c );

    new_what$c := substr( rec.what, beg$c, end$c - beg$c + 1 );
    begin
      dbms_job.what( rec.job, new_what$c );
      plog.info( 'Error handler unsetted for job ' || rec.job );
      commit;
    exception when others then 
      plog.error( 'Error unsetting handler for job ' || rec.job || ': ' || SQLERRM(SQLCODE) );
      raise_application_error( -20101, run$c, true );
      rollback;
    end;
  end loop;
  close cur$c;
  dbms_application_info.set_module( 'mview.refresh_jobs_unwrap', 'stop' );
end;

--
-- Constructor
begin
    -- Initialize plog
    plog.setlevel( plog.linfo );
end mview;
/
