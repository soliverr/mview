--
-- Create database link if it not exists
--

set define on
set verify off
set serveroutput on

define L_DB_LINK_NAME = &&ORA_DB_LINK_NAME

declare
  l$cnt integer := 0;
  l$sql varchar2(1024) := '
create database link &&L_DB_LINK_NAME
 connect to excellent
 identified by "&&ORA_PASSWORD"
 using ''billing''
';

begin
  select count(1) into l$cnt
    from sys.dba_db_links
   where db_link like '&&L_DB_LINK_NAME%'
         and owner = '&&ORA_SCHEMA_OWNER';

   if l$cnt = 0 then
     begin
       execute immediate l$sql;
       dbms_output.put_line( CHR(10) || 'I: Database link &&L_DB_LINK_NAME created' );
     end;
   else
       dbms_output.put_line( CHR(10) || 'W: Database link &&L_DB_LINK_NAME already exists' );
   end if;
end;
/

undefine L_DB_LINK_NAME
