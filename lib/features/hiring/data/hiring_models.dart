/// A hiring post — ported from the web Hiring page (`hiring_posts` table).
class HiringPost {
  const HiringPost({
    required this.id,
    required this.title,
    required this.content,
    this.attachmentUrl,
    this.attachmentName,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final String? attachmentUrl;
  final String? attachmentName;
  final String createdAt;

  factory HiringPost.fromMap(Map<String, dynamic> m) => HiringPost(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        attachmentUrl: m['attachment_url'] as String?,
        attachmentName: m['attachment_name'] as String?,
        createdAt: (m['created_at'] ?? '') as String,
      );
}
