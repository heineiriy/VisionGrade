import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DraftItem {
  final String type;
  final String title;
  final String body;
  final String subjectTitle;
  final DateTime createdAt;
  final Map<String, dynamic>? rubric;
  final List<String> targetStudentEmails;
  final List<String> targetStudentNames;
  final String? attachmentName;
  final String? attachmentUrl;

  const DraftItem({
    required this.type,
    required this.title,
    required this.body,
    required this.subjectTitle,
    required this.createdAt,
    this.rubric,
    this.targetStudentEmails = const [],
    this.targetStudentNames = const [],
    this.attachmentName,
    this.attachmentUrl,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'body': body,
    'subjectTitle': subjectTitle,
    'createdAt': createdAt.toIso8601String(),
    if (rubric != null) 'rubric': rubric,
    if (targetStudentEmails.isNotEmpty)
      'targetStudentEmails': targetStudentEmails,
    if (targetStudentNames.isNotEmpty) 'targetStudentNames': targetStudentNames,
    if (attachmentName != null) 'attachmentName': attachmentName,
    if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
  };

  factory DraftItem.fromJson(Map<String, dynamic> json) => DraftItem(
    type: json['type'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    subjectTitle: json['subjectTitle'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    rubric: json['rubric'] is Map
        ? Map<String, dynamic>.from(json['rubric'] as Map)
        : null,
    targetStudentEmails:
        (json['targetStudentEmails'] as List?)?.whereType<String>().toList() ??
        const [],
    targetStudentNames:
        (json['targetStudentNames'] as List?)?.whereType<String>().toList() ??
        const [],
    attachmentName: json['attachmentName'] as String?,
    attachmentUrl: json['attachmentUrl'] as String?,
  );
}

class PublishedItem {
  final String type;
  final String title;
  final String body;
  final String subjectTitle;
  final DateTime publishedAt;
  final double? score;
  final double? maxScore;

  const PublishedItem({
    required this.type,
    required this.title,
    required this.body,
    required this.subjectTitle,
    required this.publishedAt,
    this.score,
    this.maxScore,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'body': body,
    'subjectTitle': subjectTitle,
    'publishedAt': publishedAt.toIso8601String(),
    'score': score,
    'maxScore': maxScore,
  };

  factory PublishedItem.fromJson(Map<String, dynamic> json) => PublishedItem(
    type: json['type'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    subjectTitle: json['subjectTitle'] as String? ?? '',
    publishedAt:
        DateTime.tryParse(json['publishedAt'] as String? ?? '') ??
        DateTime.now(),
    score: (json['score'] as num?)?.toDouble(),
    maxScore: (json['maxScore'] as num?)?.toDouble(),
  );

  PublishedItem copyWith({double? score, double? maxScore}) {
    return PublishedItem(
      type: type,
      title: title,
      body: body,
      subjectTitle: subjectTitle,
      publishedAt: publishedAt,
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
    );
  }
}

class DraftStore {
  DraftStore._();

  static const _draftsKey = 'visiongrade_drafts';
  static const _publishedKey = 'visiongrade_published_items';
  static SharedPreferences? _preferences;

  static final List<DraftItem> items = [];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final List<PublishedItem> publishedItems = [];
  static final ValueNotifier<int> publishedRevision = ValueNotifier<int>(0);

  static Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    final savedDrafts = _preferences?.getStringList(_draftsKey) ?? [];
    final savedPublished = _preferences?.getStringList(_publishedKey) ?? [];
    items
      ..clear()
      ..addAll(
        savedDrafts.map(
          (value) =>
              DraftItem.fromJson(jsonDecode(value) as Map<String, dynamic>),
        ),
      );
    publishedItems
      ..clear()
      ..addAll(
        savedPublished.map(
          (value) =>
              PublishedItem.fromJson(jsonDecode(value) as Map<String, dynamic>),
        ),
      );
  }

  static void add(DraftItem item) {
    items.insert(0, item);
    revision.value++;
    _persist();
  }

  static void update(int index, DraftItem item) {
    if (index < 0 || index >= items.length) return;
    items[index] = item;
    revision.value++;
    _persist();
  }

  static void remove(int index) {
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    revision.value++;
    _persist();
  }

  static void publish(PublishedItem item) {
    publishedItems.insert(0, item);
    publishedRevision.value++;
    _persist();
  }

  static void grade(PublishedItem item, double score, double maxScore) {
    final index = publishedItems.indexOf(item);
    if (index < 0) return;
    publishedItems[index] = item.copyWith(score: score, maxScore: maxScore);
    publishedRevision.value++;
    _persist();
  }

  static Future<void> _persist() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    await preferences.setStringList(
      _draftsKey,
      items.map((item) => jsonEncode(item.toJson())).toList(),
    );
    await preferences.setStringList(
      _publishedKey,
      publishedItems.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
