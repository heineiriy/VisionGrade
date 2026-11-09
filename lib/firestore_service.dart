import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _posts(String subjectId) {
    return _firestore.collection('subjects').doc(subjectId).collection('posts');
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> subjectsStream() {
    return _firestore.collection('subjects').orderBy('name').snapshots();
  }

  static Future<void> refreshHomeData({
    String? studentEmail,
    String? instructorEmail,
  }) async {
    final futures = <Future<Object>>[];
    if (studentEmail != null && studentEmail.trim().isNotEmpty) {
      futures.add(
        _firestore
            .collection('students')
            .where('email', isEqualTo: studentEmail.trim())
            .limit(1)
            .get(const GetOptions(source: Source.server)),
      );
    }
    if (instructorEmail != null && instructorEmail.trim().isNotEmpty) {
      futures.add(
        _firestore
            .collection('subjects')
            .where('instructorEmail', isEqualTo: instructorEmail.trim())
            .get(const GetOptions(source: Source.server)),
      );
    } else {
      futures.add(
        _firestore
            .collection('subjects')
            .orderBy('name')
            .get(const GetOptions(source: Source.server)),
      );
    }
    await Future.wait(futures);
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> getSubject(
    String subjectId,
  ) {
    return _firestore.collection('subjects').doc(subjectId).get();
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  findSubjectByTitle(String subjectTitle) async {
    final matches = await _firestore
        .collection('subjects')
        .where('name', isEqualTo: subjectTitle)
        .limit(1)
        .get();
    return matches.docs.isEmpty ? null : matches.docs.first;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> getSubjectTask({
    required String subjectId,
    required String taskId,
  }) {
    return _posts(subjectId).doc(taskId).get();
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  findSubjectTaskByTitle({
    required String subjectId,
    required String taskTitle,
  }) async {
    final matches = await _posts(
      subjectId,
    ).where('title', isEqualTo: taskTitle).limit(1).get();
    return matches.docs.isEmpty ? null : matches.docs.first;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> instructorSubjectsStream(
    String instructorEmail,
  ) {
    return _firestore
        .collection('subjects')
        .where('instructorEmail', isEqualTo: instructorEmail)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> studentSubjectsStream(
    String? section,
  ) {
    return _firestore.collection('subjects').orderBy('name').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> studentAccountStream(
    String email,
  ) {
    return _firestore
        .collection('students')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> userProfileStream({
    required String collection,
    required String email,
  }) {
    return _firestore
        .collection(collection)
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .snapshots();
  }

  static Future<void> refreshUserProfile({
    required String collection,
    required String email,
  }) async {
    await _firestore
        .collection(collection)
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get(const GetOptions(source: Source.server));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> subjectPostsStream(
    String subjectId,
  ) {
    // Do not order in Firestore: older posts may not have `postedAt`, and
    // Firestore excludes those documents from an ordered query.
    return _posts(subjectId).snapshots();
  }

  static Future<void> refreshSubjectContent({
    required String subjectId,
    required String role,
    required String email,
    required String authUid,
  }) async {
    final posts = await _posts(
      subjectId,
    ).get(const GetOptions(source: Source.server));
    final futures = <Future<Object>>[];
    for (final post in posts.docs.where(
      (post) => post.data()['type'] == 'Task',
    )) {
      final submissions = _submissions(subjectId, post.id);
      if (role == 'student' && email.trim().isNotEmpty) {
        futures.add(
          submissions
              .doc(email.trim())
              .get(const GetOptions(source: Source.server)),
        );
      } else if (role == 'instructor') {
        futures.add(submissions.get(const GetOptions(source: Source.server)));
      }
    }

    final normalizedEmail = email.trim().toLowerCase();
    final normalizedUid = authUid.trim();
    final announcements = _firestore.collection('global_announcements');
    futures.add(
      announcements
          .where('isGlobalAnnouncement', isEqualTo: true)
          .get(const GetOptions(source: Source.server)),
    );
    if (normalizedEmail.isNotEmpty) {
      futures.add(
        announcements
            .where(
              role == 'student'
                  ? 'targetStudentEmails'
                  : 'targetInstructorEmails',
              arrayContains: normalizedEmail,
            )
            .get(const GetOptions(source: Source.server)),
      );
    }
    if (normalizedUid.isNotEmpty) {
      final uidField = role == 'student'
          ? 'targetStudentUids'
          : 'targetInstructorUids';
      final profileIdField = role == 'student'
          ? 'targetStudentProfileIds'
          : 'targetInstructorProfileIds';
      futures.addAll([
        announcements
            .where(uidField, arrayContains: normalizedUid)
            .get(const GetOptions(source: Source.server)),
        announcements
            .where(profileIdField, arrayContains: normalizedUid)
            .get(const GetOptions(source: Source.server)),
      ]);
    }
    await Future.wait(futures);
  }

  static Future<void> refreshPostComments({
    required String subjectId,
    required String postId,
    bool isGlobalAnnouncement = false,
  }) async {
    final post = isGlobalAnnouncement
        ? _firestore.collection('global_announcements').doc(postId)
        : _posts(subjectId).doc(postId);
    await post
        .collection('comments')
        .get(const GetOptions(source: Source.server));
  }

  static Future<void> refreshMessages({
    required String studentEmail,
    required String instructorEmail,
  }) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId(studentEmail, instructorEmail))
        .collection('messages')
        .orderBy('sentAt')
        .get(const GetOptions(source: Source.server));
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  globalAnnouncementsStream({
    required String email,
    required String role,
    required String authUid,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedUid = authUid.trim();
    final collection = _firestore.collection('global_announcements');
    final controller =
        StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? broadcasts;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? emailTargets =
        normalizedEmail.isEmpty ? [] : null;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? uidTargets =
        normalizedUid.isEmpty ? [] : null;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? profileTargets =
        normalizedUid.isEmpty ? [] : null;
    final targetField = role == 'student'
        ? 'targetStudentEmails'
        : 'targetInstructorEmails';
    final targetUidField = role == 'student'
        ? 'targetStudentUids'
        : 'targetInstructorUids';
    final targetProfileIdField = role == 'student'
        ? 'targetStudentProfileIds'
        : 'targetInstructorProfileIds';

    void emitIfReady() {
      if (broadcasts == null ||
          emailTargets == null ||
          uidTargets == null ||
          profileTargets == null) {
        return;
      }
      final uniquePosts =
          <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final post in [
        ...broadcasts!,
        ...emailTargets!,
        ...uidTargets!,
        ...profileTargets!,
      ]) {
        uniquePosts[post.id] = post;
      }
      controller.add(uniquePosts.values.toList());
    }

    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    subscriptions.add(
      collection
          .where('isGlobalAnnouncement', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
            broadcasts = snapshot.docs;
            emitIfReady();
          }, onError: controller.addError),
    );
    if (normalizedEmail.isNotEmpty) {
      subscriptions.add(
        collection
            .where(targetField, arrayContains: normalizedEmail)
            .snapshots()
            .listen((snapshot) {
              emailTargets = snapshot.docs;
              emitIfReady();
            }, onError: controller.addError),
      );
    }
    if (normalizedUid.isNotEmpty) {
      subscriptions.add(
        collection
            .where(targetUidField, arrayContains: normalizedUid)
            .snapshots()
            .listen((snapshot) {
              uidTargets = snapshot.docs;
              emitIfReady();
            }, onError: controller.addError),
      );
      subscriptions.add(
        collection
            .where(targetProfileIdField, arrayContains: normalizedUid)
            .snapshots()
            .listen((snapshot) {
              profileTargets = snapshot.docs;
              emitIfReady();
            }, onError: controller.addError),
      );
    }
    controller.onCancel = () async {
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    };
    return controller.stream;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> postCommentsStream({
    required String subjectId,
    required String postId,
    bool isGlobalAnnouncement = false,
  }) {
    final post = isGlobalAnnouncement
        ? _firestore.collection('global_announcements').doc(postId)
        : _posts(subjectId).doc(postId);
    return post.collection('comments').snapshots();
  }

  static Future<void> addPostComment({
    required String subjectId,
    required String postId,
    required String authorName,
    required String authorEmail,
    required String authorRole,
    required String text,
    bool isGlobalAnnouncement = false,
  }) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Comment cannot be empty.');
    }
    final post = isGlobalAnnouncement
        ? _firestore.collection('global_announcements').doc(postId)
        : _posts(subjectId).doc(postId);
    return post.collection('comments').add({
      'authorName': authorName.trim().isEmpty ? 'User' : authorName.trim(),
      'authorEmail': authorEmail.trim(),
      'authorRole': authorRole,
      'text': trimmedText,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static CollectionReference<Map<String, dynamic>> _submissions(
    String subjectId,
    String taskId,
  ) {
    return _posts(subjectId).doc(taskId).collection('submissions');
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>>
  studentSubmissionStream({
    required String subjectId,
    required String taskId,
    required String studentEmail,
  }) {
    return _submissions(subjectId, taskId).doc(studentEmail).snapshots();
  }

  static Future<void> submitClasswork({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required String studentName,
    required String answer,
  }) {
    return _submissions(subjectId, taskId).doc(studentEmail).set({
      'studentEmail': studentEmail,
      'studentName': studentName,
      'answer': answer,
      'status': 'Submitted',
      'reviewStatus': 'pending_review',
      'gradingSource': 'ai_pending_human_review',
      'submittedAt': FieldValue.serverTimestamp(),
      'score': null,
      'feedback': null,
    }, SetOptions(merge: true));
  }

  static Future<void> gradeSubmission({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required double score,
    required double maxScore,
    required String feedback,
    double? aiScore,
    double? aiConfidence,
    String? overrideReason,
    Map<String, dynamic>? aiTrainingExample,
  }) {
    final teacherFinalScore = score / maxScore * 100;
    final reason = overrideReason?.trim() ?? '';
    final differsFromAi =
        aiScore != null && (teacherFinalScore - aiScore).abs() > 0.01;
    final data = <String, dynamic>{
      'score': score,
      'maxScore': maxScore,
      'feedback': feedback,
      'status': 'Graded',
      'reviewStatus': 'published',
      'gradingSource': aiScore == null
          ? 'teacher_manual'
          : differsFromAi
          ? 'human_override'
          : 'teacher_reviewed_ai',
      'gradedAt': FieldValue.serverTimestamp(),
      'ai_pre_score': aiScore,
      'teacher_final_score': teacherFinalScore,
      'teacher_final_points': score,
      'override_reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (aiScore != null) data['aiScore'] = aiScore;
    if (aiConfidence != null) data['aiConfidence'] = aiConfidence;
    if (aiScore != null) {
      data['teacherComparison'] = {
        'teacherScore': teacherFinalScore,
        'aiScore': aiScore,
        'absoluteDifference': (teacherFinalScore - aiScore).abs(),
        'evaluatedAt': FieldValue.serverTimestamp(),
      };
    }
    if (aiTrainingExample != null) {
      data['aiTrainingExample'] = aiTrainingExample;
    }
    return _submissions(subjectId, taskId).doc(studentEmail).update(data);
  }

  static Future<void> updateSubmissionAiGrading({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required double aiScore,
    required double aiConfidence,
    required String extractedText,
    required List<String> aiInsights,
    required String expectedAnswer,
    required Map<String, dynamic> visualAnalysis,
    List<Map<String, dynamic>>? criterionResults,
    List<Map<String, dynamic>>? criterionScores,
    List<String>? aiFeedback,
    Map<String, dynamic>? textFeatures,
    List<String>? matchedStandards,
    List<String>? missingStandards,
    bool requiresHumanReview = true,
  }) {
    return _submissions(subjectId, taskId).doc(studentEmail).update({
      'aiScore': aiScore,
      'aiConfidence': aiConfidence,
      'extractedText': extractedText,
      'aiInsights': aiInsights,
      'aiExpectedAnswer': expectedAnswer,
      'visualAnalysis': visualAnalysis,
      'aiCriterionResults': ?criterionResults,
      'aiCriterionScores': ?criterionScores,
      'aiFeedback': ?aiFeedback,
      'aiTextFeatures': ?textFeatures,
      'matchedCurriculumStandards': ?matchedStandards,
      'missingCurriculumStandards': ?missingStandards,
      'aiRequiresHumanReview': requiresHumanReview,
      'aiGradedAt': FieldValue.serverTimestamp(),
      'reviewStatus': 'pending_review',
      'gradingSource': 'ai_pending_human_review',
    });
  }

  static String conversationId(String studentEmail, String instructorEmail) {
    final participants = [
      studentEmail.trim().toLowerCase(),
      instructorEmail.trim().toLowerCase(),
    ]..sort();
    return '${participants[0]}_${participants[1]}';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream({
    required String studentEmail,
    required String instructorEmail,
  }) {
    return _firestore
        .collection('conversations')
        .doc(conversationId(studentEmail, instructorEmail))
        .collection('messages')
        .orderBy('sentAt')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
  instructorConversationsStream(String instructorEmail) {
    return _firestore
        .collection('conversations')
        .where('instructorEmail', isEqualTo: instructorEmail)
        .snapshots();
  }

  static Future<void> refreshInstructorConversations(
    String instructorEmail,
  ) async {
    await _firestore
        .collection('conversations')
        .where('instructorEmail', isEqualTo: instructorEmail)
        .get(const GetOptions(source: Source.server));
  }

  static Future<void> sendMessage({
    required String studentEmail,
    required String instructorEmail,
    required String senderEmail,
    required String senderName,
    required String text,
    String? subjectTitle,
    String? subjectId,
    String? taskTitle,
    String? taskId,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Message cannot be empty.');
    }
    final conversation = _firestore
        .collection('conversations')
        .doc(conversationId(studentEmail, instructorEmail));
    final conversationData = <String, dynamic>{
      'studentEmail': studentEmail,
      'instructorEmail': instructorEmail,
      'lastMessage': trimmedText,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
    if (senderEmail == studentEmail) {
      conversationData['studentName'] = senderName;
    }
    if (senderEmail == instructorEmail) {
      conversationData['instructorName'] = senderName;
    }
    final trimmedSubjectTitle = subjectTitle?.trim() ?? '';
    final trimmedSubjectId = subjectId?.trim() ?? '';
    final trimmedTaskTitle = taskTitle?.trim() ?? '';
    final trimmedTaskId = taskId?.trim() ?? '';
    if (senderEmail == studentEmail &&
        (trimmedSubjectTitle.isNotEmpty || trimmedTaskTitle.isNotEmpty)) {
      conversationData['sourceSubjectTitle'] = trimmedSubjectTitle;
      conversationData['sourceTaskTitle'] = trimmedTaskTitle;
      if (trimmedSubjectId.isNotEmpty) {
        conversationData['sourceSubjectId'] = trimmedSubjectId;
      }
      if (trimmedTaskId.isNotEmpty) {
        conversationData['sourceTaskId'] = trimmedTaskId;
      }
    }
    await conversation.set(conversationData, SetOptions(merge: true));
    final messageData = <String, dynamic>{
      'senderEmail': senderEmail,
      'senderName': senderName,
      'text': trimmedText,
      'sentAt': FieldValue.serverTimestamp(),
      'readBy': [senderEmail],
    };
    if (trimmedSubjectTitle.isNotEmpty) {
      messageData['subjectTitle'] = trimmedSubjectTitle;
    }
    if (trimmedSubjectId.isNotEmpty) {
      messageData['subjectId'] = trimmedSubjectId;
    }
    if (trimmedTaskTitle.isNotEmpty) {
      messageData['taskTitle'] = trimmedTaskTitle;
    }
    if (trimmedTaskId.isNotEmpty) {
      messageData['taskId'] = trimmedTaskId;
    }
    await conversation.collection('messages').add(messageData);
  }

  static Future<void> updateSubmissionFeedback({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required String feedback,
  }) {
    return _submissions(subjectId, taskId).doc(studentEmail).update({
      'feedback': feedback,
      'feedbackUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> publishPost({
    required String subjectId,
    required String subjectTitle,
    required String type,
    required String title,
    required String body,
    required String posterName,
    required String posterEmail,
    bool allowUpload = false,
    bool closeAfterDeadline = true,
    String? dueDate,
    List<String> targetStudentEmails = const [],
    List<String> targetStudentNames = const [],
    String? attachmentName,
    String? attachmentUrl,
    Map<String, dynamic>? rubric,
  }) {
    final data = <String, dynamic>{
      'subjectId': subjectId,
      'subjectTitle': subjectTitle,
      'type': type,
      'title': title,
      'body': body,
      'posterName': posterName,
      'posterEmail': posterEmail,
      'allowUpload': allowUpload,
      'closeAfterDeadline': closeAfterDeadline,
      'postedAt': FieldValue.serverTimestamp(),
    };
    if (dueDate != null) data['dueDate'] = dueDate;
    final selectedEmails = targetStudentEmails
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .toList();
    if (selectedEmails.isNotEmpty) {
      data['targetStudentEmails'] = selectedEmails;
      data['targetStudentNames'] = targetStudentNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
    }
    if (rubric != null) data['rubric'] = rubric;
    if (attachmentName != null && attachmentUrl != null) {
      data['attachmentName'] = attachmentName;
      data['attachmentUrl'] = attachmentUrl;
    }
    return _posts(subjectId).add(data);
  }

  static Future<void> updatePost({
    required String subjectId,
    required String postId,
    required String title,
    required String body,
    bool? allowUpload,
    bool? closeAfterDeadline,
    String? dueDate,
    List<String> targetStudentEmails = const [],
    List<String> targetStudentNames = const [],
    String? attachmentName,
    String? attachmentUrl,
    Map<String, dynamic>? rubric,
    bool updateTaskFields = false,
  }) {
    final data = <String, dynamic>{
      'title': title,
      'body': body,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (updateTaskFields) {
      data['allowUpload'] = allowUpload ?? false;
      data['closeAfterDeadline'] = closeAfterDeadline ?? true;
      data['dueDate'] = dueDate;
      data['targetStudentEmails'] = targetStudentEmails
          .map((email) => email.trim())
          .where((email) => email.isNotEmpty)
          .toList();
      data['targetStudentNames'] = targetStudentNames
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (attachmentName != null && attachmentUrl != null) {
        data['attachmentName'] = attachmentName;
        data['attachmentUrl'] = attachmentUrl;
      }
      if (rubric != null) data['rubric'] = rubric;
    }
    return _posts(subjectId).doc(postId).update(data);
  }

  static Future<void> deletePost({
    required String subjectId,
    required String postId,
  }) {
    return _posts(subjectId).doc(postId).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> submissionsStream({
    required String subjectId,
    required String taskId,
  }) {
    return _submissions(
      subjectId,
      taskId,
    ).orderBy('submittedAt', descending: true).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> studentsStream() {
    return _firestore.collection('students').orderBy('name').snapshots();
  }

  static Future<void> updateSubjectThumbnail({
    required String subjectId,
    required String thumbnailUrl,
  }) {
    return _firestore.collection('subjects').doc(subjectId).update({
      'thumbnailUrl': thumbnailUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> recordHardcopyScan({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required String studentName,
    required String scanUrl,
    List<String>? scanUrls,
    bool appendImages = false,
  }) {
    final submissionRef = _submissions(subjectId, taskId).doc(studentEmail);
    final newUrls = scanUrls ?? [scanUrl];
    return _firestore.runTransaction((transaction) async {
      final existing = appendImages
          ? await transaction.get(submissionRef)
          : null;
      final existingData = existing?.data() ?? const <String, dynamic>{};
      final existingUrls = <String>[
        if (existingData['scanUrls'] is Iterable)
          for (final url in existingData['scanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
        if (existingData['scanUrls'] is! Iterable &&
            existingData['scanUrl'] is String &&
            (existingData['scanUrl'] as String).trim().isNotEmpty)
          (existingData['scanUrl'] as String).trim(),
      ];
      final allUrls = appendImages ? [...existingUrls, ...newUrls] : newUrls;
      transaction.set(submissionRef, {
        'studentEmail': studentEmail,
        'studentName': studentName,
        'answer': 'Hardcopy scanned for grading',
        'scanUrl': allUrls.first,
        'scanUrls': allUrls,
        'status': 'Submitted',
        'reviewStatus': 'pending_review',
        'gradingSource': 'ai_pending_human_review',
        'submittedAt': FieldValue.serverTimestamp(),
        'score': null,
        'feedback': null,
      }, SetOptions(merge: true));
    });
  }

  static Future<void> saveSubmissionImageDraft({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required String studentName,
    required List<String> imageUrls,
  }) {
    if (imageUrls.isEmpty) {
      throw ArgumentError.value(imageUrls, 'imageUrls', 'Must not be empty.');
    }

    final submissionRef = _submissions(subjectId, taskId).doc(studentEmail);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(submissionRef);
      final existingData = snapshot.data() ?? const <String, dynamic>{};
      if (existingData['status'] == 'Submitted' ||
          existingData['status'] == 'Graded') {
        throw StateError('Unsubmit your current work before adding photos.');
      }
      transaction.set(submissionRef, {
        'studentEmail': studentEmail,
        'studentName': studentName,
        'draftScanUrls': FieldValue.arrayUnion(imageUrls),
        'draftUpdatedAt': FieldValue.serverTimestamp(),
        if (!snapshot.exists) ...{
          'answer': '',
          'status': 'Draft',
          'submittedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    });
  }

  static Future<void> submitSubmissionImageDraft({
    required String subjectId,
    required String taskId,
    required String studentEmail,
  }) {
    final submissionRef = _submissions(subjectId, taskId).doc(studentEmail);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(submissionRef);
      if (!snapshot.exists) {
        throw StateError('There are no saved photos to submit.');
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      if (data['status'] == 'Submitted' || data['status'] == 'Graded') {
        throw StateError('Unsubmit your current work before submitting again.');
      }
      final draftUrls = <String>[
        if (data['draftScanUrls'] is Iterable)
          for (final url in data['draftScanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
      ];
      if (draftUrls.isEmpty) {
        throw StateError('There are no saved photos to submit.');
      }

      final submittedUrls = <String>[
        if (data['scanUrls'] is Iterable)
          for (final url in data['scanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
        if (data['scanUrls'] is! Iterable &&
            data['scanUrl'] is String &&
            (data['scanUrl'] as String).trim().isNotEmpty)
          (data['scanUrl'] as String).trim(),
      ];
      final allUrls = [...submittedUrls, ...draftUrls];

      transaction.update(submissionRef, {
        'answer': 'Hardcopy scanned for grading',
        'scanUrl': allUrls.first,
        'scanUrls': allUrls,
        'draftScanUrls': FieldValue.delete(),
        'draftUpdatedAt': FieldValue.delete(),
        'status': 'Submitted',
        'reviewStatus': 'pending_review',
        'gradingSource': 'ai_pending_human_review',
        'submittedAt': FieldValue.serverTimestamp(),
        'score': null,
        'feedback': null,
      });
    });
  }

  static Future<void> unsubmitSubmissionImageDraft({
    required String subjectId,
    required String taskId,
    required String studentEmail,
  }) {
    final submissionRef = _submissions(subjectId, taskId).doc(studentEmail);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(submissionRef);
      if (!snapshot.exists) {
        throw StateError('The submission could not be found.');
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      if (data['status'] != 'Submitted' ||
          data['score'] != null ||
          data['reviewStatus'] == 'published') {
        throw StateError('Only ungraded submitted work can be unsubmitted.');
      }

      final submittedUrls = <String>[
        if (data['scanUrls'] is Iterable)
          for (final url in data['scanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
        if (data['scanUrls'] is! Iterable &&
            data['scanUrl'] is String &&
            (data['scanUrl'] as String).trim().isNotEmpty)
          (data['scanUrl'] as String).trim(),
      ];
      final existingDraftUrls = <String>[
        if (data['draftScanUrls'] is Iterable)
          for (final url in data['draftScanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
      ];
      final draftUrls = [...existingDraftUrls, ...submittedUrls];

      transaction.update(submissionRef, {
        'answer': '',
        'scanUrl': FieldValue.delete(),
        'scanUrls': FieldValue.delete(),
        'draftScanUrls': draftUrls.isEmpty ? FieldValue.delete() : draftUrls,
        'draftUpdatedAt': FieldValue.serverTimestamp(),
        'submittedAt': FieldValue.delete(),
        'status': 'Draft',
        'reviewStatus': 'pending_review',
        'gradingSource': FieldValue.delete(),
        'score': FieldValue.delete(),
        'feedback': FieldValue.delete(),
      });
    });
  }

  static Future<void> removeSubmissionImageDraft({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required String imageUrl,
  }) {
    final submissionRef = _submissions(subjectId, taskId).doc(studentEmail);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(submissionRef);
      if (!snapshot.exists) {
        throw StateError('The saved photos could not be found.');
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      final draftUrls = <String>[
        if (data['draftScanUrls'] is Iterable)
          for (final url in data['draftScanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
      ];
      if (!draftUrls.remove(imageUrl)) {
        throw StateError('This photo is no longer in the saved set.');
      }

      transaction.update(submissionRef, {
        'draftScanUrls': draftUrls.isEmpty ? FieldValue.delete() : draftUrls,
        'draftUpdatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> removeSubmittedImage({
    required String subjectId,
    required String taskId,
    required String studentEmail,
    required String imageUrl,
  }) {
    final submissionRef = _submissions(subjectId, taskId).doc(studentEmail);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(submissionRef);
      if (!snapshot.exists) {
        throw StateError('The submission could not be found.');
      }

      final data = snapshot.data() ?? const <String, dynamic>{};
      if (data['status'] == 'Submitted' || data['status'] == 'Graded') {
        throw StateError('Submitted photos cannot be removed.');
      }

      final urls = <String>[
        if (data['scanUrls'] is Iterable)
          for (final url in data['scanUrls'] as Iterable)
            if (url is String && url.trim().isNotEmpty) url.trim(),
        if (data['scanUrls'] is! Iterable &&
            data['scanUrl'] is String &&
            (data['scanUrl'] as String).trim().isNotEmpty)
          (data['scanUrl'] as String).trim(),
      ];
      if (!urls.remove(imageUrl)) {
        throw StateError('This photo is no longer part of the submission.');
      }

      transaction.update(submissionRef, {
        'scanUrls': urls.isEmpty ? FieldValue.delete() : urls,
        'scanUrl': urls.isEmpty ? FieldValue.delete() : urls.first,
      });
    });
  }
}
