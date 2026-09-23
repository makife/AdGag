import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../domain/comment.dart";
import "../domain/comments_repository.dart";

final class CommentsRepositoryImpl implements CommentsRepository {
  CommentsRepositoryImpl(this._client);

  final supa.SupabaseClient _client;

  @override
  Future<List<Comment>> fetchPage({required String adId, DateTime? before, int limit = 20}) async {
    supa.PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from("comments")
        .select("*, profiles(username)")
        .eq("ad_id", adId);

    if (before != null) {
      query = query.lt("created_at", before.toIso8601String());
    }

    final List<Map<String, dynamic>> rows =
        await query.order("created_at", ascending: false).limit(limit);
    return rows.map(Comment.fromRow).toList(growable: false);
  }

  @override
  Future<Comment> create({required String adId, required String body}) async {
    try {
      final Map<String, dynamic> row = await _client.rpc<Map<String, dynamic>>(
        "create_comment",
        params: <String, dynamic>{"p_ad_id": adId, "p_body": body},
      );
      return Comment.fromRow(row);
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
