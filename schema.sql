-- ⚠️ النسخة الجديدة (متعددة المحلات). بتمسح الجداول القديمة (كانت تجريبية). شغّل الملف كله مرة واحدة.
drop table if exists order_items, orders, products, profiles, tenant_invites, super_admins, tenants cascade;
drop function if exists place_order(text,text,text,text,jsonb);

create table tenants(id uuid primary key default gen_random_uuid(), name text not null, slug text unique not null check(slug ~ '^[a-z0-9-]{2,40}$'),
  logo text, description text, owner_id uuid, subscription_status text not null default 'active' check(subscription_status in('active','suspended')),
  expires_at date, created_at timestamptz default now());
create table tenant_invites(tenant_id uuid primary key references tenants on delete cascade, code text unique not null);
create table profiles(id uuid primary key references auth.users on delete cascade, tenant_id uuid not null references tenants, created_at timestamptz default now());
create table super_admins(user_id uuid primary key references auth.users on delete cascade);
create table products(id uuid primary key default gen_random_uuid(), tenant_id uuid not null references tenants on delete cascade,
  name text not null, price numeric not null check(price>=0), stock int not null default 0 check(stock>=0), category text, image_url text, created_at timestamptz default now());
create table orders(id uuid primary key default gen_random_uuid(), tenant_id uuid not null references tenants on delete cascade, created_at timestamptz default now(),
  customer_name text not null, customer_phone text not null, customer_address text not null, note text, total_price numeric not null default 0,
  status text not null default 'جديد' check(status in('جديد','قيد التجهيز','تم التسليم','ملغي')));
create table order_items(id uuid primary key default gen_random_uuid(), order_id uuid not null references orders on delete cascade,
  product_id uuid, name text not null, quantity int not null, unit_price numeric not null);
create index on products(tenant_id); create index on orders(tenant_id,created_at);

create or replace function my_tenant() returns uuid language sql stable security definer set search_path=public as $$ select tenant_id from profiles where id=auth.uid() $$;
create or replace function is_super() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from super_admins where user_id=auth.uid()) $$;
create or replace function tenant_ok(tid uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from tenants where id=tid and subscription_status='active' and (expires_at is null or expires_at>=current_date)) $$;

alter table tenants enable row level security; alter table tenant_invites enable row level security; alter table profiles enable row level security;
alter table super_admins enable row level security; alter table products enable row level security; alter table orders enable row level security; alter table order_items enable row level security;

revoke all on tenants,tenant_invites,profiles,super_admins,products,orders,order_items from anon,authenticated;
grant select on tenants to anon,authenticated; grant update(name,logo,description) on tenants to authenticated;
grant select on profiles to authenticated;
grant select on products to anon,authenticated; grant insert,update,delete on products to authenticated;
grant select on orders to authenticated; grant update(status) on orders to authenticated;
grant select on order_items to authenticated;

create policy t_read on tenants for select using(true);
create policy t_upd on tenants for update to authenticated using(id=my_tenant()) with check(id=my_tenant());
create policy p_read on profiles for select to authenticated using(id=auth.uid());
create policy pr_read on products for select using(tenant_id=my_tenant() or tenant_ok(tenant_id));
create policy pr_all on products for all to authenticated using(tenant_id=my_tenant() and tenant_ok(tenant_id)) with check(tenant_id=my_tenant() and tenant_ok(tenant_id));
create policy o_read on orders for select to authenticated using(tenant_id=my_tenant());
create policy o_upd on orders for update to authenticated using(tenant_id=my_tenant()) with check(tenant_id=my_tenant());
create policy oi_read on order_items for select to authenticated using(exists(select 1 from orders o where o.id=order_id and o.tenant_id=my_tenant()));

-- صور المنتجات: كل محل يرفع في فولدر باسم الـ tenant بتاعه بس
insert into storage.buckets(id,name,public) values('product-images','product-images',true) on conflict do nothing;
drop policy if exists img_read on storage.objects; drop policy if exists img_ins on storage.objects; drop policy if exists img_upd on storage.objects; drop policy if exists img_del on storage.objects;
create policy img_read on storage.objects for select using(bucket_id='product-images');
create policy img_ins on storage.objects for insert to authenticated with check(bucket_id='product-images' and (storage.foldername(name))[1]=my_tenant()::text);
create policy img_upd on storage.objects for update to authenticated using(bucket_id='product-images' and (storage.foldername(name))[1]=my_tenant()::text);
create policy img_del on storage.objects for delete to authenticated using(bucket_id='product-images' and (storage.foldername(name))[1]=my_tenant()::text);

-- دوال آمنة
create or replace function create_tenant(p_name text,p_slug text) returns text language plpgsql security definer set search_path=public as $$
declare t uuid; c text:=substr(md5(random()::text||clock_timestamp()::text),1,8);
begin
  if not is_super() then raise exception 'غير مسموح'; end if;
  if p_slug !~ '^[a-z0-9-]{2,40}$' then raise exception 'الرابط: حروف إنجليزي صغيرة وأرقام وشرطة فقط'; end if;
  insert into tenants(name,slug) values(trim(p_name),p_slug) returning id into t;
  insert into tenant_invites values(t,c); return c;
end $$;
create or replace function set_status(p_id uuid,p_status text,p_expires date) returns void language plpgsql security definer set search_path=public as $$
begin if not is_super() then raise exception 'غير مسموح'; end if;
  update tenants set subscription_status=p_status, expires_at=p_expires where id=p_id; end $$;
create or replace function claim_tenant(p_code text) returns uuid language plpgsql security definer set search_path=public as $$
declare t uuid;
begin
  if auth.uid() is null then raise exception 'سجل دخول الأول'; end if;
  if exists(select 1 from profiles where id=auth.uid()) then raise exception 'الحساب مرتبط بمحل بالفعل'; end if;
  select tenant_id into t from tenant_invites where code=trim(p_code);
  if t is null then raise exception 'كود الدعوة غير صحيح'; end if;
  insert into profiles(id,tenant_id) values(auth.uid(),t);
  update tenants set owner_id=auth.uid() where id=t;
  delete from tenant_invites where tenant_id=t; return t;
end $$;
create or replace function super_stats() returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not is_super() then raise exception 'غير مسموح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'slug',t.slug,'status',t.subscription_status,'expires_at',t.expires_at,
    'code',(select code from tenant_invites i where i.tenant_id=t.id),
    'orders',(select count(*) from orders o where o.tenant_id=t.id),
    'sales',(select coalesce(sum(total_price),0) from orders o where o.tenant_id=t.id and o.status<>'ملغي')) order by t.created_at desc) from tenants t),'[]'::jsonb);
end $$;
create or replace function place_order(p_slug text,p_name text,p_phone text,p_address text,p_note text,p_items jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare tid uuid; it jsonb; pr products; q int; total numeric:=0; oid uuid; n int:=0;
begin
  select id into tid from tenants where slug=p_slug and tenant_ok(id);
  if tid is null then raise exception 'المحل غير متاح'; end if;
  if length(trim(p_name))<2 or length(trim(p_phone))<6 or length(trim(p_address))<3 then raise exception 'بيانات ناقصة'; end if;
  insert into orders(tenant_id,customer_name,customer_phone,customer_address,note) values(tid,trim(p_name),trim(p_phone),trim(p_address),p_note) returning id into oid;
  for it in select * from jsonb_array_elements(p_items) loop
    q:=(it->>'qty')::int;
    select * into pr from products where id=(it->>'id')::uuid and tenant_id=tid for update;
    if not found or q<=0 then raise exception 'صنف غير صحيح'; end if;
    if pr.stock<q then raise exception 'الكمية غير متاحة: %',pr.name; end if;
    update products set stock=stock-q where id=pr.id;
    insert into order_items(order_id,product_id,name,quantity,unit_price) values(oid,pr.id,pr.name,q,pr.price);
    total:=total+pr.price*q; n:=n+1;
  end loop;
  if n=0 then raise exception 'السلة فاضية'; end if;
  update orders set total_price=total where id=oid; return oid;
end $$;
grant execute on function place_order to anon,authenticated;
grant execute on function claim_tenant, create_tenant, set_status, super_stats to authenticated;

-- بعد التشغيل: خلّي إيميلك أدمن النظام (غيّر الإيميل) وشغّل السطر ده لوحده:
-- insert into super_admins select id from auth.users where email='YOUR_EMAIL';
