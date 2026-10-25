-- أصوات الساحرة الخاصة (للمرجع؛ تنطبق على مشروع Supabase "sp-game").
-- الصوت نفسه ما موجود بملفات اللعبة ولا بـ GitHub: محفوظ بجدول مقفول، والدالة تنطيه بس
-- للحسابات اللي بقائمة media_access وعليها رمز (PIN).
create table if not exists public.private_media (name text primary key, data text not null); -- ogg بصيغة base64
alter table public.private_media enable row level security; -- بدون policies = محد يقراه مباشرة
create table if not exists public.media_access (name text primary key); -- الاسم بحروف صغيرة
alter table public.media_access enable row level security;
revoke all on public.private_media, public.media_access from anon, authenticated;

-- witch_media(p_token) → {ok, media: {cackle: base64, music: base64}} أو {ok:false}
create or replace function public.witch_media(p_token uuid) returns json
language plpgsql security definer set search_path = '' as $$
declare
	who public.players;
begin
	select * into who from public.players where token = p_token;
	if not found or who.pin_hash is null
		or not exists (select 1 from public.media_access a where a.name = lower(who.name)) then
		return json_build_object('ok', false);
	end if;
	return json_build_object('ok', true, 'media', coalesce((select json_object_agg(m.name, m.data) from public.private_media m), '{}'::json));
end $$;
revoke all on function public.witch_media(uuid) from public;
grant execute on function public.witch_media(uuid) to anon, authenticated;

insert into public.media_access (name) values ('علي'), ('يوسف'), ('aljizani') on conflict do nothing;
