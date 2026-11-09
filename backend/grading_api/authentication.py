import logging

from django.conf import settings
from django.http import HttpRequest, JsonResponse
from firebase_admin import auth, firestore, get_app, initialize_app
from firebase_admin.exceptions import FirebaseError
from google.auth.exceptions import DefaultCredentialsError

logger = logging.getLogger(__name__)


def require_instructor(request: HttpRequest) -> JsonResponse | None:
    authorization = request.headers.get('Authorization', '')
    scheme, separator, token = authorization.partition(' ')
    if not separator or scheme.lower() != 'bearer' or not token.strip():
        return JsonResponse({'error': 'Sign in as an instructor to use AI grading.'}, status=401)

    try:
        try:
            get_app()
        except ValueError:
            initialize_app(options={'projectId': settings.FIREBASE_PROJECT_ID})
    except (DefaultCredentialsError, FirebaseError, ValueError):
        logger.exception('Firebase Admin SDK could not be initialized.')
        return JsonResponse(
            {'error': 'The grading service is not configured for Firebase authentication.'},
            status=503,
        )

    try:
        identity = auth.verify_id_token(token.strip())
    except (auth.InvalidIdTokenError, ValueError):
        return JsonResponse({'error': 'The Firebase sign-in token is invalid or expired.'}, status=401)
    except FirebaseError:
        logger.exception('Firebase could not verify a grading API token.')
        return JsonResponse(
            {'error': 'Firebase authentication is temporarily unavailable.'},
            status=503,
        )

    email = identity.get('email')
    if not isinstance(email, str) or not email.strip():
        return JsonResponse({'error': 'An instructor email is required.'}, status=403)

    try:
        accounts = (
            firestore.client()
            .collection('instructor_accounts')
            .where('email', '==', email.strip())
            .limit(1)
            .stream()
        )
        account = next(accounts, None)
    except (DefaultCredentialsError, FirebaseError):
        logger.exception('Firebase could not verify the instructor account.')
        return JsonResponse(
            {'error': 'Instructor verification is temporarily unavailable.'},
            status=503,
        )

    if account is None or account.to_dict().get('isActive') is not True:
        return JsonResponse(
            {'error': 'An active instructor account is required to use AI grading.'},
            status=403,
        )
    return None
