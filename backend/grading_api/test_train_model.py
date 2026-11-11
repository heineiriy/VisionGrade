import io
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

import cv2
import numpy as np
from PIL import Image

from .features import AnswerPairFeatures
from .export_teacher_feedback import training_row_from_submission
from .evaluate_ocr_feedback import evaluate_ocr_feedback
from .ocr import OCRGrader
from .train_model import (
    BEETLE_TRAIN_PATH,
    DIGIKLAUSUR_TRAIN_PATH,
    JORGPT_TRAIN_PATH,
    JORGPT_VALIDATION_PATH,
    ModelArtifactError,
    SCIENTSBANK_TRAIN_PATH,
    build_text,
    _load_model_cached,
    load_model,
    load_dataset,
    _read_dataset,
)
from .essay_model import _load_essay_dataset, load_essay_model


class ModelLoadTests(unittest.TestCase):
    def tearDown(self):
        _load_model_cached.cache_clear()

    def test_missing_short_answer_model_does_not_trigger_training(self):
        with TemporaryDirectory() as directory:
            model_path = Path(directory) / 'missing.joblib'
            with patch('grading_api.train_model.train_scoring_model') as train:
                with self.assertRaises(ModelArtifactError):
                    load_model(model_path)
            train.assert_not_called()

    def test_short_answer_model_is_loaded_once_until_artifact_changes(self):
        with TemporaryDirectory() as directory:
            model_path = Path(directory) / 'model.joblib'
            model_path.write_bytes(b'first model')
            model = object()

            with patch('grading_api.train_model.joblib.load', return_value=model) as load:
                self.assertIs(load_model(model_path), model)
                self.assertIs(load_model(model_path), model)
                load.assert_called_once_with(str(model_path.resolve()))

                model_path.write_bytes(b'replacement model')
                self.assertIs(load_model(model_path), model)

            self.assertEqual(load.call_count, 2)

    def test_missing_essay_model_does_not_trigger_training(self):
        with TemporaryDirectory() as directory:
            model_path = Path(directory) / 'missing.joblib'
            with patch('grading_api.essay_model.train_essay_model') as train:
                with self.assertRaises(ModelArtifactError):
                    load_essay_model(model_path)
            train.assert_not_called()


class LoadDatasetTests(unittest.TestCase):
    def test_aes2_dataset_is_kept_as_essay_scoring_data(self):
        dataset = _load_essay_dataset()
        self.assertGreaterEqual(len(dataset), 17000)
        self.assertTrue(dataset['score'].between(1, 6).all())
        self.assertNotIn('expected_answer', dataset.columns)

    def test_default_training_data_includes_public_train_splits(self):
        self.assertTrue(SCIENTSBANK_TRAIN_PATH.is_file())
        self.assertTrue(BEETLE_TRAIN_PATH.is_file())
        self.assertTrue(DIGIKLAUSUR_TRAIN_PATH.is_file())

        dataset = load_dataset()
        scientsbank_rows = dataset[
            dataset['question_id'].str.startswith('scientsbank:')
        ]
        beetle_rows = dataset[dataset['question_id'].str.startswith('beetle:')]

        self.assertEqual(len(scientsbank_rows), 4830)
        self.assertEqual(scientsbank_rows['question_id'].nunique(), 135)
        self.assertEqual(set(scientsbank_rows['score'].unique()), {0.0, 3.0, 5.0})
        self.assertEqual(len(beetle_rows), 3917)
        self.assertEqual(beetle_rows['question_id'].nunique(), 36)
        digiklausur_rows = dataset[
            dataset['question_id'].str.startswith('digiklausur_asag:')
        ]
        self.assertEqual(len(digiklausur_rows), 607)
        self.assertEqual(digiklausur_rows['question_id'].nunique(), 17)

    def test_default_training_data_uses_only_jorgpt_training_questions(self):
        self.assertTrue(JORGPT_TRAIN_PATH.is_file())

        dataset = load_dataset()
        jorgpt_rows = dataset[
            dataset['question_id'].str.startswith('jorgpt_en:')
        ]
        validation_rows = _read_dataset(JORGPT_VALIDATION_PATH)

        self.assertEqual(len(jorgpt_rows), 2473)
        self.assertEqual(jorgpt_rows['question_id'].nunique(), 40)
        self.assertEqual(
            set(jorgpt_rows['score'].unique()),
            {0.0, 1.0, 2.0, 3.0, 4.0, 5.0},
        )
        self.assertEqual(len(validation_rows), 530)
        self.assertEqual(validation_rows['question_id'].nunique(), 10)
        self.assertTrue(
            set(jorgpt_rows['question_id']).isdisjoint(
                validation_rows['question_id']
            )
        )
        self.assertTrue(
            dataset['question_id'].str.startswith('digiklausur_asag:').any()
        )

    def test_question_identifiers_do_not_change_grading_features(self):
        self.assertEqual(
            build_text('Student answer', 'Expected answer', 'question-1'),
            build_text('Student answer', 'Expected answer', 'question-2'),
        )

    def test_pair_features_distinguish_matching_from_unrelated_answers(self):
        examples = [
            build_text(
                'The water evaporated, leaving the salt.',
                'The water evaporated, leaving the salt.',
            ),
            build_text(
                'The salt was frozen into ice.',
                'The water evaporated, leaving the salt.',
            ),
        ]
        features = AnswerPairFeatures().fit_transform(examples)

        self.assertEqual(features.shape, (2, 8))
        self.assertGreater(features[0, 0], features[1, 0])


class ExportTeacherFeedbackTests(unittest.TestCase):
    def _snapshot(self, path, data):
        snapshot = Mock()
        snapshot.reference.path = path
        snapshot.to_dict.return_value = data
        return snapshot

    def test_exports_only_teacher_corrected_examples_without_student_identity(self):
        snapshot = self._snapshot(
            'subjects/science/posts/task-1/submissions/student@example.com',
            {
                'studentName': 'Student Name',
                'studentEmail': 'student@example.com',
                'aiTrainingExample': {
                    'student_answer': '  water evaporates  ',
                    'expected_answer': 'water changes into vapor',
                    'score': 4.5,
                    'teacher_corrected': True,
                },
            },
        )

        row = training_row_from_submission(snapshot)

        self.assertEqual(
            row,
            {
                'question_id': 'science:task-1',
                'student_answer': 'water evaporates',
                'expected_answer': 'water changes into vapor',
                'score': 4.5,
                'teacher_corrected': True,
            },
        )
        self.assertNotIn('studentName', row)
        self.assertNotIn('studentEmail', row)

    def test_ignores_unreviewed_or_invalid_examples(self):
        unreviewed = self._snapshot(
            'subjects/science/posts/task-1/submissions/student-1',
            {
                'aiTrainingExample': {
                    'student_answer': 'answer',
                    'expected_answer': 'reference',
                    'score': 4,
                    'teacher_corrected': False,
                },
            },
        )
        invalid_score = self._snapshot(
            'subjects/science/posts/task-1/submissions/student-2',
            {
                'aiTrainingExample': {
                    'student_answer': 'answer',
                    'expected_answer': 'reference',
                    'score': 6,
                    'teacher_corrected': True,
                },
            },
        )

        self.assertIsNone(training_row_from_submission(unreviewed))
        self.assertIsNone(training_row_from_submission(invalid_score))

    def test_exports_reviewed_transcription_and_original_ocr_separately(self):
        snapshot = self._snapshot(
            'subjects/science/posts/task-1/submissions/student-1',
            {
                'aiTrainingExample': {
                    'student_answer': 'The water cycle has three steps.',
                    'corrected_text': 'The water cycle has three steps.',
                    'ocr_text': 'The woter cycle has three steps.',
                    'ocr_engine': 'easyocr',
                    'ocr_confidence': 0.81,
                    'expected_answer': 'The water cycle includes three steps.',
                    'score': 4,
                    'teacher_corrected': True,
                },
            },
        )

        row = training_row_from_submission(snapshot)

        self.assertEqual(row['student_answer'], 'The water cycle has three steps.')
        self.assertEqual(row['corrected_text'], 'The water cycle has three steps.')
        self.assertEqual(row['ocr_text'], 'The woter cycle has three steps.')
        self.assertEqual(row['ocr_engine'], 'easyocr')
        self.assertEqual(row['ocr_confidence'], 0.81)

    def test_evaluates_ocr_errors_against_corrected_transcriptions(self):
        with TemporaryDirectory() as directory:
            dataset_path = Path(directory) / 'ocr_feedback.csv'
            dataset_path.write_text(
                'ocr_text,corrected_text,ocr_engine\n'
                'hello word,hello world,easyocr\n'
                ',unused,azure_computer_vision\n',
                encoding='utf-8',
            )

            report = evaluate_ocr_feedback(dataset_path)

        self.assertEqual(report['evaluated_samples'], 1)
        self.assertEqual(report['skipped_samples'], 1)
        self.assertEqual(report['overall']['wer'], 0.5)
        self.assertEqual(report['overall']['cer'], 0.0909)
        self.assertIn('easyocr', report['by_engine'])


class ImageSegmentationTests(unittest.TestCase):
    def test_preprocessing_caps_large_images_before_expensive_operations(self):
        image_bytes = io.BytesIO()
        Image.new('RGB', (4000, 3000), color='white').save(
            image_bytes,
            format='JPEG',
        )
        observed_shapes = []

        def segment(image):
            observed_shapes.append(image.shape)
            return image, False, 1.0

        with (
            patch.object(OCRGrader, '_segment_document', side_effect=segment),
            patch(
                'grading_api.ocr.pytesseract.image_to_osd',
                return_value={'rotate': 0},
            ),
        ):
            processed, diagnostics = OCRGrader()._prepare_image(
                image_bytes.getvalue(),
            )

        self.assertEqual(observed_shapes, [(1800, 2400, 3)])
        self.assertEqual(max(processed.shape), 2400)
        self.assertEqual(diagnostics['image_size'], {
            'width': 4000,
            'height': 3000,
        })

    def test_azure_fallback_returns_text_without_confidence_score(self):
        image = np.full((120, 120), 255, dtype=np.uint8)

        with (
            patch.object(
                OCRGrader,
                '_prepare_image',
                return_value=(image, {'document_detected': True}),
            ),
            patch.object(OCRGrader, '_easyocr_reader', return_value=None),
            patch.object(
                OCRGrader,
                '_read_with_azure_vision',
                return_value=('The response', None),
            ),
        ):
            result = OCRGrader().analyze_image(b'page')

        self.assertEqual(result['text'], 'The response')
        self.assertEqual(result['ocr_engine'], 'azure_computer_vision')
        self.assertIsNone(result['ocr_confidence'])

    def test_low_confidence_easyocr_retries_with_azure(self):
        image = np.full((120, 120), 255, dtype=np.uint8)
        reader = Mock()
        reader.readtext.return_value = [([[0, 0]], 'unclear', 0.2)]

        with (
            patch.object(
                OCRGrader,
                '_prepare_image',
                return_value=(image, {'document_detected': True}),
            ),
            patch.object(OCRGrader, '_easyocr_reader', return_value=reader),
            patch.object(
                OCRGrader,
                '_read_with_azure_vision',
                return_value=('Verified fallback text', None),
            ) as azure,
        ):
            result = OCRGrader().analyze_image(b'page')

        self.assertEqual(result['text'], 'Verified fallback text')
        self.assertEqual(result['ocr_engine'], 'azure_computer_vision')
        self.assertIsNone(result['ocr_confidence'])
        azure.assert_called_once_with(b'page')

    def test_azure_vision_requires_backend_configuration(self):
        with (
            patch.dict(
                'os.environ',
                {
                    'AZURE_VISION_ENDPOINT': '',
                    'AZURE_VISION_KEY': '',
                },
                clear=False,
            ),
            self.assertRaisesRegex(
                RuntimeError,
                'Azure Vision OCR fallback is not configured',
            ),
        ):
            OCRGrader._read_with_azure_vision(b'page')

    def test_azure_vision_sends_image_and_returns_transcription(self):
        response = Mock(status_code=200)
        response.json.return_value = {
            'readResult': {
                'blocks': [{
                    'lines': [
                        {'text': 'A handwritten answer.'},
                        {'text': 'Second line.'},
                    ],
                }],
            },
        }

        with (
            patch.dict(
                'os.environ',
                {
                    'AZURE_VISION_ENDPOINT': 'https://vision.example.com',
                    'AZURE_VISION_KEY': 'test-key',
                },
                clear=False,
            ),
            patch('grading_api.ocr.requests.post', return_value=response) as post,
        ):
            buffer = io.BytesIO()
            Image.new('RGB', (10, 10), color='white').save(buffer, format='PNG')
            text, confidence = OCRGrader._read_with_azure_vision(
                buffer.getvalue(),
            )

        self.assertEqual(text, 'A handwritten answer.\nSecond line.')
        self.assertIsNone(confidence)
        self.assertTrue(
            post.call_args.args[0].endswith(
                '/computervision/imageanalysis:analyze'
            )
        )
        self.assertEqual(
            post.call_args.kwargs['headers'],
            {
                'Ocp-Apim-Subscription-Key': 'test-key',
                'Content-Type': 'application/octet-stream',
            },
        )
        self.assertEqual(post.call_args.kwargs['data'], buffer.getvalue())
        self.assertEqual(
            post.call_args.kwargs['params'],
            {
                'features': 'read',
                'model-version': 'latest',
                'language': 'en',
                'api-version': '2024-02-01',
            },
        )

    def test_azure_vision_rejects_endpoint_with_path(self):
        with (
            patch.dict(
                'os.environ',
                {
                    'AZURE_VISION_ENDPOINT': 'https://vision.example.com/other',
                    'AZURE_VISION_KEY': 'test-key',
                },
                clear=False,
            ),
            patch('grading_api.ocr.requests.post') as post,
            self.assertRaisesRegex(
                RuntimeError,
                'valid HTTPS Azure endpoint',
            ),
        ):
            OCRGrader._read_with_azure_vision(b'page')
        post.assert_not_called()

    def test_segments_a_photographed_page_from_a_contrasting_background(self):
        image = np.full((600, 800, 3), 35, dtype=np.uint8)
        page_corners = np.array(
            [[120, 55], [665, 85], [620, 545], [90, 510]],
            dtype=np.int32,
        )
        cv2.fillConvexPoly(image, page_corners, (245, 245, 245))
        cv2.polylines(image, [page_corners], True, (15, 15, 15), 5)

        page, detected, area_ratio = OCRGrader._segment_document(image)

        self.assertTrue(detected)
        self.assertGreater(area_ratio, 0.4)
        self.assertLess(page.shape[1], image.shape[1])
        self.assertLess(page.shape[0], image.shape[0])
