-- شغّل الملف ده كله في Supabase > SQL Editor
create table products(
  id uuid primary key default gen_random_uuid(),
  name text not null, price numeric not null check(price>=0),
  stock int not null default 0 check(stock>=0),
  category text, emoji text, created_at timestamptz default now());
create table orders(
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  customer_name text not null, phone text not null, address text not null, note text,
  items jsonb not null, total numeric not null, status text not null default 'جديد');

alter table products enable row level security;
alter table orders enable row level security;
-- الكل يشوف المنتجات، والأدمن (المسجل دخول) بس يعدّل
create policy "read products" on products for select using (true);
create policy "admin products" on products for all to authenticated using (true) with check (true);
-- الأدمن بس يشوف ويعدّل الطلبات. الزبون بيبعت الطلب من خلال الدالة تحت بس
create policy "admin orders" on orders for all to authenticated using (true) with check (true);

-- إنشاء الطلب: السعر بيتحسب من السيرفر والمخزون بينقص تلقائي
create or replace function place_order(p_name text,p_phone text,p_address text,p_note text,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare it jsonb; pr products; total numeric:=0; lines jsonb:='[]'; oid uuid;
begin
  if length(trim(p_name))<2 or length(trim(p_phone))<6 or length(trim(p_address))<3 then raise exception 'بيانات ناقصة'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from products where id=(it->>'id')::uuid for update;
    if not found or (it->>'qty')::int<=0 then raise exception 'صنف غير صحيح'; end if;
    if pr.stock<(it->>'qty')::int then raise exception 'الكمية غير متاحة: %',pr.name; end if;
    update products set stock=stock-(it->>'qty')::int where id=pr.id;
    total:=total+pr.price*(it->>'qty')::int;
    lines:=lines||jsonb_build_object('name',pr.name,'price',pr.price,'qty',(it->>'qty')::int);
  end loop;
  if jsonb_array_length(lines)=0 then raise exception 'السلة فاضية'; end if;
  insert into orders(customer_name,phone,address,note,items,total)
  values(trim(p_name),trim(p_phone),trim(p_address),p_note,lines,total) returning id into oid;
  return oid;
end $$;
grant execute on function place_order to anon, authenticated;
