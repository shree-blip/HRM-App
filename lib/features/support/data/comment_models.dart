/// A row from `asset_request_comments` (also reusable for other *_comments).
class CommentItem {
  const CommentItem({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.authorName,
  });

  final String id;
  final String userId;
  final String content;
  final DateTime? createdAt;
  final String? authorName;

  CommentItem withAuthor(String? name) => CommentItem(
        id: id,
        userId: userId,
        content: content,
        createdAt: createdAt,
        authorName: name,
      );

  factory CommentItem.fromMap(Map<String, dynamic> m) => CommentItem(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        content: (m['content'] ?? '') as String,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
            : null,
      );
}
