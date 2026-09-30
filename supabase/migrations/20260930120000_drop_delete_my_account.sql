-- Account deletion moved to the delete-account Edge Function, which also revokes Sign in with Apple.
drop function if exists public.delete_my_account();
