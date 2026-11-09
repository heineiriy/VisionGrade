from django.conf import settings
from django.http import HttpResponse


class GradingCorsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        is_grading_api = request.path in {'/api/grade/', '/api/train-model/'}
        if is_grading_api and request.method == 'OPTIONS':
            response = HttpResponse(status=204)
        else:
            response = self.get_response(request)

        origin = request.headers.get('Origin')
        allowed_origins = getattr(settings, 'GRADING_ALLOWED_ORIGINS', ())
        if is_grading_api and origin in allowed_origins:
            response['Access-Control-Allow-Origin'] = origin
            response['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
            response['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
            response['Vary'] = 'Origin'
        return response
