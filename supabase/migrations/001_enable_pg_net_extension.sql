-- Enable pg_net extension for making HTTP requests from database functions
-- This is required for trigger functions to call Edge Functions

create extension if not exists pg_net with schema extensions;

-- Grant necessary permissions to authenticated and anon roles
grant usage on schema extensions to postgres, anon, authenticated, service_role;