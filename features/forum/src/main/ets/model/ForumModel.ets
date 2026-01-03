export interface ApiResponse<T> {
  success: boolean;
  message?: string;
  data?: T;
}

export interface UserInfo {
  id: number;
  nickname: string;
  avatar_url: string;
  age?: number;
  weight?: number;
  health_tags?: string;
}

export interface ForumPost {
  id: number;
  title: string;
  content: string;
  images: string[];
  tags: string[]; // Changed to string[]
  type: number; // 0图文 1视频
  like_count: number;
  fav_count?: number; // 收藏数
  view_count: number;
  author_name: string;
  author_avatar: string;
  user_id: number;
  created_at?: string;
  is_liked?: number; // 1 or 0
  is_faved?: number;
}

export interface Comment {
  id: number;
  nickname: string;
  avatar_url: string;
  content: string;
  created_at: string;
}

export interface PostDetailData {
  post: ForumPost;
  comments: Comment[];
}

export interface ProfileData {
  info: UserInfo;
  works: ForumPost[];
  likes: ForumPost[];
  favs: ForumPost[];
}