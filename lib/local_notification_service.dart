import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'task_due_date.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static const _channelId = 'visiongrade_updates';
  static const _channelName = 'VisionGrade updates';
  static const _reminderIdsKey = 'local_scheduled_reminder_ids';
  static const _notifiedContentKey = 'local_notified_content_ids';
  static const _timeZone = 'Asia/Manila';
  static final _notifications = FlutterLocalNotificationsPlugin();
  static final Map<
    String,
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  >
  _postSubscriptions = {};
  static final Map<
    String,
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  >
  _submissionSubscriptions = {};
  static final Set<String> _initializedSubjects = {};
  static final Map<String, Map<String, dynamic>> _tasks = {};
  static timezone.Location? _location;
  static String _studentEmail = '';
  static bool _notificationsEnabled = true;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    _location = timezone.getLocation(_timeZone);
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Task, announcement, grade, and deadline reminders.',
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  static Future<void> startForStudent({
    required String email,
    required List<String> assignedSubjectIds,
  }) async {
    try {
      await initialize();
      await _cancelListeners();
      await _cancelScheduledReminders();
      _tasks.clear();
      _initializedSubjects.clear();
      _studentEmail = email.trim();

      final settings = await SharedPreferences.getInstance();
      _notificationsEnabled =
          settings.getBool('settings_notifications') ?? true;
      if (_notificationsEnabled) {
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }

      final subjectIds = assignedSubjectIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final subjectId in subjectIds) {
        _postSubscriptions[subjectId] = FirebaseFirestore.instance
            .collection('subjects')
            .doc(subjectId)
            .collection('posts')
            .snapshots()
            .listen(
              (snapshot) => unawaited(_handlePostSnapshot(subjectId, snapshot)),
              onError: (Object error, StackTrace stackTrace) {
                debugPrint(
                  'Could not monitor posts for local notifications: '
                  '$error\n$stackTrace',
                );
              },
            );
      }
    } catch (error, stackTrace) {
      debugPrint('Could not start local notifications: $error\n$stackTrace');
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    final settings = await SharedPreferences.getInstance();
    await settings.setBool('settings_notifications', enabled);
    _notificationsEnabled = enabled;
    if (enabled) {
      await _scheduleTaskReminders();
    } else {
      await _cancelScheduledReminders();
    }
  }

  static Future<void> stop() async {
    await _cancelListeners();
    _tasks.clear();
    _initializedSubjects.clear();
    await _cancelScheduledReminders();
    _studentEmail = '';
  }

  static Future<void> _cancelListeners() async {
    await Future.wait([
      ..._postSubscriptions.values.map((subscription) => subscription.cancel()),
      ..._submissionSubscriptions.values.map(
        (subscription) => subscription.cancel(),
      ),
    ]);
    _postSubscriptions.clear();
    _submissionSubscriptions.clear();
  }

  static Future<void> _handlePostSnapshot(
    String subjectId,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    try {
      final isInitialSnapshot = _initializedSubjects.add(subjectId);
      final currentTaskKeys = <String>{};

      for (final post in snapshot.docs) {
        final data = post.data();
        final type = data['type'];
        if ((type != 'Task' && type != 'Announcement') ||
            !isTaskVisibleToStudent(data, _studentEmail)) {
          continue;
        }

        final postKey = '$subjectId/${post.id}';
        final title = (data['title'] as String?)?.trim();
        final subjectTitle = (data['subjectTitle'] as String?)?.trim();
        final displayTitle = title?.isNotEmpty == true
            ? title!
            : 'Untitled ${type.toString().toLowerCase()}';

        if (type == 'Task') {
          currentTaskKeys.add(postKey);
          _tasks[postKey] = {
            ...data,
            'subjectId': subjectId,
            'postId': post.id,
            'subjectTitle': subjectTitle,
          };
          _listenForPublishedGrade(
            subjectId: subjectId,
            postId: post.id,
            taskTitle: displayTitle,
          );
        }
      }

      final previousTaskKeys = _tasks.keys
          .where((key) => key.startsWith('$subjectId/'))
          .toSet();
      for (final key in previousTaskKeys.difference(currentTaskKeys)) {
        _tasks.remove(key);
        final subscription = _submissionSubscriptions.remove(key);
        await subscription?.cancel();
      }

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null ||
            (data['type'] != 'Task' && data['type'] != 'Announcement') ||
            !isTaskVisibleToStudent(data, _studentEmail)) {
          continue;
        }
        if (isInitialSnapshot && !_wasPostedRecently(data['postedAt'])) {
          continue;
        }
        final type = data['type'] as String;
        final title = (data['title'] as String?)?.trim();
        final displayTitle = title?.isNotEmpty == true
            ? title!
            : 'Untitled ${type.toLowerCase()}';
        await _showContentOnce(
          key: 'post|$_studentEmail|$subjectId|${change.doc.id}',
          title: type == 'Task' ? 'New task posted' : 'New announcement',
          body: displayTitle,
        );
      }

      await _scheduleTaskReminders();
    } catch (error, stackTrace) {
      debugPrint(
        'Could not process local notification updates: $error\n$stackTrace',
      );
    }
  }

  static void _listenForPublishedGrade({
    required String subjectId,
    required String postId,
    required String taskTitle,
  }) {
    final taskKey = '$subjectId/$postId';
    if (_submissionSubscriptions.containsKey(taskKey) ||
        _studentEmail.isEmpty) {
      return;
    }
    var hasInitialSnapshot = false;
    var wasPublished = false;
    _submissionSubscriptions[taskKey] = FirebaseFirestore.instance
        .collection('subjects')
        .doc(subjectId)
        .collection('posts')
        .doc(postId)
        .collection('submissions')
        .doc(_studentEmail)
        .snapshots()
        .listen(
          (snapshot) {
            final isPublished = snapshot.data()?['reviewStatus'] == 'published';
            if (!hasInitialSnapshot) {
              hasInitialSnapshot = true;
              wasPublished = isPublished;
              return;
            }
            final wasJustPublished = isPublished && !wasPublished;
            wasPublished = isPublished;
            if (!wasJustPublished) return;
            unawaited(
              _showContentOnce(
                key: 'grade|$_studentEmail|$taskKey',
                title: 'Your work has been graded',
                body: '$taskTitle is ready to review.',
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'Could not monitor a task grade for local notifications: '
              '$error\n$stackTrace',
            );
          },
        );
  }

  static Future<void> _showContentOnce({
    required String key,
    required String title,
    required String body,
  }) async {
    if (!_notificationsEnabled) return;
    try {
      final settings = await SharedPreferences.getInstance();
      final notifiedIds = settings.getStringList(_notifiedContentKey) ?? [];
      if (notifiedIds.contains(key)) return;
      await _show(
        id: _notificationId(key),
        title: title,
        body: body,
        payload: key,
      );
      notifiedIds.add(key);
      if (notifiedIds.length > 500) {
        notifiedIds.removeRange(0, notifiedIds.length - 500);
      }
      await settings.setStringList(_notifiedContentKey, notifiedIds);
    } catch (error, stackTrace) {
      debugPrint('Could not show a local notification: $error\n$stackTrace');
    }
  }

  static bool _wasPostedRecently(Object? value) {
    final DateTime? postedAt = switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime dateTime => dateTime,
      _ => null,
    };
    if (postedAt == null) return false;
    final age = DateTime.now().difference(postedAt);
    return age >= Duration.zero && age <= const Duration(hours: 24);
  }

  static Future<void> _scheduleTaskReminders() async {
    if (!_notificationsEnabled || _location == null) return;
    final settings = await SharedPreferences.getInstance();
    final oldIds = (settings.getStringList(_reminderIdsKey) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final scheduledIds = <int>{};
    final now = timezone.TZDateTime.now(_location!);

    for (final entry in _tasks.entries) {
      final data = entry.value;
      final dueDate = _parseDueDate(data['dueDate'] ?? data['due']);
      if (dueDate == null) continue;
      final taskTitle = (data['title'] as String?)?.trim();
      final subjectTitle = (data['subjectTitle'] as String?)?.trim();
      for (final daysBefore in [3, 2, 1]) {
        final reminderDate = dueDate.subtract(Duration(days: daysBefore));
        final scheduledDate = timezone.TZDateTime(
          _location!,
          reminderDate.year,
          reminderDate.month,
          reminderDate.day,
          9,
        );
        if (!scheduledDate.isAfter(now)) continue;

        final notificationKey = 'deadline|${entry.key}|$daysBefore';
        final id = _notificationId(notificationKey);
        scheduledIds.add(id);
        await _notifications.zonedSchedule(
          id,
          'Task due in $daysBefore ${daysBefore == 1 ? 'day' : 'days'}',
          [
            if (taskTitle?.isNotEmpty == true) taskTitle!,
            if (subjectTitle?.isNotEmpty == true) 'in $subjectTitle',
          ].join(' '),
          scheduledDate,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription:
                  'Task, announcement, grade, and deadline reminders.',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: notificationKey,
        );
      }
    }

    for (final id in oldIds.difference(scheduledIds)) {
      await _notifications.cancel(id);
    }
    await settings.setStringList(
      _reminderIdsKey,
      scheduledIds.map((id) => id.toString()).toList(),
    );
  }

  static DateTime? _parseDueDate(Object? value) {
    return taskDueDate(value);
  }

  static Future<void> _cancelScheduledReminders() async {
    final settings = await SharedPreferences.getInstance();
    final oldIds = (settings.getStringList(_reminderIdsKey) ?? [])
        .map(int.tryParse)
        .whereType<int>();
    for (final id in oldIds) {
      await _notifications.cancel(id);
    }
    await settings.setStringList(_reminderIdsKey, []);
  }

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) {
    return _notifications.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Task, announcement, grade, and deadline reminders.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
