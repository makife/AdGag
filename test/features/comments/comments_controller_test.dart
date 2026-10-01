import "package:adgag/features/comments/domain/comment.dart";
import "package:adgag/features/comments/domain/comments_repository.dart";
import "package:adgag/features/comments/presentation/providers/comments_controller.dart";
import "package:adgag/features/comments/presentation/providers/comments_providers.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

Comment _c(String id, {String? parentId, int replyCount = 0}) => Comment(
      id: id,
      adId: "ad1",
      userId: "u1",
      body: "body $id",
      createdAt: DateTime(2026),
      parentId: parentId,
      replyCount: replyCount,
      username: "someone",
    );

class _FakeCommentsRepository implements CommentsRepository {
  final List<Comment> topLevel = <Comment>[_c("top1", replyCount: 1), _c("top2")];
  final Map<String, List<Comment>> replies = <String, List<Comment>>{
    "top1": <Comment>[_c("r1", parentId: "top1")],
  };
  int _next = 0;
  bool failLikes = false;
  final Set<String> liked = <String>{};

  @override
  Future<List<Comment>> fetchPage({required String adId, DateTime? before, int limit = 20}) async => topLevel;

  @override
  Future<List<Comment>> fetchReplies(String parentId, {int limit = 50}) async => replies[parentId] ?? <Comment>[];

  @override
  Future<Comment> create({required String adId, required String body, String? parentId}) async =>
      _c("new${_next++}", parentId: parentId);

  @override
  Future<void> deleteOwn(String commentId) async {}

  @override
  Future<bool> toggleLike(String commentId) async {
    if (failLikes) {
      throw Exception("server said no");
    }
    return liked.remove(commentId) ? false : liked.add(commentId);
  }
}

void main() {
  late ProviderContainer container;
  late _FakeCommentsRepository repo;
  CommentsState state() => container.read(commentsControllerProvider("ad1")).requireValue;
  CommentsController controller() => container.read(commentsControllerProvider("ad1").notifier);

  setUp(() async {
    container = ProviderContainer(
      overrides: <Override>[commentsRepositoryProvider.overrideWithValue(repo = _FakeCommentsRepository())],
    );
    await container.read(commentsControllerProvider("ad1").future);
  });

  tearDown(() => container.dispose());

  test("loadReplies expands a review and hideReplies collapses it", () async {
    await controller().loadReplies("top1");
    expect(state().replies["top1"]!.map((Comment c) => c.id), <String>["r1"]);
    controller().hideReplies("top1");
    expect(state().replies.containsKey("top1"), isFalse);
  });

  test("a reply goes under its review and bumps its reply count", () async {
    await controller().post("hi", parentId: "top2");
    expect(state().comments.map((Comment c) => c.id), <String>["top1", "top2"]); // not a new top-level review
    expect(state().comments[1].replyCount, 1);
    expect(state().replies["top2"]!.single.parentId, "top2");
    expect(container.read(commentCountDeltaProvider("ad1")), 1);
  });

  test("a new top-level review goes first", () async {
    await controller().post("hi");
    expect(state().comments.first.id, "new0");
    expect(state().comments.first.isReply, isFalse);
  });

  test("deleting a reply removes it and lowers the count", () async {
    await controller().loadReplies("top1");
    await controller().deleteOwn(state().replies["top1"]!.single);
    expect(state().replies["top1"], isEmpty);
    expect(state().comments.first.replyCount, 0);
    expect(container.read(commentCountDeltaProvider("ad1")), -1);
  });

  test("liking a review shows at once, and liking again takes it back", () async {
    await controller().toggleLike(state().comments.first);
    expect(state().comments.first.likedByMe, isTrue);
    expect(state().comments.first.likeCount, 1);
    await controller().toggleLike(state().comments.first);
    expect(state().comments.first.likedByMe, isFalse);
    expect(state().comments.first.likeCount, 0);
  });

  test("a reply can be liked too", () async {
    await controller().loadReplies("top1");
    await controller().toggleLike(state().replies["top1"]!.single);
    expect(state().replies["top1"]!.single.likedByMe, isTrue);
    expect(state().comments.first.likedByMe, isFalse); // only the reply
  });

  test("a like the server refuses is undone", () async {
    repo.failLikes = true;
    await expectLater(controller().toggleLike(state().comments.first), throwsException);
    expect(state().comments.first.likedByMe, isFalse);
    expect(state().comments.first.likeCount, 0);
  });
}
