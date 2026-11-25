class NoteSpan {
  const NoteSpan({
    required this.text,
    this.fontFamily = 'sans',
    this.fontSize = 14,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  final String text;
  final String fontFamily;
  final int fontSize;
  final bool bold;
  final bool italic;
  final bool underline;
  final String? color;

  factory NoteSpan.fromJson(Map<String, dynamic> json) => NoteSpan(
    text: json['text'] as String,
    fontFamily: json['font_family'] as String? ?? 'sans',
    fontSize: json['font_size'] as int? ?? 14,
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    underline: json['underline'] as bool? ?? false,
    color: json['color'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'font_family': fontFamily,
    'font_size': fontSize,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'color': color,
  };

  NoteSpan copyWith({
    String? text,
    String? fontFamily,
    int? fontSize,
    bool? bold,
    bool? italic,
    bool? underline,
    String? color,
    bool clearColor = false,
  }) => NoteSpan(
    text: text ?? this.text,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    color: clearColor ? null : color ?? this.color,
  );
}

class NoteBlock {
  const NoteBlock({this.type = 'paragraph', this.spans = const []});

  final String type;
  final List<NoteSpan> spans;

  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
    type: json['type'] as String? ?? 'paragraph',
    spans: (json['spans'] as List<dynamic>? ?? const [])
        .map((span) => NoteSpan.fromJson(span as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'spans': spans
        .where((span) => span.text.isNotEmpty)
        .map((span) => span.toJson())
        .toList(),
  };

  String get plainText => spans.map((span) => span.text).join();
}

class NoteAttachment {
  const NoteAttachment({
    required this.id,
    required this.filename,
    required this.mediaType,
    required this.size,
  });
  final int id;
  final String filename;
  final String mediaType;
  final int size;

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
    id: json['id'] as int,
    filename: json['filename'] as String,
    mediaType: json['media_type'] as String,
    size: json['size'] as int,
  );
}

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    required this.taskIds,
    required this.attachments,
  });
  final int id;
  final String title;
  final List<NoteBlock> content;
  final DateTime updatedAt;
  final List<int> taskIds;
  final List<NoteAttachment> attachments;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as int,
    title: json['title'] as String,
    content: (json['content'] as List<dynamic>? ?? const [])
        .map((block) => NoteBlock.fromJson(block as Map<String, dynamic>))
        .toList(),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    taskIds: (json['task_ids'] as List<dynamic>? ?? const []).cast<int>(),
    attachments: (json['attachments'] as List<dynamic>? ?? const [])
        .map((item) => NoteAttachment.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  String get preview => content
      .map((block) => block.plainText)
      .where((text) => text.isNotEmpty)
      .join(' · ');
}
