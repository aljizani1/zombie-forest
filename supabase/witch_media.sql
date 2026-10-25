-- أصوات الساحرة الخاصة (للمرجع؛ تنطبق على مشروع Supabase "sp-game").
-- الصوت نفسه ما موجود بملفات اللعبة ولا بـ GitHub: محفوظ بجدول مقفول، والدالة تنطيه بس
-- للحسابات اللي بقائمة media_access وعليها رمز (PIN).
create table if not exists private_media (name text primary key, data text not null); -- ogg بصيغة base64
alter table private_media enable row level security; -- بدون policies = محد يقراه مباشرة
create table if not exists media_access (name text primary key); -- الاسم بحروف صغيرة
alter table media_access enable row level security;

-- witch_media(p_token) → {ok, media: {cackle: base64, music: base64}} أو {ok:false}
create or replace function witch_media(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
	who players;
begin
	select * into who from players where token::text = p_token;
	if who.name is null or who.pin_hash is null
		or not exists (select 1 from media_access a where a.name = lower(who.name)) then
		return jsonb_build_object('ok', false);
	end if;
	return jsonb_build_object('ok', true, 'media', coalesce((select jsonb_object_agg(name, data) from private_media), '{}'::jsonb));
end $$;
revoke all on function witch_media(text) from public;
grant execute on function witch_media(text) to anon, authenticated;
