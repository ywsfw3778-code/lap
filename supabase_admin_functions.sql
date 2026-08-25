-- ==============================================================================
-- Lab Members - Advanced Admin Functions & Policies (لوحة التحكم الإدارية)
-- ==============================================================================

-- 1. جدول الحظر وحالة المستخدمين الإدارية (User Moderation & Bans)
CREATE TABLE IF NOT EXISTS public.admin_user_moderation (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_banned BOOLEAN DEFAULT false,
  ban_reason TEXT DEFAULT '',
  banned_by UUID REFERENCES auth.users(id),
  banned_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.admin_user_moderation ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_user_moderation_read_all" ON public.admin_user_moderation;
CREATE POLICY "admin_user_moderation_read_all"
ON public.admin_user_moderation FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "admin_user_moderation_modify_admin" ON public.admin_user_moderation;
CREATE POLICY "admin_user_moderation_modify_admin"
ON public.admin_user_moderation FOR ALL TO authenticated
USING (
  lower(trim(coalesce(auth.jwt()->>'email', ''))) = 'ywsfw3778@gmail.com'
  OR coalesce((auth.jwt()->'user_metadata'->>'is_admin')::boolean, false) = true
  OR coalesce(auth.jwt()->'user_metadata'->>'role', '') = 'admin'
);

-- 2. جدول الإعلانات والتعميمات العامة (Broadcast Announcements)
CREATE TABLE IF NOT EXISTS public.admin_broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_name TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'warning', 'urgent', 'success')),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_broadcasts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_broadcasts_select_active" ON public.admin_broadcasts;
CREATE POLICY "admin_broadcasts_select_active"
ON public.admin_broadcasts FOR SELECT TO authenticated
USING (is_active = true);

DROP POLICY IF EXISTS "admin_broadcasts_all_admin" ON public.admin_broadcasts;
CREATE POLICY "admin_broadcasts_all_admin"
ON public.admin_broadcasts FOR ALL TO authenticated
USING (
  lower(trim(coalesce(auth.jwt()->>'email', ''))) = 'ywsfw3778@gmail.com'
  OR coalesce((auth.jwt()->'user_metadata'->>'is_admin')::boolean, false) = true
  OR coalesce(auth.jwt()->'user_metadata'->>'role', '') = 'admin'
);

-- 3. دالة التحقق من صلاحية الإدارة (Is Admin Assert Helper)
CREATE OR REPLACE FUNCTION public.assert_admin_caller()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  caller_email text;
  is_admin_flag boolean;
  role_str text;
begin
  caller_email := lower(trim(coalesce(auth.jwt()->>'email', '')));
  is_admin_flag := coalesce((auth.jwt()->'user_metadata'->>'is_admin')::boolean, false);
  role_str := lower(trim(coalesce(auth.jwt()->'user_metadata'->>'role', '')));

  IF caller_email <> 'ywsfw3778@gmail.com' AND NOT is_admin_flag AND role_str <> 'admin' THEN
    RAISE EXCEPTION 'Unauthorized: Only platform administrators can execute this function.';
  END IF;
  return caller_email;
end;
$$;

-- 4. دالة إحصائيات لوحة التحكم الشاملة (Dashboard Stats)
CREATE OR REPLACE FUNCTION public.admin_get_dashboard_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
  v_total_users integer;
  v_online_users integer;
  v_total_messages integer;
  v_total_friend_requests integer;
  v_total_voice_messages integer;
  v_total_image_messages integer;
  v_banned_users integer;
  v_stats json;
begin
  v_admin := public.assert_admin_caller();

  -- Total registered users
  SELECT count(*) INTO v_total_users FROM public.profiles;

  -- Active / Online users (seen in last 5 minutes)
  SELECT count(*) INTO v_online_users FROM public.profiles 
  WHERE last_seen_at >= (now() - interval '5 minutes');

  -- Total messages
  SELECT count(*) INTO v_total_messages FROM public.messages;

  -- Message types breakdown
  SELECT count(*) INTO v_total_voice_messages FROM public.messages 
  WHERE content LIKE '[voice]%' OR content LIKE '[audio]%';

  SELECT count(*) INTO v_total_image_messages FROM public.messages 
  WHERE content LIKE '[image]%';

  -- Total friend requests
  SELECT count(*) INTO v_total_friend_requests FROM public.friend_requests;

  -- Banned users
  SELECT count(*) INTO v_banned_users FROM public.admin_user_moderation 
  WHERE is_banned = true;

  v_stats := json_build_object(
    'total_users', coalesce(v_total_users, 0),
    'online_users', coalesce(v_online_users, 0),
    'total_messages', coalesce(v_total_messages, 0),
    'total_voice_messages', coalesce(v_total_voice_messages, 0),
    'total_image_messages', coalesce(v_total_image_messages, 0),
    'total_friend_requests', coalesce(v_total_friend_requests, 0),
    'banned_users', coalesce(v_banned_users, 0),
    'server_time', now()
  );

  return v_stats;
end;
$$;

-- 5. دالة جلب قائمة كل المستخدمين مع بياناتهم وحالات الحظر (Get All Users)
CREATE OR REPLACE FUNCTION public.admin_get_all_users()
RETURNS TABLE (
  id UUID,
  email TEXT,
  username TEXT,
  full_name TEXT,
  avatar_url TEXT,
  member_code INTEGER,
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  is_admin BOOLEAN,
  is_banned BOOLEAN,
  ban_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
begin
  v_admin := public.assert_admin_caller();

  RETURN QUERY
  SELECT 
    p.id,
    coalesce(p.email, u.email) as email,
    p.username,
    coalesce(p.full_name, p.username, 'User') as full_name,
    p.avatar_url,
    p.member_code,
    p.last_seen_at,
    u.created_at,
    (lower(coalesce(p.email, u.email, '')) = 'ywsfw3778@gmail.com' 
     OR coalesce((u.raw_user_meta_data->>'is_admin')::boolean, false) = true
     OR coalesce(u.raw_user_meta_data->>'role', '') = 'admin') as is_admin,
    coalesce(m.is_banned, false) as is_banned,
    coalesce(m.ban_reason, '') as ban_reason
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  LEFT JOIN public.admin_user_moderation m ON m.user_id = u.id
  ORDER BY coalesce(p.last_seen_at, u.created_at) DESC;
end;
$$;

-- 6. دالة حظر / فك حظر مستخدم (Ban/Unban User)
CREATE OR REPLACE FUNCTION public.admin_set_user_ban(
  target_user_id UUID,
  ban_status BOOLEAN,
  reason_text TEXT DEFAULT ''
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
begin
  v_admin := public.assert_admin_caller();

  INSERT INTO public.admin_user_moderation (user_id, is_banned, ban_reason, banned_by, banned_at, updated_at)
  VALUES (target_user_id, ban_status, reason_text, auth.uid(), now(), now())
  ON CONFLICT (user_id) DO UPDATE
  SET is_banned = excluded.is_banned,
      ban_reason = excluded.ban_reason,
      banned_by = auth.uid(),
      updated_at = now();

  RETURN true;
end;
$$;

-- 7. دالة تحديث كود العضوية والاسم والصورة للمستخدم من قبل الإدارة (Update Member Profile)
CREATE OR REPLACE FUNCTION public.admin_update_user_profile(
  target_user_id UUID,
  new_name TEXT,
  new_member_code INTEGER,
  new_avatar_url TEXT DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
begin
  v_admin := public.assert_admin_caller();

  UPDATE public.profiles
  SET full_name = coalesce(nullif(trim(new_name), ''), full_name),
      member_code = coalesce(new_member_code, member_code),
      avatar_url = CASE 
        WHEN new_avatar_url = '__REMOVE__' THEN NULL
        WHEN new_avatar_url IS NOT NULL THEN new_avatar_url
        ELSE avatar_url
      END
  WHERE id = target_user_id;

  RETURN true;
end;
$$;

-- 8. دالة إرسال تعميم / إعلان جماعي (Broadcast Announcement)
CREATE OR REPLACE FUNCTION public.admin_create_broadcast(
  p_title TEXT,
  p_content TEXT,
  p_type TEXT DEFAULT 'info'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
  v_sender_name text;
  v_broadcast_id UUID;
begin
  v_admin := public.assert_admin_caller();

  SELECT coalesce(full_name, username, 'الإدارة') INTO v_sender_name
  FROM public.profiles WHERE id = auth.uid();

  INSERT INTO public.admin_broadcasts (sender_id, sender_name, title, content, type)
  VALUES (auth.uid(), coalesce(v_sender_name, 'الإدارة'), p_title, p_content, p_type)
  RETURNING id INTO v_broadcast_id;

  RETURN v_broadcast_id;
end;
$$;

-- 9. دالة مسح كل الرسائل من السيرفر نهائياً (Purge All Messages)
CREATE OR REPLACE FUNCTION public.admin_purge_all_messages()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
begin
  v_admin := public.assert_admin_caller();
  TRUNCATE TABLE public.messages RESTART IDENTITY CASCADE;
  RETURN true;
end;
$$;

-- 10. دالة تعيين أو إلغاء رتبة المشرف لمستخدم (Set/Unset Admin Role)
CREATE OR REPLACE FUNCTION public.admin_set_user_admin(
  target_user_id UUID,
  is_admin_status BOOLEAN
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
  v_target_email text;
begin
  v_admin := public.assert_admin_caller();

  SELECT lower(coalesce(email, '')) INTO v_target_email
  FROM auth.users
  WHERE id = target_user_id;

  IF v_target_email = 'ywsfw3778@gmail.com' AND NOT is_admin_status THEN
    RAISE EXCEPTION 'Cannot demote the primary owner.';
  END IF;

  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    coalesce(raw_user_meta_data, '{}'::jsonb),
    '{is_admin}',
    to_jsonb(is_admin_status)
  )
  WHERE id = target_user_id;

  BEGIN
    UPDATE public.profiles
    SET is_admin = is_admin_status,
        updated_at = now()
    WHERE id = target_user_id;
  EXCEPTION WHEN undefined_column THEN
    NULL;
  END;

  RETURN true;
end;
$$;

-- 11. دالة حذف حساب مستخدم نهائياً بكافة بياناته (Delete User Completely)
CREATE OR REPLACE FUNCTION public.admin_delete_user(
  target_user_id UUID
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
declare
  v_admin text;
  v_target_email text;
begin
  v_admin := public.assert_admin_caller();

  SELECT lower(coalesce(email, '')) INTO v_target_email
  FROM auth.users
  WHERE id = target_user_id;

  IF v_target_email = 'ywsfw3778@gmail.com' THEN
    RAISE EXCEPTION 'Cannot delete the primary owner account.';
  END IF;

  -- حذف الرسائل المرتبطة
  DELETE FROM public.messages WHERE sender_id = target_user_id OR receiver_id = target_user_id;

  -- حذف طلبات الصداقة
  DELETE FROM public.friend_requests WHERE sender_id = target_user_id OR receiver_id = target_user_id;

  -- حذف سجلات الحظر والربط
  DELETE FROM public.admin_user_moderation WHERE user_id = target_user_id;
  DELETE FROM public.admin_message_blocks WHERE admin_id = target_user_id OR user_id = target_user_id;
  DELETE FROM public.user_identities WHERE user_id = target_user_id;

  -- حذف البروفايل
  DELETE FROM public.profiles WHERE id = target_user_id;

  -- حذف المستخدم من جدول المصادقة الأساسي
  DELETE FROM auth.users WHERE id = target_user_id;

  RETURN true;
end;
$$;

-- 12. منح صلاحيات الاستدعاء للمستخدمين المصادقين (Execute Grants)
GRANT EXECUTE ON FUNCTION public.assert_admin_caller() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_dashboard_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_all_users() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_ban(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_admin(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, TEXT, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_broadcast(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_purge_all_messages() TO authenticated;

-- تحديث سياسة الرسائل لتطبيق الحظر تلقائياً (Block banned users from inserting messages)
DROP POLICY IF EXISTS "messages_insert_self" ON public.messages;
CREATE POLICY "messages_insert_self"
ON public.messages
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = sender_id
  AND NOT EXISTS (
    SELECT 1 FROM public.admin_user_moderation aum
    WHERE aum.user_id = auth.uid() AND aum.is_banned = true
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.admin_message_blocks amb
    WHERE amb.admin_id = messages.receiver_id AND amb.user_id = auth.uid()
  )
);
