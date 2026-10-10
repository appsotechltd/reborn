import type { Comment } from "./types";

export interface CommentThread {
  comment: Comment;
  replies: Comment[];
}

/**
 * Nests replies under their top-level comment (replies are one level deep).
 * Replies whose parent isn't loaded are shown as top-level so nothing is lost.
 */
export function threadComments(comments: Comment[]): CommentThread[] {
  const tops = new Map<string, CommentThread>();
  const out: CommentThread[] = [];
  for (const c of comments) {
    if (!c.parent_id) {
      const t = { comment: c, replies: [] };
      tops.set(c.id, t);
      out.push(t);
    }
  }
  for (const c of comments) {
    if (!c.parent_id) continue;
    const parent = tops.get(c.parent_id);
    if (parent) parent.replies.push(c);
    else out.push({ comment: c, replies: [] });
  }
  return out;
}
