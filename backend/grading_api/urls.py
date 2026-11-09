from django.urls import path

from .views import grade_sheet_api, train_model_api

urlpatterns = [
    path('api/health/', lambda request: __import__('django.http').http.HttpResponse('OK')),
    path('api/grade/', grade_sheet_api, name='grade_sheet_api'),
    path('api/train-model/', train_model_api, name='train_model_api'),
]
