import json
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, SimpleTestCase, override_settings

from .ocr import OCRProviderError
from .train_model import ModelArtifactError
from .views import _labeled_student_name_mismatch


@override_settings(ALLOWED_HOSTS=['testserver', 'localhost'])
class GradeSheetApiTests(SimpleTestCase):
    def setUp(self):
        self.client = Client()
        self.payload = {
            'expected_answers': {
                'criterion_1': 'Plants use sunlight to make food.',
            },
        }

    def test_labeled_name_check_only_reports_a_clear_name_mismatch(self):
        self.assertIsNone(
            _labeled_student_name_mismatch(
                'Name: Maria Dela Cruz\nAnswer: Photosynthesis',
                'Maria Dela Cruz',
            )
        )
        self.assertIsNone(
            _labeled_student_name_mismatch(
                'Student name: Maria Dela Cruz\nAnswer: Photosynthesis',
                'Maria Dela Cruz',
            )
        )
        self.assertEqual(
            _labeled_student_name_mismatch(
                'Name: Juan Santos\nAnswer: Photosynthesis',
                'Maria Dela Cruz',
            ),
            'Juan Santos',
        )
        self.assertIsNone(
            _labeled_student_name_mismatch(
                'Name: __________\nAnswer: Photosynthesis',
                'Maria Dela Cruz',
            )
        )

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_essay_score')
    def test_essay_tasks_use_separate_model_and_require_review(
        self,
        predict_essay,
        _authenticate,
    ):
        predict_essay.return_value = {
            'predicted_score': 6,
            'max_score': 6,
            'confidence': 0.82,
            'requires_human_review': True,
            'model_scope': 'AES2 free-form essay scoring',
        }
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                'task_type': 'essay',
                'essay_text': 'An essay about the effects of technology.',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['essay_result']['predicted_score'], 6)
        self.assertTrue(response.json()['requires_human_review'])
        predict_essay.assert_called_once()

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_score')
    def test_json_answers_return_model_score_and_keep_human_review(
        self,
        predict,
        _authenticate,
    ):
        predict.return_value = {
            'predicted_score': 4,
            'max_score': 5,
            'confidence': 0.8,
        }
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                **self.payload,
                'answer_text': 'Plants use sunlight to make food.',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['ai_score'], 80.0)
        self.assertEqual(result['percentage'], 100.0)
        self.assertEqual(result['extracted_text'], 'Plants use sunlight to make food.')
        self.assertTrue(result['requires_human_review'])

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_score')
    def test_analytic_rubric_grades_each_criterion_against_its_levels(
        self,
        predict,
        _authenticate,
    ):
        def score_level(_answer, expected, _question):
            if 'Some evidence' in expected:
                return {'predicted_score': 5, 'max_score': 5, 'confidence': 0.9}
            if 'Clear evidence' in expected:
                return {'predicted_score': 4, 'max_score': 5, 'confidence': 0.8}
            return {'predicted_score': 1, 'max_score': 5, 'confidence': 0.8}

        predict.side_effect = score_level
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                'expected_answers': {},
                'task_instructions': 'Explain the water cycle.',
                'answer_text': 'Water evaporates and falls as rain.',
                'rubric': {
                    'type': 'Analytic',
                    'criteria': [{
                        'title': 'Evidence',
                        'levels': [
                            'No relevant evidence',
                            'Some evidence',
                            'Clear evidence',
                        ],
                    }],
                },
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['ai_score'], 66.67)
        self.assertEqual(result['details'][0]['selected_level'], 2)
        self.assertEqual(result['details'][0]['rubric_level'], 'Some evidence')
        self.assertEqual(result['criterion_results'][0]['selectedLevel'], 2)
        self.assertEqual(predict.call_count, 3)

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_score')
    def test_analytic_rubric_weights_scores_and_returns_feedback(
        self,
        predict,
        _authenticate,
    ):
        def score_level(_answer, _expected, question):
            if question.startswith('criterion_2'):
                return {'predicted_score': 1, 'max_score': 5, 'confidence': 0.8}
            score = 5 if 'Complete coverage' in _expected else 1
            return {'predicted_score': score, 'max_score': 5, 'confidence': 0.9}

        predict.side_effect = score_level
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                'expected_answers': {},
                'task_title': 'Explain photosynthesis',
                'task_instructions': 'Explain how plants make food.',
                'learning_objectives': ['Describe light absorption'],
                'expected_concepts': ['chlorophyll', 'light energy'],
                'submission_metadata': {'source': 'hardcopy_scan', 'page_count': 1},
                'answer_text': 'Plants absorb light. Chlorophyll captures sunlight.',
                'rubric': {
                    'type': 'Analytic',
                    'criteria': [
                        {
                            'title': 'Completeness',
                            'score': '40',
                            'levels': ['Limited coverage', 'Complete coverage'],
                        },
                        {
                            'title': 'Accuracy',
                            'score': '60',
                            'levels': ['Limited accuracy', 'Accurate explanation'],
                        },
                    ],
                },
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['ai_pre_score'], 70.0)
        self.assertEqual(result['confidence'], 0.85)
        self.assertEqual(result['criterion_scores'][0]['criterion'], 'Completeness')
        self.assertEqual(result['criterion_scores'][0]['score'], 40.0)
        self.assertEqual(result['criterion_scores'][0]['max_score'], 40.0)
        self.assertEqual(result['criterion_scores'][0]['confidence'], 0.9)
        self.assertEqual(
            result['criterion_scores'][0]['explanation'],
            'The submitted response most closely matches the rubric level: '
            'Complete coverage.',
        )
        self.assertEqual(result['criterion_scores'][1]['criterion'], 'Accuracy')
        self.assertEqual(result['criterion_scores'][1]['score'], 30.0)
        self.assertEqual(result['criterion_scores'][1]['max_score'], 60.0)
        self.assertEqual(result['criterion_scores'][1]['confidence'], 0.8)
        self.assertTrue(
            all(0 <= item['similarity'] <= 1 for item in result['criterion_scores'])
        )
        self.assertEqual(len(result['feedback']), 2)
        self.assertEqual(result['text_features']['word_count'], 6)
        self.assertEqual(result['submission_metadata']['page_count'], 1)
        self.assertTrue(all(
            'Rubric criterion:' in call.args[1]
            and 'Performance level:' in call.args[1]
            and 'Task title: Explain photosynthesis' in call.args[1]
            and 'Task instructions: Explain how plants make food.' in call.args[1]
            and 'Learning objective: Describe light absorption' in call.args[1]
            and 'Expected concept: chlorophyll' in call.args[1]
            and 'Expected concept: light energy' in call.args[1]
            for call in predict.call_args_list
        ))
        self.assertIn('chlorophyll', result['text_features']['matched_keywords'])

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_score')
    def test_weighted_criterion_list_uses_criterion_and_description(
        self,
        predict,
        _authenticate,
    ):
        predict.return_value = {
            'predicted_score': 4,
            'max_score': 5,
            'confidence': 0.9,
        }
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                'task_title': 'Explain photosynthesis',
                'instructions': 'Describe how plants use light.',
                'rubric': [{
                    'name': 'Accuracy',
                    'description': 'Scientific facts are correct',
                    'weight': 40,
                }],
                'student_text': 'Plants use light to make food.',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['ai_pre_score'], 80.0)
        self.assertEqual(result['criterion_scores'][0]['criterion'], 'Accuracy')
        self.assertEqual(result['criterion_scores'][0]['score'], 32.0)
        self.assertEqual(result['criterion_scores'][0]['max_score'], 40.0)
        self.assertIn('Rubric criterion: Accuracy', predict.call_args.args[1])
        self.assertIn(
            'Criterion description: Scientific facts are correct',
            predict.call_args.args[1],
        )
        self.assertIn(
            'Task title: Explain photosynthesis',
            predict.call_args.args[1],
        )
        self.assertIn(
            'Task instructions: Describe how plants use light.',
            predict.call_args.args[1],
        )

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_score')
    def test_holistic_rubric_uses_selected_band_points(
        self,
        predict,
        _authenticate,
    ):
        def score_level(_answer, expected, _question):
            score = 5 if 'Meets expectations' in expected else 1
            return {'predicted_score': score, 'max_score': 5, 'confidence': 0.9}

        predict.side_effect = score_level
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                'expected_answers': {},
                'answer_text': 'A complete response.',
                'rubric': {
                    'type': 'Holistic',
                    'title': 'Overall quality',
                    'criteria': [
                        {'points': '0', 'description': 'Does not meet expectations'},
                        {'points': '5', 'description': 'Meets expectations'},
                        {'points': '10', 'description': 'Exceeds expectations'},
                    ],
                },
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['score'], 5.0)
        self.assertEqual(result['total'], 10.0)
        self.assertEqual(result['ai_score'], 50.0)
        self.assertEqual(result['criterion_results'][0]['rubricLevel'], 'Meets expectations')
        self.assertEqual(predict.call_count, 3)

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.predict_score')
    def test_rubric_evidence_and_curriculum_matches_are_returned(
        self,
        predict,
        _authenticate,
    ):
        predict.return_value = {
            'predicted_score': 4,
            'max_score': 5,
            'confidence': 0.9,
        }
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                **self.payload,
                'answer_text': 'Plants use sunlight and chlorophyll to make food.',
                'rubric': {'type': 'Analytic', 'criteria': [{'title': 'Content'}]},
                'curriculum_standards': {
                    'criterion_1': ['sunlight', 'chlorophyll', 'missing concept'],
                },
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['criterion_results'][0]['title'], 'Content')
        self.assertEqual(result['matched_curriculum_standards'], ['chlorophyll', 'sunlight'])
        self.assertEqual(result['missing_curriculum_standards'], ['missing concept'])

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.OCRGrader.analyze_image')
    @patch('grading_api.views.predict_score')
    def test_visual_rubric_recommendations_are_returned_and_require_review(
        self,
        predict,
        analyze_image,
        _authenticate,
    ):
        predict.return_value = {
            'predicted_score': 4,
            'max_score': 5,
            'confidence': 0.9,
        }
        analyze_image.return_value = {
            'text': 'A complete answer.',
            'ocr_engine': 'tesseract',
            'ocr_confidence': 0.9,
            'visual_features': {
                'document_detected': True,
                'document_area_ratio': 0.9,
                'ink_coverage': 0.08,
                'edge_density': 0.05,
                'content_regions': 22,
                'horizontal_balance': 0.95,
                'vertical_balance': 0.92,
            },
        }
        response = self.client.post(
            '/api/grade/',
            data={
                'payload': json.dumps({
                    'expected_answers': {'criterion_1': 'A complete answer.'},
                    'rubric': {
                        'type': 'Analytic',
                        'criteria': [{
                            'title': 'Organization and neatness',
                            'levels': ['Beginning', 'Developing', 'Proficient', 'Advanced'],
                        }],
                    },
                    'answer_text': 'A complete answer.',
                }),
                'images': SimpleUploadedFile('page.jpg', b'page', 'image/jpeg'),
            },
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(len(result['visual_recommendations']), 1)
        self.assertIn('recommendedScore', result['visual_recommendations'][0])
        self.assertEqual(result['visual_recommendations'][0]['maxLevel'], 4)
        self.assertTrue(result['requires_human_review'])
        self.assertIn(
            'Visual rubric criteria require instructor verification against the original scan.',
            result['review_reasons'],
        )

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.OCRGrader.analyze_image')
    @patch('grading_api.views.predict_score')
    def test_scanned_pages_are_read_and_graded(
        self,
        predict,
        analyze_image,
        _authenticate,
    ):
        predict.return_value = {
            'predicted_score': 3,
            'max_score': 5,
            'confidence': 0.99,
        }
        analyze_image.return_value = {
            'text': 'OCR answer',
            'ocr_engine': 'easyocr',
            'ocr_confidence': 0.91,
            'visual_features': {
                'document_detected': True,
                'document_area_ratio': 0.8,
                'ink_coverage': 0.12,
                'edge_density': 0.07,
                'content_regions': 12,
                'horizontal_balance': 0.9,
                'vertical_balance': 0.8,
            },
        }
        response = self.client.post(
            '/api/grade/',
            data={
                'payload': json.dumps(self.payload),
                'images': [
                    SimpleUploadedFile('page-one.jpg', b'page one', 'image/jpeg'),
                    SimpleUploadedFile('page-two.jpg', b'page two', 'image/jpeg'),
                ],
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['result']['extracted_text'], 'OCR answer\nOCR answer')
        self.assertEqual(response.json()['result']['ai_score'], 60.0)
        visual_analysis = response.json()['result']['visual_analysis']
        self.assertEqual(visual_analysis['pages_analyzed'], 2)
        self.assertEqual(visual_analysis['pages_with_detected_document'], 2)
        self.assertEqual(visual_analysis['ocr_engine'], 'easyocr')
        self.assertEqual(visual_analysis['ocr_confidence'], 0.91)
        self.assertEqual(analyze_image.call_count, 2)
        predict.assert_called_once_with(
            'OCR answer\nOCR answer',
            'Plants use sunlight to make food.',
            'criterion_1',
        )

    def test_scans_without_readable_text_require_instructor_review(self):
        with (
            patch('grading_api.views.require_instructor', return_value=None),
            patch(
                'grading_api.views.OCRGrader.analyze_image',
                return_value={
                    'text': '',
                    'ocr_engine': 'tesseract',
                    'ocr_confidence': None,
                    'visual_features': {
                        'document_detected': False,
                        'document_area_ratio': 1.0,
                        'ink_coverage': 0.0,
                        'edge_density': 0.0,
                        'content_regions': 0,
                        'horizontal_balance': 0.0,
                        'vertical_balance': 0.0,
                    },
                },
            ),
        ):
            response = self.client.post(
                '/api/grade/',
                data={
                    'payload': json.dumps(self.payload),
                    'images': SimpleUploadedFile('blank.jpg', b'blank', 'image/jpeg'),
                },
            )

        self.assertEqual(response.status_code, 422)
        self.assertTrue(response.json()['requires_human_review'])

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.OCRGrader.analyze_image')
    @patch('grading_api.views.predict_score')
    def test_scan_with_a_different_labeled_student_name_is_not_scored(
        self,
        predict,
        analyze_image,
        _authenticate,
    ):
        analyze_image.return_value = {
            'text': 'Name: Juan Santos\nAnswer: Plants use sunlight.',
            'ocr_engine': 'easyocr',
            'ocr_confidence': 0.95,
            'visual_features': {'document_detected': True},
        }
        response = self.client.post(
            '/api/grade/',
            data={
                'payload': json.dumps({
                    **self.payload,
                    'submission_metadata': {
                        'source': 'hardcopy_scan',
                        'expected_student_name': 'Maria Dela Cruz',
                    },
                }),
                'images': SimpleUploadedFile('page.jpg', b'page', 'image/jpeg'),
            },
        )

        self.assertEqual(response.status_code, 422)
        self.assertEqual(
            response.json()['submission_mismatch'],
            {
                'type': 'student_name',
                'expected_student_name': 'Maria Dela Cruz',
                'detected_student_name': 'Juan Santos',
            },
        )
        self.assertIn('Juan Santos', response.json()['error'])
        self.assertIn('Maria Dela Cruz', response.json()['error'])
        predict.assert_not_called()

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.OCRGrader.analyze_image')
    @patch('grading_api.views.predict_score')
    def test_low_confidence_ocr_returns_no_score(
        self,
        predict,
        analyze_image,
        _authenticate,
    ):
        analyze_image.return_value = {
            'text': 'A response that OCR may have misread.',
            'ocr_engine': 'easyocr',
            'ocr_confidence': 0.2,
            'visual_features': {'document_detected': True},
        }
        response = self.client.post(
            '/api/grade/',
            data={
                'payload': json.dumps(self.payload),
                'images': SimpleUploadedFile('unclear.jpg', b'image', 'image/jpeg'),
            },
        )

        self.assertEqual(response.status_code, 422)
        self.assertEqual(
            response.json()['error'],
            'Scan quality too poor for reliable grading.',
        )
        self.assertTrue(response.json()['requires_human_review'])
        self.assertNotIn('result', response.json())
        predict.assert_not_called()

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch('grading_api.views.OCRGrader.analyze_image')
    @patch('grading_api.views.predict_score')
    def test_gemini_scan_without_ocr_confidence_is_graded_for_review(
        self,
        predict,
        analyze_image,
        _authenticate,
    ):
        predict.return_value = {
            'predicted_score': 3,
            'max_score': 5,
            'confidence': 0.6,
        }
        analyze_image.return_value = {
            'text': 'Gemini transcription.',
            'ocr_engine': 'gemini',
            'ocr_confidence': None,
            'visual_features': {
                'document_detected': True,
                'document_area_ratio': 0.8,
                'ink_coverage': 0.12,
                'edge_density': 0.07,
                'content_regions': 12,
                'horizontal_balance': 0.9,
                'vertical_balance': 0.8,
            },
        }
        response = self.client.post(
            '/api/grade/',
            data={
                'payload': json.dumps(self.payload),
                'images': SimpleUploadedFile('page.jpg', b'image', 'image/jpeg'),
            },
        )

        self.assertEqual(response.status_code, 200)
        result = response.json()['result']
        self.assertEqual(result['visual_analysis']['ocr_engine'], 'gemini')
        self.assertIsNone(result['visual_analysis']['ocr_confidence'])
        self.assertTrue(result['requires_human_review'])
        self.assertFalse(result['assisted_grading_eligible'])
        self.assertIn(
            'The OCR provider did not return a confidence score; verify the transcription against the original scan.',
            result['review_reasons'],
        )
        predict.assert_called_once()

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch(
        'grading_api.views.OCRGrader.analyze_image',
        side_effect=OCRProviderError('Gemini OCR fallback is not configured.'),
    )
    def test_ocr_provider_error_is_returned_without_generic_failure(
        self,
        _analyze_image,
        _authenticate,
    ):
        response = self.client.post(
            '/api/grade/',
            data={
                'payload': json.dumps(self.payload),
                'images': SimpleUploadedFile('page.jpg', b'page', 'image/jpeg'),
            },
        )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.json()['error'],
            'Gemini OCR fallback is not configured.',
        )

    @patch('grading_api.views.require_instructor', return_value=None)
    def test_empty_references_are_rejected(self, _authenticate):
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                'expected_answers': {'criterion_1': '  '},
                'answer_text': 'An answer.',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)

    @patch('grading_api.views.require_instructor', return_value=None)
    def test_non_object_json_is_rejected(self, _authenticate):
        response = self.client.post(
            '/api/grade/',
            data=json.dumps(['not', 'an', 'object']),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)

    def test_grading_requires_instructor_authentication(self):
        response = self.client.post(
            '/api/grade/',
            data=json.dumps(self.payload),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 401)

    @patch('grading_api.views.require_instructor', return_value=None)
    @patch(
        'grading_api.views.predict_score',
        side_effect=ModelArtifactError('The grading model is missing.'),
    )
    def test_missing_model_is_reported_without_retraining(
        self,
        _predict,
        _authenticate,
    ):
        response = self.client.post(
            '/api/grade/',
            data=json.dumps({
                **self.payload,
                'answer_text': 'Plants use sunlight to make food.',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()['error'], 'The grading model is missing.')

    @override_settings(GRADING_ALLOWED_ORIGINS=['https://app.example'])
    def test_configured_web_origin_can_call_grading_api(self):
        response = self.client.options(
            '/api/grade/',
            HTTP_ORIGIN='https://app.example',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
        )

        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            response['Access-Control-Allow-Origin'],
            'https://app.example',
        )
