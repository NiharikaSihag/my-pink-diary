CREATE POLICY "owner uploads blog images" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'blog-images' AND public.is_owner());
CREATE POLICY "owner reads blog images" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'blog-images' AND public.is_owner());
CREATE POLICY "owner updates blog images" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'blog-images' AND public.is_owner());
CREATE POLICY "owner deletes blog images" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'blog-images' AND public.is_owner());