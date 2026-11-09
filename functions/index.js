const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

initializeApp();

const DEFAULT_STUDENT_PASSWORD = 'student123';
const DASHBOARD_ADMIN_EMAILS = new Set([
  'admin@visiongrade.edu',
  'bruce.admin@visiongrade.edu'
]);

exports.resetStudentPassword = onCall({ region: 'us-central1' }, async request => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in as an administrator to reset student passwords.');
  }

  const adminEmail = String(request.auth.token.email || '').toLowerCase();
  if (!DASHBOARD_ADMIN_EMAILS.has(adminEmail)) {
    throw new HttpsError('permission-denied', 'Only dashboard administrators can reset student passwords.');
  }

  const studentId = typeof request.data?.studentId === 'string'
    ? request.data.studentId.trim()
    : '';
  if (!studentId) {
    throw new HttpsError('invalid-argument', 'A student profile ID is required.');
  }

  const studentRef = getFirestore().collection('students').doc(studentId);
  const studentSnapshot = await studentRef.get();
  if (!studentSnapshot.exists) {
    throw new HttpsError('not-found', 'The student profile was not found.');
  }

  const student = studentSnapshot.data();
  if (student.hasAccount === false) {
    throw new HttpsError('failed-precondition', 'This student does not have an account to reset.');
  }

  const authUid = typeof student.authUid === 'string' && student.authUid.trim()
    ? student.authUid.trim()
    : studentSnapshot.id;

  try {
    const authUser = await getAuth().getUser(authUid);
    if (student.email && authUser.email
      && student.email.trim().toLowerCase() !== authUser.email.trim().toLowerCase()) {
      throw new HttpsError('failed-precondition', 'The student profile email does not match its account.');
    }
    await getAuth().updateUser(authUid, { password: DEFAULT_STUDENT_PASSWORD });
    return { email: authUser.email || student.email || '' };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'The student login account was not found.');
    }
    console.error('Unable to reset student password.', error);
    throw new HttpsError('internal', 'Unable to reset the student password. Try again later.');
  }
});
