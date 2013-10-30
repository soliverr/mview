--
-- Public procedure to refresh materialized views
--

create or replace procedure mview_refresh as
begin
  mview.refresh_all;
end mview_refresh;
/

