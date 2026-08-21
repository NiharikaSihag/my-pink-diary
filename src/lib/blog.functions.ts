import { createServerFn } from "@tanstack/react-start";
import { notFound } from "@tanstack/react-router";

export type PostCard = {
  id: string;
  title: string;
  slug: string;
  excerpt: string | null;
  featured_image: string | null;
  published_at: string | null;
  category: { name: string; slug: string } | null;
  like_count: number;
  comment_count: number;
};

export type PublicProfile = {
  display_name: string;
  username: string | null;
  bio: string | null;
  profile_image: string | null;
  location: string | null;
  birthday: string | null;
  interests: string[];
  favorite_things: string[];
  social_links: Record<string, string>;
  gallery_images: string[];
  post_count: number;
};

type RawPost = {
  id: string;
  title: string;
  slug: string;
  excerpt: string | null;
  featured_image: string | null;
  published_at: string | null;
  categories: { name: string; slug: string } | null;
  likes: { count: number }[];
  comments: { count: number }[];
};

const CARD_SELECT =
  "id,title,slug,excerpt,featured_image,published_at,categories(name,slug),likes(count),comments(count)";

function toCard(row: RawPost): PostCard {
  return {
    id: row.id,
    title: row.title,
    slug: row.slug,
    excerpt: row.excerpt,
    featured_image: row.featured_image,
    published_at: row.published_at,
    category: row.categories,
    like_count: row.likes?.[0]?.count ?? 0,
    comment_count: row.comments?.[0]?.count ?? 0,
  };
}

export const listPosts = createServerFn({ method: "GET" })
  .inputValidator(
    (input?: {
      search?: string;
      category?: string;
      sort?: "newest" | "oldest";
      page?: number;
      pageSize?: number;
    }) => input ?? {},
  )
  .handler(async ({ data }) => {
    const { createPublicClient } = await import("./supabase-public.server");
    const supabase = createPublicClient();
    const pageSize = Math.min(data.pageSize ?? 9, 24);
    const page = Math.max(data.page ?? 1, 1);
    const from = (page - 1) * pageSize;

    let query = supabase
      .from("posts")
      .select(CARD_SELECT, { count: "exact" })
      .eq("status", "published")
      .order("published_at", { ascending: data.sort === "oldest" })
      .range(from, from + pageSize - 1);

    if (data.search?.trim()) {
      const term = data.search.trim().replace(/[%,()]/g, "").slice(0, 80);
      query = query.or(`title.ilike.%${term}%,excerpt.ilike.%${term}%,content.ilike.%${term}%`);
    }
    if (data.category && data.category !== "all") {
      const { data: cat } = await supabase
        .from("categories")
        .select("id")
        .eq("slug", data.category)
        .maybeSingle();
      query = query.eq("category_id", cat?.id ?? "00000000-0000-0000-0000-000000000000");
    }

    const { data: rows, count, error } = await query;
    if (error) return { posts: [] as PostCard[], total: 0, error: "Could not load posts right now." };
    return {
      posts: ((rows ?? []) as unknown as RawPost[]).map(toCard),
      total: count ?? 0,
      error: null as string | null,
    };
  });

export const listCategories = createServerFn({ method: "GET" }).handler(async () => {
  const { createPublicClient } = await import("./supabase-public.server");
  const supabase = createPublicClient();
  const { data } = await supabase.from("categories").select("id,name,slug").order("name");
  return data ?? [];
});

export const getPostBySlug = createServerFn({ method: "GET" })
  .inputValidator((input: { slug: string }) => ({ slug: String(input.slug).slice(0, 120) }))
  .handler(async ({ data }) => {
    const { createPublicClient } = await import("./supabase-public.server");
    const supabase = createPublicClient();

    const { data: post } = await supabase
      .from("posts")
      .select(
        "id,title,slug,excerpt,content,featured_image,published_at,categories(name,slug),post_images(image_url,caption,sort_order),post_tags(tags(name,slug))",
      )
      .eq("slug", data.slug)
      .eq("status", "published")
      .maybeSingle();

    if (!post) throw notFound();

    const [{ count: likeCount }, { data: profile }] = await Promise.all([
      supabase.from("likes").select("id", { count: "exact", head: true }).eq("post_id", post.id),
      supabase.from("profiles").select("display_name,profile_image").eq("is_owner", true).maybeSingle(),
    ]);

    const images = (post.post_images ?? []).slice().sort((a, b) => a.sort_order - b.sort_order);
    const tags = (post.post_tags ?? [])
      .map((t: { tags: { name: string; slug: string } | null }) => t.tags)
      .filter(Boolean) as { name: string; slug: string }[];

    return {
      post: {
        id: post.id,
        title: post.title,
        slug: post.slug,
        excerpt: post.excerpt,
        content: post.content,
        featured_image: post.featured_image,
        published_at: post.published_at,
        category: post.categories,
        images,
        tags,
      },
      likeCount: likeCount ?? 0,
      author: {
        display_name: profile?.display_name ?? "Me",
        profile_image: profile?.profile_image ?? null,
      },
    };
  });

export const getPublicProfile = createServerFn({ method: "GET" }).handler(async () => {
  const { createPublicClient } = await import("./supabase-public.server");
  const supabase = createPublicClient();

  const { data: profile } = await supabase
    .from("profiles")
    .select(
      "display_name,username,bio,profile_image,location,birthday,interests,favorite_things,social_links,gallery_images,visibility",
    )
    .eq("is_owner", true)
    .maybeSingle();

  const { count } = await supabase
    .from("posts")
    .select("id", { count: "exact", head: true })
    .eq("status", "published");

  if (!profile) return null;

  const visibility = (profile.visibility ?? {}) as Record<string, boolean>;
  const show = (field: string) => visibility[field] !== false;

  const result: PublicProfile = {
    display_name: profile.display_name,
    username: profile.username,
    bio: show("bio") ? profile.bio : null,
    profile_image: profile.profile_image,
    location: show("location") ? profile.location : null,
    birthday: visibility["birthday"] === true ? profile.birthday : null,
    interests: show("interests") ? (profile.interests ?? []) : [],
    favorite_things: show("favorite_things") ? (profile.favorite_things ?? []) : [],
    social_links: show("social_links")
      ? ((profile.social_links ?? {}) as Record<string, string>)
      : {},
    gallery_images: profile.gallery_images ?? [],
    post_count: count ?? 0,
  };
  return result;
});
