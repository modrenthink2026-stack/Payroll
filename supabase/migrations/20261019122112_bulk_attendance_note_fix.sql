-- Safe for both the corrected fresh migration and the original deployed definition.
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.bulk_attendance(jsonb)'::regprocedure);
 if strpos(src,'else '' · ''||j->>''note'' end')>0 then
  execute replace(src,'else '' · ''||j->>''note'' end','else '' · ''||(j->>''note'') end');
 elsif strpos(src,'else '' · ''||(j->>''note'') end')=0 then raise exception 'Attendance note function changed; review required';end if;
end $patch$;
