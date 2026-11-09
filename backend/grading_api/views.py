import json
import logging
import math
import re
import unicodedata

from django.views.decorators.csrf import csrf_exempt
from django.http import HttpRequest, JsonResponse

from .authentication import require_instructor
from .ocr import OCRGrader, OCRProviderError
from .essay_model import predict_essay_score
from .train_model import ModelArtifactError, predict_score, train_scoring_model

logger = logging.getLogger(__name__)


_VISUAL_CRITERION_KEYWORDS = {
    'flow': ('flow', 'sequence', 'sequence', 'connection', 'transition'),
    'organization': ('organization', 'organis', 'arrangement', 'layout', 'structure'),
    'completeness': ('complete', 'completeness', 'required', 'coverage', 'content'),
    'neatness': ('neat', 'clean', 'legibility', 'legible', 'presentation', 'physical'),
}
_MIN_OCR_CONFIDENCE = 0.4
_STUDENT_NAME_LABEL = re.compile(
    r"^\s*(?:student(?:\s+name)?|learner(?:\s+name)?|name)\s*[:\-]\s*(.+?)\s*$",
    re.IGNORECASE | re.MULTILINE,
)
_FEATURE_STOP_WORDS = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'in',
    'into', 'is', 'it', 'of', 'on', 'or', 'that', 'the', 'their', 'this',
    'to', 'was', 'were', 'with',
}


def _normalized_name_tokens(value):
    normalized = unicodedata.normalize('NFKD', value)
    normalized = normalized.encode('ascii', 'ignore').decode('ascii')
    return set(re.findall(r'[a-z]+', normalized.casefold()))


def _labeled_student_name_mismatch(extracted_text, expected_name):
    expected_tokens = _normalized_name_tokens(expected_name)
    if not expected_tokens:
        return None

    for match in _STUDENT_NAME_LABEL.finditer(extracted_text):
        detected_name = match.group(1).strip()
        detected_tokens = _normalized_name_tokens(detected_name)
        if detected_tokens and not expected_tokens.intersection(detected_tokens):
            return detected_name
    return None


def _clamp_score(value):
    return round(max(0.0, min(100.0, value)), 2)


def _has_usable_rubric(rubric):
    if not isinstance(rubric, dict) or not isinstance(rubric.get('criteria'), list):
        return False
    criteria = rubric['criteria']
    if not criteria:
        return False
    if rubric.get('type') == 'Weighted':
        return all(
            isinstance(criterion, dict)
            and str(criterion.get('title') or '').strip()
            and str(criterion.get('description') or '').strip()
            and _has_valid_criterion_weight(criterion)
            for criterion in criteria
        )
    if rubric.get('type') == 'Analytic':
        return all(
            isinstance(criterion, dict)
            and str(criterion.get('title') or '').strip()
            and isinstance(criterion.get('levels'), list)
            and criterion['levels']
            and all(str(level).strip() for level in criterion['levels'])
            and _has_valid_criterion_weight(criterion)
            for criterion in criteria
        )
    if rubric.get('type') == 'Holistic':
        try:
            points = [
                float(criterion['points'])
                for criterion in criteria
                if isinstance(criterion, dict)
                and str(criterion.get('description') or '').strip()
            ]
        except (KeyError, TypeError, ValueError):
            return False
        return (
            len(points) == len(criteria)
            and all(math.isfinite(point) and point >= 0 for point in points)
            and max(points, default=0) > 0
        )
    return False


def _has_valid_criterion_weight(criterion):
    weight = criterion.get('weight')
    if weight is None:
        weight = criterion.get('score')
    if weight is None or (isinstance(weight, str) and not weight.strip()):
        return True
    if isinstance(weight, bool):
        return False
    try:
        numeric_weight = float(weight)
    except (TypeError, ValueError):
        return False
    return math.isfinite(numeric_weight) and numeric_weight > 0


def _criterion_weight(criterion):
    weight = criterion.get('weight')
    if weight is None:
        weight = criterion.get('score')
    if weight is None or (isinstance(weight, str) and not weight.strip()):
        return 1.0
    numeric_weight = float(weight)
    if not math.isfinite(numeric_weight) or numeric_weight <= 0:
        raise ValueError('Rubric criterion weights must be positive numbers.')
    return numeric_weight


def _normalize_rubric(rubric):
    if not isinstance(rubric, list):
        return rubric
    return {
        'type': 'Weighted',
        'criteria': [
            {
                **criterion,
                'title': criterion.get('name') or criterion.get('title'),
            }
            if isinstance(criterion, dict) else criterion
            for criterion in rubric
        ],
    }


def _context_values(value):
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, dict):
        return [
            item
            for child in value.values()
            for item in _context_values(child)
        ]
    if isinstance(value, list):
        return [
            item
            for child in value
            for item in _context_values(child)
        ]
    return []


def _is_text_context(value):
    if isinstance(value, str):
        return True
    if isinstance(value, list):
        return all(_is_text_context(item) for item in value)
    if isinstance(value, dict):
        return all(_is_text_context(item) for item in value.values())
    return False


def _text_features(extracted_text, learning_objectives, rubric):
    words = re.findall(r"\b[\w'-]+\b", extracted_text.casefold())
    sentences = [
        sentence
        for sentence in re.split(r'[.!?]+', extracted_text)
        if sentence.strip()
    ]
    paragraphs = [
        paragraph
        for paragraph in re.split(r'\n\s*\n', extracted_text.strip())
        if paragraph.strip()
    ]
    if extracted_text.strip() and not paragraphs:
        paragraphs = [extracted_text.strip()]

    reference_text = learning_objectives + [
        str(criterion.get('title') or '')
        for criterion in rubric.get('criteria', [])
        if isinstance(criterion, dict)
    ] + [
        str(criterion.get('description') or '')
        for criterion in rubric.get('criteria', [])
        if isinstance(criterion, dict)
    ] + [
        str(level)
        for criterion in rubric.get('criteria', [])
        if isinstance(criterion, dict)
        for level in criterion.get('levels', [])
    ]
    reference_words = {
        word
        for text in reference_text
        for word in re.findall(r"\b[\w'-]+\b", text.casefold())
        if len(word) > 2 and word not in _FEATURE_STOP_WORDS
    }
    response_words = set(words)
    matched_words = sorted(reference_words & response_words)
    return {
        'word_count': len(words),
        'sentence_count': len(sentences),
        'paragraph_count': len(paragraphs),
        'keyword_coverage': (
            round(len(matched_words) / len(reference_words), 3)
            if reference_words else None
        ),
        'matched_keywords': matched_words,
        'reference_keyword_count': len(reference_words),
    }


def _rubric_task_context(
    task_title,
    task_instructions,
    expected_answers,
    learning_objectives,
    expected_concepts,
):
    context_lines = []
    if task_title.strip():
        context_lines.append(f'Task title: {task_title.strip()}')
    if task_instructions.strip():
        context_lines.append(f'Task instructions: {task_instructions.strip()}')
    for answer in _context_values(expected_answers):
        context_lines.append(f'Reference answer: {answer}')
    for objective in learning_objectives:
        context_lines.append(f'Learning objective: {objective}')
    for concept in expected_concepts:
        context_lines.append(f'Expected concept: {concept}')
    return '\n'.join(dict.fromkeys(context_lines))


def _grade_with_rubric(
    student_answers,
    extracted_text,
    rubric,
    task_context='',
):
    details = []
    criterion_results = []
    criteria = rubric['criteria']

    context_prefix = (
        'Task context (use to interpret relevance; the rubric remains the '
        'scoring standard):\n'
        f'{task_context}\n'
        if task_context
        else ''
    )

    def select_level(question, title, levels, answer):
        candidates = []
        for index, descriptor in enumerate(levels):
            expected = (
                f'{context_prefix}'
                f'Rubric criterion: {title}\n'
                f'Performance level: {descriptor}'
            )
            result = predict_score(
                answer,
                expected,
                f'{question}_level_{index + 1}',
            )
            candidates.append((result, descriptor, index))
        return max(
            candidates,
            key=lambda candidate: (
                candidate[0]['predicted_score'] / max(candidate[0]['max_score'], 1),
                candidate[0]['confidence'],
                -candidate[2],
            ),
        )

    if rubric['type'] == 'Analytic':
        for index, criterion in enumerate(criteria):
            question = f'criterion_{index + 1}'
            title = str(criterion['title']).strip()
            levels = [str(level).strip() for level in criterion['levels']]
            answer = student_answers.get(question, extracted_text)
            if not isinstance(answer, str):
                raise ValueError('Each student_answers value must be a string.')
            result, descriptor, level_index = select_level(
                question,
                title,
                levels,
                answer,
            )
            score = level_index + 1
            maximum = len(levels)
            criterion_maximum = _criterion_weight(criterion)
            criterion_score = criterion_maximum * score / maximum
            try:
                similarity = round(
                    OCRGrader._similarity_score(
                        descriptor.casefold(),
                        answer.casefold(),
                    ),
                    3,
                )
            except ValueError:
                similarity = 0.0
            explanation = (
                'The submitted response most closely matches the rubric level: '
                f'{descriptor}.'
            )
            detail = {
                'question': question,
                'title': title,
                'expected': descriptor,
                'student_answer': answer,
                'predicted_score': score,
                'max_score': maximum,
                'confidence': result['confidence'],
                'matched': score >= (maximum + 1) / 2,
                'selected_level': score,
                'rubric_level': descriptor,
                'rubric_score': criterion_score,
                'rubric_max_score': criterion_maximum,
                'similarity': similarity,
                'explanation': explanation,
                'feedback': (
                    f'For {title}, aim for the next rubric level: '
                    f'{levels[level_index + 1]}.'
                    if level_index + 1 < len(levels)
                    else f'{title} reached the highest rubric level: {descriptor}.'
                ),
            }
            details.append(detail)
            criterion_results.append({
                'title': title,
                'predictedScore': score,
                'maxScore': maximum,
                'selectedLevel': score,
                'rubricLevel': descriptor,
                'confidence': result['confidence'],
                'evidence': answer[:500],
                'score': round(criterion_score, 2),
                'rubricScore': round(criterion_score, 2),
                'rubricMaxScore': criterion_maximum,
                'similarity': similarity,
                'explanation': explanation,
                'feedback': detail['feedback'],
            })
    else:
        if rubric['type'] == 'Weighted':
            for index, criterion in enumerate(criteria):
                question = f'criterion_{index + 1}'
                title = str(criterion['title']).strip()
                description = str(criterion['description']).strip()
                answer = student_answers.get(question, extracted_text)
                if not isinstance(answer, str):
                    raise ValueError('Each student_answers value must be a string.')
                expected = (
                    f'{context_prefix}'
                    f'Rubric criterion: {title}\n'
                    f'Criterion description: {description}'
                )
                result = predict_score(answer, expected, question)
                model_maximum = max(result['max_score'], 1)
                criterion_maximum = _criterion_weight(criterion)
                criterion_score = (
                    criterion_maximum * result['predicted_score'] / model_maximum
                )
                try:
                    similarity = round(
                        OCRGrader._similarity_score(
                            description.casefold(),
                            answer.casefold(),
                        ),
                        3,
                    )
                except ValueError:
                    similarity = 0.0
                explanation = (
                    'The response was evaluated against the teacher-defined '
                    f'criterion: {description}.'
                )
                feedback = (
                    f'This rubric requirement was met: {description}.'
                    if criterion_score >= criterion_maximum
                    else f'To improve {title}, address this rubric requirement: '
                    f'{description}.'
                )
                detail = {
                    'question': question,
                    'title': title,
                    'expected': description,
                    'student_answer': answer,
                    'predicted_score': result['predicted_score'],
                    'max_score': result['max_score'],
                    'confidence': result['confidence'],
                    'matched': criterion_score >= criterion_maximum / 2,
                    'rubric_level': description,
                    'rubric_score': criterion_score,
                    'rubric_max_score': criterion_maximum,
                    'similarity': similarity,
                    'explanation': explanation,
                    'feedback': feedback,
                }
                details.append(detail)
                criterion_results.append({
                    'title': title,
                    'predictedScore': result['predicted_score'],
                    'maxScore': result['max_score'],
                    'rubricLevel': description,
                    'confidence': result['confidence'],
                    'evidence': answer[:500],
                    'score': round(criterion_score, 2),
                    'rubricScore': round(criterion_score, 2),
                    'rubricMaxScore': criterion_maximum,
                    'similarity': similarity,
                    'explanation': explanation,
                    'feedback': feedback,
                })
        else:
            title = str(rubric.get('title') or 'Holistic rubric').strip()
            levels = [
                (float(criterion['points']), str(criterion['description']).strip())
                for criterion in criteria
            ]
            answer = student_answers.get('holistic', extracted_text)
            if not isinstance(answer, str):
                raise ValueError('Each student_answers value must be a string.')
            candidates = []
            for index, (points, descriptor) in enumerate(levels):
                result, _, _ = select_level(
                    f'holistic',
                    title,
                    [descriptor],
                    answer,
                )
                candidates.append((result, points, descriptor, index))
            result, score, descriptor, level_index = max(
                candidates,
                key=lambda candidate: (
                    candidate[0]['predicted_score'] / max(candidate[0]['max_score'], 1),
                    candidate[0]['confidence'],
                    -candidate[3],
                ),
            )
            maximum = max(points for points, _ in levels)
            try:
                similarity = round(
                    OCRGrader._similarity_score(
                        descriptor.casefold(),
                        answer.casefold(),
                    ),
                    3,
                )
            except ValueError:
                similarity = 0.0
            explanation = (
                'The submitted response most closely matches the rubric level: '
                f'{descriptor}.'
            )
            higher_levels = [
                item for item in levels
                if item[0] > score
            ]
            next_level = min(higher_levels, default=None, key=lambda item: item[0])
            detail = {
                'question': 'holistic',
                'title': title,
                'expected': descriptor,
                'student_answer': answer,
                'predicted_score': score,
                'max_score': maximum,
                'confidence': result['confidence'],
                'matched': score >= maximum / 2,
                'selected_level': level_index + 1,
                'rubric_level': descriptor,
                'rubric_score': score,
                'rubric_max_score': maximum,
                'similarity': similarity,
                'explanation': explanation,
                'feedback': (
                    f'To improve, aim for the next rubric level: {next_level[1]}.'
                    if next_level is not None
                    else f'The response reached the highest rubric level: {descriptor}.'
                ),
            }
            details.append(detail)
            criterion_results.append({
                'title': title,
                'predictedScore': score,
                'maxScore': maximum,
                'selectedLevel': level_index + 1,
                'rubricLevel': descriptor,
                'confidence': result['confidence'],
                'evidence': answer[:500],
                'score': round(score, 2),
                'rubricScore': round(score, 2),
                'rubricMaxScore': maximum,
                'similarity': similarity,
                'explanation': explanation,
                'feedback': detail['feedback'],
            })

    return details, criterion_results


def _visual_recommendations(features, pages_analyzed, criteria):
    if not features or not criteria:
        return []
    detected = float(features.get('document_area_ratio', 0.0))
    ink = float(features.get('ink_coverage', 0.0))
    edges = float(features.get('edge_density', 0.0))
    regions = float(features.get('content_regions', 0.0))
    horizontal = float(features.get('horizontal_balance', 0.0))
    vertical = float(features.get('vertical_balance', 0.0))
    document_detected = detected >= 0.35
    quality_confidence = round(
        min(1.0, (0.5 if document_detected else 0.0) + min(0.5, pages_analyzed / 10)),
        3,
    )
    scores = {
        'flow': _clamp_score((horizontal * 0.45 + vertical * 0.35 + min(edges / 0.2, 1) * 0.2) * 100),
        'organization': _clamp_score((horizontal * 0.4 + vertical * 0.4 + min(regions / 40, 1) * 0.2) * 100),
        'completeness': _clamp_score((
            (1 if document_detected else 0) * 0.35
            + min(regions / 30, 1) * 0.35
            + (1 if ink > 0.01 else 0) * 0.3
        ) * 100),
        'neatness': _clamp_score((
            min(horizontal, vertical) * 0.35
            + max(0, 1 - min(ink / 0.35, 1)) * 0.35
            + max(0, 1 - min(edges / 0.35, 1)) * 0.3
        ) * 100),
    }
    recommendations = []
    for criterion in criteria:
        title = str(criterion.get('title') or '').strip()
        normalized = title.casefold()
        key = next(
            (name for name, keywords in _VISUAL_CRITERION_KEYWORDS.items()
             if any(keyword in normalized for keyword in keywords)),
            None,
        )
        if key is None:
            continue
        level_count = criterion.get('levels')
        level_count = len(level_count) if isinstance(level_count, list) else 4
        score = scores[key]
        level = max(1, min(level_count, round((score / 100) * (level_count - 1)) + 1))
        recommendations.append({
            'title': title or key.title(),
            'criterion': key,
            'recommendedScore': score,
            'recommendedLevel': level,
            'maxLevel': level_count,
            'confidence': quality_confidence,
            'evidence': {
                'documentAreaRatio': detected,
                'inkCoverage': ink,
                'edgeDensity': edges,
                'contentRegions': regions,
                'horizontalBalance': horizontal,
                'verticalBalance': vertical,
            },
            'reviewNote': 'Visual recommendation only; instructor must verify the page and rubric.',
        })
    return recommendations


@csrf_exempt
def grade_sheet_api(request: HttpRequest):
    if request.method != 'POST':
        return JsonResponse({'error': 'Only POST requests are allowed.'}, status=405)
    authentication_error = require_instructor(request)
    if authentication_error is not None:
        return authentication_error

    try:
        if (request.content_type or '').startswith('multipart/form-data'):
            payload = request.POST.get('payload') or request.POST.get('data') or '{}'
            request_data = json.loads(payload)
        else:
            request_data = json.loads(request.body.decode('utf-8'))
    except (ValueError, TypeError):
        return JsonResponse({'error': 'Invalid JSON payload.'}, status=400)
    if not isinstance(request_data, dict):
        return JsonResponse({'error': 'The request body must be a JSON object.'}, status=400)

    if request_data.get('task_type') == 'essay':
        try:
            result = predict_essay_score(request_data.get('essay_text', ''))
        except ModelArtifactError as error:
            return JsonResponse({'error': str(error)}, status=503)
        except (ValueError, FileNotFoundError) as error:
            return JsonResponse({'error': str(error)}, status=400)
        return JsonResponse({
            'task_type': 'essay',
            'essay_result': result,
            'requires_human_review': True,
            'grading_source': 'ai_suggestion',
        })

    expected_answers = request_data.get('expected_answers', {})
    rubric = _normalize_rubric(request_data.get('rubric'))
    if rubric is not None and not isinstance(rubric, dict):
        return JsonResponse({'error': 'rubric must be an object or criteria list.'}, status=400)
    task_instructions = request_data.get(
        'task_instructions',
        request_data.get('instructions', ''),
    )
    if not isinstance(task_instructions, str):
        return JsonResponse({
            'error': 'task_instructions must be a string.'
        }, status=400)
    if (
        not isinstance(expected_answers, dict)
        or any(
            not isinstance(key, str)
            or not isinstance(value, str)
            or not value.strip()
            for key, value in expected_answers.items()
        )
        or (not expected_answers and not _has_usable_rubric(rubric))
    ):
        return JsonResponse({
            'error': 'Provide task instructions, rubric criteria, or expected answers.'
        }, status=400)
    curriculum_standards = request_data.get('curriculum_standards') or {}
    if not isinstance(curriculum_standards, dict):
        return JsonResponse({'error': 'curriculum_standards must be an object.'}, status=400)
    task_title = request_data.get('task_title', '')
    if not isinstance(task_title, str):
        return JsonResponse({'error': 'task_title must be a string.'}, status=400)
    task_type = request_data.get('task_type', '')
    if not isinstance(task_type, str):
        return JsonResponse({'error': 'task_type must be a string.'}, status=400)
    learning_objectives = request_data.get('learning_objectives', [])
    if not isinstance(learning_objectives, (str, list, dict)):
        return JsonResponse({
            'error': 'learning_objectives must be a string, list, or object.'
        }, status=400)
    if not _is_text_context(learning_objectives):
        return JsonResponse({
            'error': 'Learning objectives must contain text values.'
        }, status=400)
    expected_concepts = request_data.get('expected_concepts', [])
    if not isinstance(expected_concepts, (str, list, dict)):
        return JsonResponse({
            'error': 'expected_concepts must be a string, list, or object.'
        }, status=400)
    if not _is_text_context(expected_concepts):
        return JsonResponse({
            'error': 'Expected concepts must contain text values.'
        }, status=400)
    submission_metadata = request_data.get('submission_metadata', {})
    if not isinstance(submission_metadata, dict):
        return JsonResponse({
            'error': 'submission_metadata must be an object.'
        }, status=400)
    expected_student_name = submission_metadata.get('expected_student_name', '')
    if not isinstance(expected_student_name, str):
        return JsonResponse({
            'error': 'expected_student_name must be a string.'
        }, status=400)

    try:
        extracted_text = request_data.get(
            'student_text',
            request_data.get('answer_text', ''),
        )
        image_files = request.FILES.getlist('images')
        if not image_files and request.FILES.get('image'):
            image_files = [request.FILES['image']]
        scan_analysis = []
        if image_files:
            grader = OCRGrader()
            scan_analysis = [
                grader.analyze_image(image.read()) for image in image_files
            ]
            extracted_text = '\n'.join(
                str(scan['text']) for scan in scan_analysis
            ).strip()
        if not isinstance(extracted_text, str):
            return JsonResponse({'error': 'student_text must be a string.'}, status=400)
        if not extracted_text.strip():
            return JsonResponse({
                'error': 'No answer text could be read. Review the scan and enter the grade manually.',
                'requires_human_review': True,
            }, status=422)
        if scan_analysis and any(
            scan.get('ocr_confidence') is not None
            and float(scan['ocr_confidence']) < _MIN_OCR_CONFIDENCE
            for scan in scan_analysis
        ):
            return JsonResponse({
                'error': 'Scan quality too poor for reliable grading.',
                'requires_human_review': True,
            }, status=422)
        if scan_analysis and expected_student_name.strip():
            detected_name = _labeled_student_name_mismatch(
                extracted_text,
                expected_student_name,
            )
            if detected_name is not None:
                logger.info(
                    'Potential student/work mismatch detected for a hardcopy scan.'
                )
                return JsonResponse({
                    'error': (
                        f'The scan is labeled "{detected_name}", but this work '
                        f'was assigned to {expected_student_name}. Verify that '
                        'the correct student’s work was scanned before grading.'
                    ),
                    'requires_human_review': True,
                    'submission_mismatch': {
                        'type': 'student_name',
                        'expected_student_name': expected_student_name,
                        'detected_student_name': detected_name,
                    },
                }, status=422)

        details = []
        rubric_graded = _has_usable_rubric(rubric)
        credit_score = 0
        model_score = 0
        model_max_score = 0
        criterion_results = []

        student_answers = request_data.get('student_answers', {})
        if not isinstance(student_answers, dict):
            return JsonResponse({'error': 'student_answers must be an object.'}, status=400)
        if any(not isinstance(answer, str) for answer in student_answers.values()):
            return JsonResponse({
                'error': 'Each student_answers value must be a string.'
            }, status=400)

        confidence_values = []
        matched_standards = []
        missing_standards = []
        learning_objective_text = _context_values(learning_objectives)
        expected_concept_text = _context_values(expected_concepts)
        if rubric_graded:
            task_context = _rubric_task_context(
                task_title,
                task_instructions,
                expected_answers,
                learning_objective_text,
                expected_concept_text,
            )
            details, criterion_results = _grade_with_rubric(
                student_answers,
                extracted_text,
                rubric,
                task_context,
            )
            for detail in details:
                confidence_values.append(detail['confidence'])
                credit_score += detail['rubric_score']
                model_score += detail['rubric_score']
                model_max_score += detail['rubric_max_score']
        else:
            for question_key, expected in expected_answers.items():
                student_answer = student_answers.get(question_key, extracted_text)
                if not isinstance(student_answer, str):
                    return JsonResponse({
                        'error': 'Each student_answers value must be a string.'
                    }, status=400)
                result = predict_score(student_answer, expected, question_key)
                confidence_values.append(result['confidence'])
                matched = result['predicted_score'] >= 3
                if matched:
                    credit_score += 1
                model_score += result['predicted_score']
                model_max_score += result['max_score']
                details.append({
                    'question': question_key,
                    'expected': expected,
                    'student_answer': student_answer,
                    'predicted_score': result['predicted_score'],
                    'max_score': result['max_score'],
                    'confidence': result['confidence'],
                    'matched': matched,
                })
        for detail in details:
            question_key = detail['question']
            standards = curriculum_standards.get(question_key, [])
            if rubric_graded and rubric.get('type') == 'Holistic':
                standards = curriculum_standards.get('criterion_1', standards)
            if isinstance(standards, list):
                answer_lower = detail['student_answer'].casefold()
                matched_standards.extend(
                    str(keyword).strip()
                    for keyword in standards
                    if str(keyword).strip() and str(keyword).strip().casefold() in answer_lower
                )
                missing_standards.extend(
                    str(keyword).strip()
                    for keyword in standards
                    if str(keyword).strip() and str(keyword).strip().casefold() not in answer_lower
                )

        if rubric_graded:
            total = model_max_score
            percentage = round((credit_score / total) * 100, 2) if total else 0.0
            ai_score = percentage
        else:
            total = len(details)
            percentage = round((credit_score / total) * 100, 2) if total else 0.0
            ai_score = (
                round((model_score / model_max_score) * 100, 2)
                if model_max_score
                else 0.0
            )
        average_confidence = round(sum(confidence_values) / len(confidence_values), 3) if confidence_values else 0.0
        review_reasons = []
        assisted_grading_eligible = average_confidence >= 0.9
        if average_confidence < 0.7:
            review_reasons.append('AI confidence is below the review threshold.')
        elif not assisted_grading_eligible:
            review_reasons.append(
                'AI confidence is below the high-confidence assisted-grading threshold.'
            )
        if scan_analysis and any(
            not scan['visual_features']['document_detected'] for scan in scan_analysis
        ):
            review_reasons.append('One or more pages did not contain a confidently detected document.')
        if scan_analysis and any(
            scan['ocr_confidence'] is None for scan in scan_analysis
        ):
            review_reasons.append(
                'The OCR provider did not return a confidence score; verify the transcription against the original scan.'
            )
            assisted_grading_eligible = False
        criteria = rubric.get('criteria', []) if isinstance(rubric, dict) else []
        if not rubric_graded and isinstance(criteria, list):
            for index, criterion in enumerate(criteria):
                if not isinstance(criterion, dict):
                    continue
                detail = next(
                    (item for item in details if item['question'] == f'criterion_{index + 1}'),
                    None,
                )
                if detail:
                    criterion_results.append({
                        'title': str(criterion.get('title') or f'Criterion {index + 1}'),
                        'predictedScore': detail['predicted_score'],
                        'maxScore': detail['max_score'],
                        'confidence': detail['confidence'],
                        'evidence': detail['student_answer'][:500],
                    })
        visual_feature_names = (
            'document_area_ratio',
            'ink_coverage',
            'edge_density',
            'content_regions',
            'horizontal_balance',
            'vertical_balance',
        )
        visual_analysis = {}
        if scan_analysis:
            available_ocr_confidences = [
                float(scan['ocr_confidence'])
                for scan in scan_analysis
                if scan['ocr_confidence'] is not None
            ]
            visual_analysis = {
                'pages_analyzed': len(scan_analysis),
                'pages_with_detected_document': sum(
                    bool(scan['visual_features']['document_detected'])
                    for scan in scan_analysis
                ),
                'features': {
                    feature: round(
                        sum(
                            float(scan['visual_features'][feature])
                            for scan in scan_analysis
                        ) / len(scan_analysis),
                        4,
                    )
                    for feature in visual_feature_names
                },
                'ocr_engine': scan_analysis[0]['ocr_engine'],
                'ocr_confidence': (
                    round(
                        sum(available_ocr_confidences)
                        / len(available_ocr_confidences),
                        4,
                    )
                    if available_ocr_confidences
                    else None
                ),
                'pages': scan_analysis,
            }
        visual_recommendations = _visual_recommendations(
            visual_analysis.get('features', {}),
            visual_analysis.get('pages_analyzed', 0),
            criteria,
        )
        if visual_recommendations:
            criterion_results.extend(visual_recommendations)
            visual_score = round(
                sum(item['recommendedScore'] for item in visual_recommendations)
                / len(visual_recommendations),
                2,
            )
            review_reasons.append(
                'Visual rubric criteria require instructor verification against the original scan.'
            )
            assisted_grading_eligible = False
        else:
            visual_score = None
        text_features = _text_features(
            extracted_text,
            [*learning_objective_text, *expected_concept_text],
            rubric if isinstance(rubric, dict) else {},
        )
        criterion_scores = [
            {
                'criterion': detail['title'],
                'score': round(detail['rubric_score'], 2),
                'max_score': detail['rubric_max_score'],
                'confidence': detail['confidence'],
                'explanation': detail['explanation'],
                'similarity': detail['similarity'],
            }
            for detail in details
            if 'rubric_score' in detail
        ]
        rubric_feedback = [
            detail['feedback']
            for detail in details
            if isinstance(detail.get('feedback'), str)
        ]
        return JsonResponse({
            'status': 'success',
            'result': {
                'score': credit_score,
                'total': total,
                'percentage': percentage,
                'details': details,
                'extracted_text': extracted_text,
                'ai_score': ai_score,
                'ai_pre_score': ai_score,
                'visual_score': visual_score,
                'ai_confidence': average_confidence,
                'confidence': average_confidence,
                'assisted_grading_eligible': assisted_grading_eligible,
                'visual_analysis': visual_analysis,
                'visual_recommendations': visual_recommendations,
                'criterion_results': criterion_results,
                'criterion_scores': criterion_scores,
                'feedback': rubric_feedback,
                'text_features': text_features,
                'task_context': {
                    'task_title': task_title,
                    'task_type': task_type,
                    'learning_objectives': learning_objective_text,
                    'expected_concepts': expected_concept_text,
                },
                'submission_metadata': submission_metadata,
                'matched_curriculum_standards': sorted(set(matched_standards)),
                'missing_curriculum_standards': sorted(set(missing_standards)),
                'review_status': 'pending_review',
                'requires_human_review': True,
                'review_reasons': review_reasons,
            },
        }, status=200)
    except OCRProviderError as error:
        logger.warning('OCR provider could not process the scan: %s', error)
        return JsonResponse({'error': str(error)}, status=503)
    except ModelArtifactError as error:
        logger.error('The grading model is unavailable: %s', error)
        return JsonResponse({'error': str(error)}, status=503)
    except Exception:
        logger.exception('Automatic grading failed.')
        return JsonResponse({'error': 'Automatic grading failed.'}, status=500)


@csrf_exempt
def train_model_api(request: HttpRequest):
    if request.method != 'POST':
        return JsonResponse({'error': 'Only POST requests are allowed.'}, status=405)
    authentication_error = require_instructor(request)
    if authentication_error is not None:
        return authentication_error

    try:
        report = train_scoring_model()
        return JsonResponse({
            'status': 'success',
            'message': 'Model retrained successfully.',
            'report': report,
        }, status=200)
    except Exception:
        logger.exception('Model training failed.')
        return JsonResponse({'error': 'Model training failed.'}, status=500)
