-- Enforce one request -> one work order at DB level.
-- Run this in Supabase SQL editor after resolving any existing duplicates.

create unique index if not exists ux_work_orders_request_id
on public.work_orders (request_id)
where request_id is not null;
