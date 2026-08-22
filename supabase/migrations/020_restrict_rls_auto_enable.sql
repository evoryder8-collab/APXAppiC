-- The event trigger runs internally as its postgres owner. API roles never need
-- direct access to the SECURITY DEFINER helper that powers it.
revoke all on function public.rls_auto_enable() from public;
revoke all on function public.rls_auto_enable() from anon;
revoke all on function public.rls_auto_enable() from authenticated;
