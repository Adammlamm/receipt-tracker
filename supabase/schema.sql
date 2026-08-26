-- Receipt Tracker schema
-- Run this in the Supabase SQL editor (or `supabase db push`) after creating your project.

create extension if not exists "uuid-ossp";

create table if not exists people (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists receipts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  merchant text not null default 'Untitled receipt',
  date date not null default current_date,
  subtotal numeric(10,2) not null default 0,
  tax numeric(10,2) not null default 0,
  tip numeric(10,2) not null default 0,
  total numeric(10,2) not null default 0,
  tax_tip_method text not null default 'proportional' check (tax_tip_method in ('proportional','equal')),
  image_path text, -- path inside the "receipts" storage bucket
  created_at timestamptz not null default now()
);

create table if not exists receipt_items (
  id uuid primary key default uuid_generate_v4(),
  receipt_id uuid not null references receipts(id) on delete cascade,
  name text not null,
  price numeric(10,2) not null,
  category text not null default 'Food' check (category in ('Food','Drinks','Other')),
  created_at timestamptz not null default now()
);

create table if not exists item_splits (
  id uuid primary key default uuid_generate_v4(),
  item_id uuid not null references receipt_items(id) on delete cascade,
  person_id uuid not null references people(id) on delete cascade,
  unique (item_id, person_id)
);

create table if not exists payments (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  person_id uuid not null references people(id) on delete cascade,
  receipt_id uuid references receipts(id) on delete set null,
  amount numeric(10,2) not null,
  payment_date date not null default current_date,
  payment_method text not null default 'Other'
    check (payment_method in ('Venmo','Zelle','Apple Cash','Cash','PayPal','Other')),
  created_at timestamptz not null default now()
);

-- ---- Row Level Security: every row is scoped to the signed-in user ----

alter table people enable row level security;
alter table receipts enable row level security;
alter table receipt_items enable row level security;
alter table item_splits enable row level security;
alter table payments enable row level security;

create policy "people_owner" on people
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "receipts_owner" on receipts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "payments_owner" on payments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- receipt_items / item_splits don't have their own user_id, so check via the parent receipt/person
create policy "receipt_items_owner" on receipt_items
  for all using (
    exists (select 1 from receipts r where r.id = receipt_id and r.user_id = auth.uid())
  ) with check (
    exists (select 1 from receipts r where r.id = receipt_id and r.user_id = auth.uid())
  );

create policy "item_splits_owner" on item_splits
  for all using (
    exists (
      select 1 from receipt_items ri join receipts r on r.id = ri.receipt_id
      where ri.id = item_id and r.user_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from receipt_items ri join receipts r on r.id = ri.receipt_id
      where ri.id = item_id and r.user_id = auth.uid()
    )
  );

-- ---- Storage bucket for receipt photos ----
insert into storage.buckets (id, name, public)
  values ('receipts', 'receipts', false)
  on conflict (id) do nothing;

create policy "receipt_images_owner_select" on storage.objects
  for select using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "receipt_images_owner_insert" on storage.objects
  for insert with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "receipt_images_owner_delete" on storage.objects
  for delete using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
