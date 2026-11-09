import 'package:cloud_firestore/cloud_firestore.dart';

List<QueryDocumentSnapshot<Map<String, dynamic>>> sortPostsNewestFirst(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> posts,
) {
  final sortedPosts = posts.toList();
  sortedPosts.sort((a, b) {
    final aDate = _postedDate(a.data()['postedAt']);
    final bDate = _postedDate(b.data()['postedAt']);
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });
  return sortedPosts;
}

String formatPostedDate(Object? value) {
  final date = _postedDate(value);
  if (date == null) return 'Date unavailable';

  final localDate = date.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Posted ${months[localDate.month - 1]} ${localDate.day}, ${localDate.year}';
}

DateTime? _postedDate(Object? value) {
  return switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => null,
  };
}
