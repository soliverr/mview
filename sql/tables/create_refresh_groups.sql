--
-- Create table if it not exists
--
set define on
set verify off
set serveroutput on

define L_TABLE_NAME = REFRESH_GROUPS

define ORA_SCHEMA_OWNER = '&&MVIEW_BASE_SCHEMA_OWNER'
define ORA_TBSP_TBLS = '&&MVIEW_BASE_TBSP_TBLS'
define ORA_TBSP_INDX = '&&MVIEW_BASE_TBSP_INDX'

-- Создать таблицу, если она не существует
declare
  l$cnt integer := 0;
  l$sql varchar2(1024) := '
create table &&L_TABLE_NAME  (
  group_name   varchar2(64) constraint pk_ref_grp primary key,
  refresh_time varchar2(64) not null
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
     end;
   else
       dbms_output.put_line( CHR(10) || 'W: Table &&L_TABLE_NAME already exists' );
   end if;
end;
/

comment on table  "&&L_TABLE_NAME" is
'Refresh groups to maintain replication';

comment on column "&&L_TABLE_NAME".group_name is
'Name of refresh group';

comment on column "&&L_TABLE_NAME".group_name is
'Refresh interval';

undefine L_TABLE_NAME ORA_SCHEMA_OWNER ORA_TBSP_TBLS ORA_TBSP_INDX
