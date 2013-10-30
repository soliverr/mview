--
-- Create table if it not exists
--
set define on
set verify off
set serveroutput on

define L_TABLE_NAME = MVIEWS_EXCLUDE_IDX

define ORA_SCHEMA_OWNER = '&&MVIEW_BASE_SCHEMA_OWNER'
define ORA_TBSP_TBLS = '&&MVIEW_BASE_TBSP_TBLS'
define ORA_TBSP_INDX = '&&MVIEW_BASE_TBSP_INDX'

-- Создать таблицу, если она не существует
declare
  l$cnt integer := 0;
  l$sql varchar2(1024) := '
create table &&L_TABLE_NAME  (
  table_name  constraint fk_mviews_table references mviews( table_name ) on delete cascade,
  index_name  varchar(300) not null
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
     execute immediate '
     create index i_mview_ex_tbl on mviews_exclude_idx (
         table_name
     ) tablespace &&ORA_TBSP_INDX';
     execute immediate '
     create index i_mview_ex_idx on mviews_exclude_idx (
         index_name
     ) tablespace &&ORA_TBSP_INDX';
     execute immediate '
     alter table &&L_TABLE_NAME add constraint mviews_exclude_uniq unique (
         table_name,
         index_name
     )';

   else
       dbms_output.put_line( CHR(10) || 'W: Table &&L_TABLE_NAME already exists' );
   end if;
end;
/

comment on table  "&&L_TABLE_NAME" is
'List of excluded source indexes: this indexes will not build on target';

comment on column "&&L_TABLE_NAME".table_name is
'Source table name in form OWNER.TABLE_NAME';

comment on column "&&L_TABLE_NAME".index_name is
'Source index name to exclude on target';

undefine L_TABLE_NAME ORA_SCHEMA_OWNER ORA_TBSP_TBLS ORA_TBSP_INDX
