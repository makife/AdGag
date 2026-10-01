import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../domain/comment.dart";
import "../domain/comments_repository.dart";

final class CommentsRepositoryImpl implements CommentsRepository {
  CommentsRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  // The FK is named: comment_likes (0025) also links comments to profiles,
  // which makes a plain profiles(...) embed ambiguous (PGRST201).
  // comment_likes(user_id) holds only the signed-in user's own like (RLS).
  static const String _select = "*, profiles!comments_user_id_fkey(username, avatar_url), comment_likes(user_id)";

  @override
  Future<List<Comment>> fetchPage({required String adId, DateTime? before, int limit = 20}) async {
    supa.PostgrestFilterBuilder<List<Map<String, dynamic>>> query =
        _client.from("comments").select(_select).eq("ad_id", adId).isFilter("parent_id", null);

    if (before != null) {
      query = query.lt("created_at", before.toIso8601String());
    }

    final List<Map<String, dynamic>> rows = await query.order("created_at", ascending: false).limit(limit);
    return rows.map(Comment.fromRow).toList(growable: false);
  }

  @override
  Future<List<Comment>> fetchReplies(String parentId, {int limit = 50}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from("comments")
        .select(_select)
        .eq("parent_id", parentId)
        .order("created_at", ascending: true)
        .limit(limit);
    return rows.map(Comment.fromRow).toList(growable: false);
  }

  @override
  Future<Comment> create({required String adId, required String body, String? parentId}) async {
    try {
      final Map<String, dynamic> row = await _client.rpc<Map<String, dynamic>>(
        "create_comment",
        params: <String, dynamic>{"p_ad_id": adId, "p_body": body, "p_parent_id": parentId},
      );
      // The RPC returns the bare comments row — no profile embed — which
      // made a freshly posted review show "@unknown" until a reload. Re-read
      // it with the author's username/avatar; fall back to the bare row.
      final Map<String, dynamic>? withAuthor =
          await _client.from("comments").select(_select).eq("id", row["id"] as String).maybeSingle();
      return Comment.fromRow(withAuthor ?? row);
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<bool> toggleLike(String commentId) async {
    try {
      return await _client.rpc<bool>("toggle_comment_like", params: <String, dynamic>{"p_comment_id": commentId});
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }

  @override
  Future<void> deleteOwn(String commentId) async {
    try {
      await _client.rpc<dynamic>(
        "delete_own_comment",
        params: <String, dynamic>{"p_comment_id": commentId},
      );
    } on supa.PostgrestException catch (e) {
      throw app_error.ValidationException(e.message, e);
    }
  }
}
