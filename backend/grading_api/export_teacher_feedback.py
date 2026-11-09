import argparse
import csv
import os
from pathlib import Path

import firebase_admin
from django.conf import settings
from firebase_admin import firestore
from google.auth.exceptions import DefaultCredentialsError

DATASET_PATH = Path(__file__).resolve().parent.parent / 'data' / 'teacher_feedback.csv'
FIELDNAMES = ('question_id', 'student_answer', 'expected_answer', 'score', 'teacher_corrected')


def training_row_from_submission(snapshot) -> dict[str, object] | None:
    path_parts = snapshot.reference.path.split('/')
    if (
        len(path_parts) != 6
        or path_parts[0] != 'subjects'
        or path_parts[2] != 'posts'
        or path_parts[4] != 'submissions'
    ):
        return None

    data = snapshot.to_dict() or {}
    example = data.get('aiTrainingExample')
    if not isinstance(example, dict) or example.get('teacher_corrected') is not True:
        return None

    student_answer = example.get('student_answer')
    expected_answer = example.get('expected_answer')
    score = example.get('score')
    if (
        not isinstance(student_answer, str)
        or not student_answer.strip()
        or not isinstance(expected_answer, str)
        or not expected_answer.strip()
        or isinstance(score, bool)
        or not isinstance(score, (int, float))
        or not 0 <= score <= 5
    ):
        return None

    return {
        'question_id': f'{path_parts[1]}:{path_parts[3]}',
        'student_answer': student_answer.strip(),
        'expected_answer': expected_answer.strip(),
        'score': score,
        'teacher_corrected': True,
    }


def export_teacher_feedback(
    output_path: Path = DATASET_PATH,
    *,
    overwrite: bool = False,
) -> int:
    if output_path.exists() and not overwrite:
        raise FileExistsError(
            f'{output_path} already exists; pass --overwrite to replace it.'
        )

    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'visiongrade_backend.settings')
    from django import setup

    setup()
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(options={'projectId': settings.FIREBASE_PROJECT_ID})

    client = firestore.client()
    rows = []
    for subject in client.collection('subjects').stream():
        for task in subject.reference.collection('posts').stream():
            snapshots = (
                task.reference.collection('submissions')
                .where('aiTrainingExample.teacher_corrected', '==', True)
                .stream()
            )
            rows.extend(
                row
                for snapshot in snapshots
                if (row := training_row_from_submission(snapshot)) is not None
            )
    if not rows:
        raise ValueError(
            'No valid instructor-reviewed AI grading examples were found in Firestore.'
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open('w', newline='', encoding='utf-8') as output_file:
        writer = csv.DictWriter(output_file, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Export instructor-corrected grading examples from Firestore.'
    )
    parser.add_argument('--output', type=Path, default=DATASET_PATH)
    parser.add_argument(
        '--overwrite',
        action='store_true',
        help='Replace the output CSV if it already exists.',
    )
    args = parser.parse_args()

    try:
        exported_count = export_teacher_feedback(args.output, overwrite=args.overwrite)
    except DefaultCredentialsError as error:
        raise SystemExit(
            'Firebase Admin credentials are unavailable. Set '
            'GOOGLE_APPLICATION_CREDENTIALS to a service account JSON file '
            'authorized to read this project.'
        ) from error
    print(f'Exported {exported_count} instructor-reviewed examples to {args.output}.')
