-- ROLES
CREATE TYPE public.app_role AS ENUM ('owner');

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.has_role(auth.uid(), 'owner'::public.app_role)
$$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

-- PROFILES
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE,
  is_owner boolean NOT NULL DEFAULT false,
  display_name text NOT NULL DEFAULT 'Me',
  username text UNIQUE,
  bio text,
  profile_image text,
  email text,
  location text,
  birthday date,
  interests text[] NOT NULL DEFAULT '{}',
  favorite_things text[] NOT NULL DEFAULT '{}',
  social_links jsonb NOT NULL DEFAULT '{}'::jsonb,
  gallery_images text[] NOT NULL DEFAULT '{}',
  visibility jsonb NOT NULL DEFAULT '{"bio":true,"location":true,"interests":true,"favorite_things":true,"social_links":true,"birthday":false,"email":false}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner reads profiles" ON public.profiles FOR SELECT TO authenticated USING (public.is_owner());
CREATE POLICY "owner updates profiles" ON public.profiles FOR UPDATE TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- first signup becomes owner and claims the singleton profile
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE role = 'owner'::public.app_role) THEN
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'owner'::public.app_role);
    UPDATE public.profiles SET user_id = NEW.id, email = NEW.email
      WHERE is_owner = true AND user_id IS NULL;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- CATEGORIES
CREATE TABLE public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.categories TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.categories TO authenticated;
GRANT ALL ON public.categories TO service_role;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "categories public read" ON public.categories FOR SELECT USING (true);
CREATE POLICY "owner manages categories" ON public.categories FOR ALL TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());

-- TAGS
CREATE TABLE public.tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.tags TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tags TO authenticated;
GRANT ALL ON public.tags TO service_role;
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tags public read" ON public.tags FOR SELECT USING (true);
CREATE POLICY "owner manages tags" ON public.tags FOR ALL TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());

-- POSTS
CREATE TABLE public.posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title text NOT NULL,
  slug text NOT NULL UNIQUE,
  excerpt text,
  content text NOT NULL DEFAULT '',
  featured_image text,
  category_id uuid REFERENCES public.categories(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX posts_status_published_at_idx ON public.posts (status, published_at DESC);
CREATE INDEX posts_category_idx ON public.posts (category_id);
GRANT SELECT ON public.posts TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.posts TO authenticated;
GRANT ALL ON public.posts TO service_role;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "published posts public read" ON public.posts FOR SELECT USING (status = 'published');
CREATE POLICY "owner reads all posts" ON public.posts FOR SELECT TO authenticated USING (public.is_owner());
CREATE POLICY "owner manages posts" ON public.posts FOR ALL TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());
CREATE TRIGGER posts_updated_at BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- POST IMAGES
CREATE TABLE public.post_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  caption text,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX post_images_post_idx ON public.post_images (post_id, sort_order);
GRANT SELECT ON public.post_images TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.post_images TO authenticated;
GRANT ALL ON public.post_images TO service_role;
ALTER TABLE public.post_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY "post images public read" ON public.post_images FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.status = 'published')
);
CREATE POLICY "owner manages post images" ON public.post_images FOR ALL TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());

-- POST TAGS
CREATE TABLE public.post_tags (
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, tag_id)
);
GRANT SELECT ON public.post_tags TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.post_tags TO authenticated;
GRANT ALL ON public.post_tags TO service_role;
ALTER TABLE public.post_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "post tags public read" ON public.post_tags FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.status = 'published')
);
CREATE POLICY "owner manages post tags" ON public.post_tags FOR ALL TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());

-- LIKES
CREATE TABLE public.likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  visitor_identifier text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, visitor_identifier)
);
CREATE INDEX likes_post_idx ON public.likes (post_id);
GRANT SELECT, INSERT, DELETE ON public.likes TO anon;
GRANT SELECT, INSERT, DELETE ON public.likes TO authenticated;
GRANT ALL ON public.likes TO service_role;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "likes public read" ON public.likes FOR SELECT USING (true);
CREATE POLICY "anyone can like published posts" ON public.likes FOR INSERT WITH CHECK (
  char_length(visitor_identifier) BETWEEN 8 AND 100
  AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.status = 'published')
);
CREATE POLICY "anyone can unlike" ON public.likes FOR DELETE USING (true);

-- SITE SETTINGS
CREATE TABLE public.site_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moderate_comments boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.site_settings TO anon;
GRANT SELECT, UPDATE ON public.site_settings TO authenticated;
GRANT ALL ON public.site_settings TO service_role;
ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings public read" ON public.site_settings FOR SELECT USING (true);
CREATE POLICY "owner updates settings" ON public.site_settings FOR UPDATE TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());
INSERT INTO public.site_settings (moderate_comments) VALUES (false);

-- COMMENTS
CREATE TABLE public.comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  commenter_name text NOT NULL,
  commenter_email text,
  content text NOT NULL,
  status text NOT NULL DEFAULT 'approved' CHECK (status IN ('pending','approved','hidden')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_post_idx ON public.comments (post_id, created_at DESC);
GRANT INSERT ON public.comments TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.comments TO authenticated;
GRANT ALL ON public.comments TO service_role;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anyone can comment on published posts" ON public.comments FOR INSERT WITH CHECK (
  char_length(commenter_name) BETWEEN 1 AND 60
  AND char_length(content) BETWEEN 1 AND 2000
  AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_id AND p.status = 'published')
);
CREATE POLICY "owner reads comments" ON public.comments FOR SELECT TO authenticated USING (public.is_owner());
CREATE POLICY "owner moderates comments" ON public.comments FOR UPDATE TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());
CREATE POLICY "owner deletes comments" ON public.comments FOR DELETE TO authenticated USING (public.is_owner());

-- force status from settings on insert
CREATE OR REPLACE FUNCTION public.set_comment_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE moderate boolean;
BEGIN
  SELECT moderate_comments INTO moderate FROM public.site_settings LIMIT 1;
  IF coalesce(moderate, false) AND NOT public.is_owner() THEN
    NEW.status := 'pending';
  ELSIF NOT public.is_owner() THEN
    NEW.status := 'approved';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER comments_set_status BEFORE INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.set_comment_status();

-- public read of approved comments without exposing emails
CREATE VIEW public.public_comments
WITH (security_invoker = false) AS
  SELECT c.id, c.post_id, c.commenter_name, c.content, c.created_at
  FROM public.comments c
  JOIN public.posts p ON p.id = c.post_id
  WHERE c.status = 'approved' AND p.status = 'published';
GRANT SELECT ON public.public_comments TO anon, authenticated;

-- SEED
INSERT INTO public.categories (name, slug) VALUES
  ('Lifestyle','lifestyle'), ('Personal','personal'), ('Travel','travel'),
  ('Thoughts','thoughts'), ('Fashion','fashion'), ('Beauty','beauty'),
  ('Food','food'), ('Daily Life','daily-life'), ('Other','other');

INSERT INTO public.tags (name, slug) VALUES
  ('slow living','slow-living'), ('morning','morning'), ('journal','journal'), ('pink','pink');

INSERT INTO public.profiles (is_owner, display_name, username, bio, profile_image, location, interests, favorite_things, social_links, gallery_images)
VALUES (
  true, 'Niharika', 'niharika',
  'Hi, I''m so happy you''re here ♡ I write about small beautiful moments, slow mornings, the books I''m loving and the little thoughts I collect along the way. This is my digital diary — come in, sit down, grab a cup of tea.',
  '/images/profile.jpg', 'Somewhere soft & sunny',
  ARRAY['journaling','film photography','baking','poetry','long walks'],
  ARRAY['peonies','iced matcha','clean bed sheets','rainy afternoons','handwritten letters'],
  '{"instagram":"https://instagram.com","pinterest":"https://pinterest.com","x":"https://x.com"}'::jsonb,
  ARRAY['/images/seed-diary.jpg','/images/seed-cafe.jpg','/images/seed-travel.jpg']
);

INSERT INTO public.posts (author_id, title, slug, excerpt, featured_image, category_id, status, published_at, content)
SELECT p.id, v.title, v.slug, v.excerpt, v.img, c.id, 'published', v.pub, v.content
FROM (VALUES
  ('Slow mornings & the art of doing nothing','slow-mornings-and-the-art-of-doing-nothing',
   'On learning that a morning does not have to be productive to be beautiful.',
   '/images/seed-diary.jpg','lifestyle', now() - interval '2 days',
   '<p>There is a particular kind of quiet that only exists before the world wakes up. I have started guarding it like something precious.</p><h2>The ritual</h2><p>First the kettle. Then the window, opened just enough to let the morning in. I write three pages in my diary — never anything clever, mostly lists of things I noticed.</p><blockquote>A morning does not have to be productive to be beautiful.</blockquote><p>I used to wake up already behind. Now I wake up <strong>early on purpose</strong>, not to do more, but to have more time doing very little.</p><ul><li>Tea before phone</li><li>Three pages, always</li><li>One flower on the desk</li></ul><p>If you are reading this on a slow morning of your own — hello. I hope your tea is still warm. ♡</p>'),
  ('A soft little café day in the city','a-soft-little-cafe-day-in-the-city',
   'Matcha, a new notebook, and an afternoon that felt like a film scene.',
   '/images/seed-cafe.jpg','daily-life', now() - interval '5 days',
   '<p>I took myself on a date. Just me, a notebook I did not need, and the prettiest iced matcha in the city.</p><h2>What I ordered</h2><p>An iced matcha with vanilla, a strawberry pastry, and an extra hour of sitting by the window doing absolutely nothing but watching people pass.</p><p><em>Some days are not stories. Some days are just soft.</em></p><h2>What I wrote down</h2><ul><li>The barista drew a heart in the foam</li><li>Someone left a paperback on the windowsill</li><li>The light at 4pm is the best light</li></ul><p>I came home with pink cheeks and a full heart, which is really all I wanted.</p>'),
  ('Pink streets & borrowed roses','pink-streets-and-borrowed-roses',
   'A little travel diary from the prettiest street I have ever walked down.',
   '/images/seed-travel.jpg','travel', now() - interval '9 days',
   '<p>I found a street where every house was a different shade of blush, and roses grew out of the walls like the whole town was in love.</p><h2>Getting lost on purpose</h2><p>I did not use a map once. I turned wherever the flowers were.</p><blockquote>Travel does not have to be far. It only has to be new.</blockquote><p>I collected: two petals, one very good espresso, a postcard I never sent, and the sound of someone practising piano through an open window.</p><p>I will go back. I already know I will.</p>')
) AS v(title, slug, excerpt, img, cat, pub, content)
JOIN public.categories c ON c.slug = v.cat
JOIN public.profiles p ON p.is_owner = true;

INSERT INTO public.post_images (post_id, image_url, caption, sort_order)
SELECT id, '/images/seed-cafe.jpg', 'Afternoon light, exactly as I found it ✨', 1 FROM public.posts WHERE slug = 'slow-mornings-and-the-art-of-doing-nothing';

INSERT INTO public.post_tags (post_id, tag_id)
SELECT p.id, t.id FROM public.posts p JOIN public.tags t ON t.slug IN ('slow-living','morning','journal')
WHERE p.slug = 'slow-mornings-and-the-art-of-doing-nothing';

INSERT INTO public.comments (post_id, commenter_name, content, status)
SELECT id, 'Aditi', 'This felt like a hug. Reading it with my own cup of tea ♡', 'approved' FROM public.posts WHERE slug = 'slow-mornings-and-the-art-of-doing-nothing';
INSERT INTO public.comments (post_id, commenter_name, content, status)
SELECT id, 'Maya', 'Okay I need to find this café immediately!!', 'approved' FROM public.posts WHERE slug = 'a-soft-little-cafe-day-in-the-city';

INSERT INTO public.likes (post_id, visitor_identifier)
SELECT p.id, 'seed-visitor-' || g FROM public.posts p, generate_series(1,7) g WHERE p.slug = 'slow-mornings-and-the-art-of-doing-nothing';
INSERT INTO public.likes (post_id, visitor_identifier)
SELECT p.id, 'seed-visitor-' || g FROM public.posts p, generate_series(1,4) g WHERE p.slug = 'a-soft-little-cafe-day-in-the-city';