DROP VIEW IF EXISTS public.public_comments;

GRANT SELECT (id, post_id, commenter_name, content, created_at) ON public.comments TO anon;
CREATE POLICY "approved comments public read" ON public.comments FOR SELECT TO anon USING (
  status = 'approved'
  AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.status = 'published')
);

REVOKE ALL ON FUNCTION public.set_updated_at() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.set_comment_status() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role) FROM anon;
REVOKE ALL ON FUNCTION public.is_owner() FROM anon;