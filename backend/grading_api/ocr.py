import io
import logging
import os
import shutil
import threading
import time
from pathlib import Path
from typing import Dict, List
from urllib.parse import urlsplit

import cv2  # type: ignore
import numpy as np
import pytesseract  # type: ignore
import requests
from PIL import Image, ImageOps
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

logger = logging.getLogger(__name__)

_MIN_OCR_CONFIDENCE = 0.4
_AZURE_VISION_API_VERSION = '2024-02-01'
_MAX_IMAGE_DIMENSION = 2400
_MAX_ORIENTATION_DIMENSION = 1280


class OCRProviderError(RuntimeError):
    pass


configured_tesseract = os.environ.get('TESSERACT_CMD', '').strip()
if configured_tesseract:
    pytesseract.pytesseract.tesseract_cmd = configured_tesseract
elif shutil.which('tesseract') is None:
    default_tesseract = (
        Path(os.environ.get('ProgramFiles', r'C:\Program Files'))
        / 'Tesseract-OCR'
        / 'tesseract.exe'
    )
    if default_tesseract.is_file():
        pytesseract.pytesseract.tesseract_cmd = str(default_tesseract)


class OCRGrader:
    """Image cleanup, document detection, and OCR for scanned answer sheets."""

    _reader = None
    _reader_failed = False
    _reader_lock = threading.Lock()

    @classmethod
    def _easyocr_reader(cls):
        if cls._reader is not None or cls._reader_failed:
            return cls._reader

        with cls._reader_lock:
            if cls._reader is not None or cls._reader_failed:
                return cls._reader
            try:
                import easyocr  # type: ignore

                cls._reader = easyocr.Reader(['en'], gpu=False)
            except Exception:
                cls._reader_failed = True
                logger.exception(
                    'EasyOCR could not be initialized; using Azure Vision fallback.'
                )
        return cls._reader

    @staticmethod
    def _read_with_azure_vision(image_bytes: bytes) -> tuple[str, float | None]:
        endpoint = os.environ.get(
            'AZURE_VISION_ENDPOINT',
            '',
        ).strip().rstrip('/')
        api_key = os.environ.get('AZURE_VISION_KEY', '').strip()
        if not endpoint or not api_key:
            raise OCRProviderError(
                'Azure Vision OCR fallback is not configured. Set '
                'AZURE_VISION_ENDPOINT and AZURE_VISION_KEY on the backend.'
            )
        try:
            parsed_endpoint = urlsplit(endpoint)
            valid_endpoint = (
                parsed_endpoint.scheme == 'https'
                and bool(parsed_endpoint.hostname)
                and parsed_endpoint.path in ('', '/')
                and parsed_endpoint.username is None
                and parsed_endpoint.password is None
                and not parsed_endpoint.query
                and not parsed_endpoint.fragment
            )
        except ValueError:
            valid_endpoint = False
        if not valid_endpoint:
            raise OCRProviderError(
                'AZURE_VISION_ENDPOINT must be a valid HTTPS Azure endpoint.'
            )

        request_url = f'{endpoint}/computervision/imageanalysis:analyze'
        headers = {
            'Ocp-Apim-Subscription-Key': api_key,
            'Content-Type': 'application/octet-stream',
        }
        try:
            response = requests.post(
                request_url,
                headers=headers,
                params={
                    'features': 'read',
                    'model-version': 'latest',
                    'language': 'en',
                    'api-version': _AZURE_VISION_API_VERSION,
                },
                data=image_bytes,
                timeout=(10, 90),
                allow_redirects=False,
            )
            if response.status_code != 200:
                raise OCRProviderError(
                    'Azure Computer Vision rejected the scan request '
                    f'(HTTP {response.status_code}). Check that the '
                    'AZURE_VISION_ENDPOINT and AZURE_VISION_KEY belong to '
                    'the same Computer Vision resource and that OCR is '
                    'available for the resource.'
                )
            result = response.json()
            if not isinstance(result, dict):
                raise OCRProviderError(
                    'Azure Computer Vision returned an invalid OCR response.'
                )
            read_result = result.get('readResult')
            blocks = (
                read_result.get('blocks')
                if isinstance(read_result, dict)
                else None
            )
            if not isinstance(blocks, list):
                raise OCRProviderError(
                    'Azure Computer Vision returned no OCR text for this scan.'
                )
            lines = [
                line['text'].strip()
                for block in blocks
                if isinstance(block, dict)
                and isinstance(block.get('lines'), list)
                for line in block['lines']
                if isinstance(line, dict)
                and isinstance(line.get('text'), str)
                and line['text'].strip()
            ]
            text = '\n'.join(lines)
            if not text:
                raise OCRProviderError(
                    'Azure Computer Vision returned no OCR text for this scan.'
                )
            return text, None
        except OCRProviderError:
            raise
        except requests.RequestException as error:
            logger.exception('Azure Computer Vision OCR request failed.')
            raise OCRProviderError(
                'Could not connect to Azure Computer Vision. Check the '
                'backend network and Azure OCR configuration.'
            ) from error
        except (ValueError, TypeError) as error:
            logger.exception(
                'Azure Computer Vision returned an invalid OCR response.'
            )
            raise OCRProviderError(
                'Azure Computer Vision returned an invalid OCR response.'
            ) from error

    @staticmethod
    def _order_points(points: np.ndarray) -> np.ndarray:
        ordered = np.zeros((4, 2), dtype='float32')
        sums = points.sum(axis=1)
        differences = np.diff(points, axis=1).ravel()
        ordered[0] = points[np.argmin(sums)]
        ordered[2] = points[np.argmax(sums)]
        ordered[1] = points[np.argmin(differences)]
        ordered[3] = points[np.argmax(differences)]
        return ordered

    @classmethod
    def _segment_document(cls, image: np.ndarray) -> tuple[np.ndarray, bool, float]:
        height, width = image.shape[:2]
        gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
        edges = cv2.Canny(cv2.GaussianBlur(gray, (5, 5), 0), 50, 150)
        edges = cv2.dilate(edges, np.ones((3, 3), dtype=np.uint8), iterations=2)
        contours, _ = cv2.findContours(
            edges,
            cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE,
        )

        image_area = float(height * width)
        for contour in sorted(contours, key=cv2.contourArea, reverse=True):
            area = float(cv2.contourArea(contour))
            if area < image_area * 0.15:
                break
            perimeter = cv2.arcLength(contour, True)
            polygon = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
            if len(polygon) != 4:
                continue

            source = cls._order_points(polygon.reshape(4, 2).astype('float32'))
            top_left, top_right, bottom_right, bottom_left = source
            target_width = int(max(
                np.linalg.norm(bottom_right - bottom_left),
                np.linalg.norm(top_right - top_left),
            ))
            target_height = int(max(
                np.linalg.norm(top_right - bottom_right),
                np.linalg.norm(top_left - bottom_left),
            ))
            if target_width < 2 or target_height < 2:
                continue

            target = np.array([
                [0, 0],
                [target_width - 1, 0],
                [target_width - 1, target_height - 1],
                [0, target_height - 1],
            ], dtype='float32')
            transform = cv2.getPerspectiveTransform(source, target)
            warped = cv2.warpPerspective(image, transform, (target_width, target_height))
            return warped, True, min(area / image_area, 1.0)
        return image, False, 1.0

    def _prepare_image(self, image_bytes: bytes) -> tuple[np.ndarray, Dict[str, object]]:
        image = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes)))
        source_width, source_height = image.size
        image.thumbnail(
            (_MAX_IMAGE_DIMENSION, _MAX_IMAGE_DIMENSION),
            Image.Resampling.LANCZOS,
        )
        image = image.convert('RGB')
        rgb = np.asarray(image)
        corrected, document_detected, document_area = self._segment_document(rgb)
        gray = cv2.cvtColor(corrected, cv2.COLOR_RGB2GRAY)
        denoised = cv2.bilateralFilter(gray, 9, 45, 45)
        enhanced = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(denoised)

        try:
            orientation_image = enhanced
            if max(enhanced.shape) > _MAX_ORIENTATION_DIMENSION:
                scale = _MAX_ORIENTATION_DIMENSION / max(enhanced.shape)
                orientation_image = cv2.resize(
                    enhanced,
                    None,
                    fx=scale,
                    fy=scale,
                    interpolation=cv2.INTER_AREA,
                )
            orientation = pytesseract.image_to_osd(
                orientation_image,
                output_type=pytesseract.Output.DICT,
                config='--psm 0',
            )
            rotation = int(orientation.get('rotate', 0)) % 360
            if rotation == 90:
                enhanced = cv2.rotate(enhanced, cv2.ROTATE_90_CLOCKWISE)
            elif rotation == 180:
                enhanced = cv2.rotate(enhanced, cv2.ROTATE_180)
            elif rotation == 270:
                enhanced = cv2.rotate(enhanced, cv2.ROTATE_90_COUNTERCLOCKWISE)
        except (
            pytesseract.TesseractError,
            pytesseract.TesseractNotFoundError,
            ValueError,
            TypeError,
        ):
            logger.debug('Automatic text orientation detection was unavailable.')

        scale = min(2.0, _MAX_IMAGE_DIMENSION / max(enhanced.shape))
        if scale != 1.0:
            processed = cv2.resize(
                enhanced,
                None,
                fx=scale,
                fy=scale,
                interpolation=(
                    cv2.INTER_CUBIC if scale > 1 else cv2.INTER_AREA
                ),
            )
        else:
            processed = enhanced
        return processed, {
            'document_detected': document_detected,
            'document_area_ratio': round(document_area, 4),
            'image_size': {'width': source_width, 'height': source_height},
        }

    def preprocess_image(self, image_bytes: bytes) -> np.ndarray:
        processed, _ = self._prepare_image(image_bytes)
        return processed

    def analyze_image(self, image_bytes: bytes) -> Dict[str, object]:
        processed, diagnostics = self._prepare_image(image_bytes)
        reader = self._easyocr_reader()
        if reader is not None:
            try:
                detections = reader.readtext(processed, detail=1, paragraph=False)
            except Exception:
                logger.exception('EasyOCR failed while reading the scan.')
                text, confidence = self._read_with_azure_vision(image_bytes)
                engine = 'azure_computer_vision'
            else:
                lines = [
                    str(detection[1]).strip()
                    for detection in detections
                    if len(detection) > 1 and str(detection[1]).strip()
                ]
                confidences = [
                    float(detection[2])
                    for detection in detections
                    if len(detection) > 2 and isinstance(detection[2], (int, float))
                ]
                text = '\n'.join(lines)
                confidence = (
                    sum(confidences) / len(confidences)
                    if confidences
                    else None
                )
                engine = 'easyocr'
                if (
                    not text
                    or confidence is None
                    or confidence < _MIN_OCR_CONFIDENCE
                ):
                    logger.info(
                        'EasyOCR confidence was low or no text was detected; '
                        'retrying with Azure Computer Vision.'
                    )
                    text, confidence = self._read_with_azure_vision(image_bytes)
                    engine = 'azure_computer_vision'
        else:
            text, confidence = self._read_with_azure_vision(image_bytes)
            engine = 'azure_computer_vision'

        ink = cv2.threshold(
            processed,
            0,
            255,
            cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU,
        )[1]
        _, _, stats, _ = cv2.connectedComponentsWithStats(ink, connectivity=8)
        min_component_area = max(8, int(ink.size * 0.00001))
        content_regions = sum(
            1 for area in stats[1:, cv2.CC_STAT_AREA] if area >= min_component_area
        )
        midpoint_x, midpoint_y = ink.shape[1] // 2, ink.shape[0] // 2
        left_ink = int(np.count_nonzero(ink[:, :max(midpoint_x, 1)]))
        right_ink = int(np.count_nonzero(ink[:, midpoint_x:]))
        top_ink = int(np.count_nonzero(ink[:max(midpoint_y, 1), :]))
        bottom_ink = int(np.count_nonzero(ink[midpoint_y:, :]))
        diagnostics.update({
            'ink_coverage': round(float(np.count_nonzero(ink) / ink.size), 4),
            'edge_density': round(
                float(np.count_nonzero(cv2.Canny(processed, 50, 150)) / ink.size),
                4,
            ),
            'content_regions': int(content_regions),
            'horizontal_balance': round(
                min(left_ink, right_ink) / max(left_ink, right_ink, 1),
                4,
            ),
            'vertical_balance': round(
                min(top_ink, bottom_ink) / max(top_ink, bottom_ink, 1),
                4,
            ),
        })
        return {
            'text': text,
            'ocr_engine': engine,
            'ocr_confidence': round(confidence, 4) if confidence is not None else None,
            'visual_features': diagnostics,
        }

    def extract_text(self, image_bytes: bytes) -> str:
        return str(self.analyze_image(image_bytes)['text'])

    def score_answers(self, expected_answers: Dict[str, str], extracted_text: str) -> Dict[str, object]:
        normalized = self._normalize_text(extracted_text)
        score = 0
        details: List[Dict[str, object]] = []

        for question_key, expected in expected_answers.items():
            expected_norm = self._normalize_text(expected)
            similarity = self._similarity_score(expected_norm, normalized)
            matched = similarity >= 0.58 or expected_norm in normalized
            if matched:
                score += 1
            details.append({
                'question': question_key,
                'expected': expected,
                'similarity': round(similarity, 3),
                'matched': matched,
            })

        total = len(expected_answers)
        percent = round((score / total) * 100, 2) if total else 0.0
        return {
            'score': score,
            'total': total,
            'percentage': percent,
            'details': details,
        }

    def grade_sheet(self, image_bytes: bytes, expected_answers: Dict[str, str]) -> Dict[str, object]:
        text = self.extract_text(image_bytes)
        result = self.score_answers(expected_answers, text)
        result['extracted_text'] = text
        return result

    @staticmethod
    def _normalize_text(value: str) -> str:
        lower = value.lower()
        lower = re.sub(r'[^a-z0-9\s]', '', lower)
        return re.sub(r'\s+', ' ', lower).strip()

    @staticmethod
    def _similarity_score(expected: str, extracted: str) -> float:
        if not expected or not extracted:
            return 0.0
        vectorizer = TfidfVectorizer(ngram_range=(1, 2), stop_words=None)
        matrix = vectorizer.fit_transform([expected, extracted])
        similarity = cosine_similarity(matrix[0], matrix[1])[0][0]
        return float(similarity)
