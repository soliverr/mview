--
-- Create table if it not exists
--

set define on
set verify off
set serveroutput on

define L_TABLE_NAME = MVIEWS

define ORA_SCHEMA_OWNER = '&&MVIEW_BASE_SCHEMA_OWNER'
define ORA_TBSP_TBLS = '&&MVIEW_BASE_TBSP_TBLS'
define ORA_TBSP_INDX = '&&MVIEW_BASE_TBSP_INDX'

declare
  l$cnt integer := 0;
  l$sql varchar2(1024) := '
create table &&L_TABLE_NAME  (
  table_name     varchar2(300) constraint pk_views primary key,
  mview_name     varchar2(300),
  refresh_group  constraint fk_mviews_rfgroup references refresh_groups( group_name ),
  process_order  integer,
  get_data       char(1) default ''Y''
)';

begin
  select count(1) into l$cnt
    from sys.all_tables
   where table_name = '&&L_TABLE_NAME'
     and owner = upper('&&ORA_SCHEMA_OWNER');

   if l$cnt = 0 then
     begin
       execute immediate l$sql || ' tablespace &&ORA_TBSP_TBLS';
       dbms_output.put_line( CHR(10) || 'I: Table &&L_TABLE_NAME created' );

       execute immediate '
       create index  i_mview_process on &&L_TABLE_NAME (
          process_order
       ) tablespace &&ORA_TBSP_INDX';
     end;
   else
       dbms_output.put_line( CHR(10) || 'W: Table &&L_TABLE_NAME already exists' );
   end if;
end;
/

comment on table  "&&L_TABLE_NAME" is
'Control table for ORADBA materialized view replication system';

comment on column "&&L_TABLE_NAME".table_name is
'Source table name in form of OWNER.TABLE_NAME';

comment on column "&&L_TABLE_NAME".mview_name is
'Target materialized view name in form of VIEW_NAME';

comment on column "&&L_TABLE_NAME".refresh_group is
'Refresh group for given materialized view';

comment on column "&&L_TABLE_NAME".process_order is
'Sort order to proceed';

comment on column "&&L_TABLE_NAME".get_data is
'Get rows (Y/N) for created tables';

undefine L_TABLE_NAME ORA_SCHEMA_OWNER ORA_TBSP_TBLS ORA_TBSP_INDX
