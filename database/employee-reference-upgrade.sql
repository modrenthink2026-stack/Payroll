-- Additive employee reference: independent of imported codes, biometric IDs and logins.
-- Identity allocation is atomic; gaps are normal after failed/rolled-back inserts.
alter table public.payroll_staff add column employee_number bigint generated always as identity;
alter table public.payroll_staff add constraint payroll_staff_employee_number_key unique(employee_number);
alter table public.payroll_staff add column employee_ref text generated always as
 ('EMP-' || lpad(employee_number::text,greatest(6,length(employee_number::text)),'0')) stored not null;
alter table public.payroll_staff add constraint payroll_staff_employee_ref_key unique(employee_ref);
create function payroll_private.keep_employee_number() returns trigger language plpgsql set search_path='' as $$
begin
 if new.employee_number is distinct from old.employee_number then
  raise exception 'Employee reference cannot be changed';
 end if;
 return new;
end$$;
revoke all on function payroll_private.keep_employee_number() from public,anon,authenticated;
create trigger payroll_staff_employee_number before update of employee_number on public.payroll_staff
 for each row execute function payroll_private.keep_employee_number();
notify pgrst,'reload schema';
