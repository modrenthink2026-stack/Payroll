-- Full monthly imports need a bounded bulk-operation budget. Scope it to
-- these authenticated RPCs; ordinary requests retain their existing limits.
alter function public.payroll_raw_biometric(jsonb) set statement_timeout='60s';
alter function public.payroll_attendance_register(jsonb) set statement_timeout='60s';
notify pgrst, 'reload schema';
