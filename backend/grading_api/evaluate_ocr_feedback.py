import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path

DEFAULT_DATASET_PATH = (
    Path(__file__).resolve().parent.parent / 'data' / 'teacher_feedback.csv'
)


def _edit_distance(reference: list[str], hypothesis: list[str]) -> int:
    previous = list(range(len(hypothesis) + 1))
    for row_index, reference_item in enumerate(reference, start=1):
        current = [row_index]
        for column_index, hypothesis_item in enumerate(hypothesis, start=1):
            current.append(min(
                current[-1] + 1,
                previous[column_index] + 1,
                previous[column_index - 1]
                + (reference_item != hypothesis_item),
            ))
        previous = current
    return previous[-1]


def _empty_metrics() -> dict[str, int]:
    return {
        'samples': 0,
        'word_errors': 0,
        'reference_words': 0,
        'character_errors': 0,
        'reference_characters': 0,
    }


def _add_sample(metrics: dict[str, int], ocr_text: str, corrected_text: str) -> None:
    normalized_ocr = ' '.join(ocr_text.casefold().split())
    normalized_corrected = ' '.join(corrected_text.casefold().split())
    reference_words = normalized_corrected.split()
    ocr_words = normalized_ocr.split()
    metrics['samples'] += 1
    metrics['word_errors'] += _edit_distance(reference_words, ocr_words)
    metrics['reference_words'] += len(reference_words)
    metrics['character_errors'] += _edit_distance(
        list(normalized_corrected),
        list(normalized_ocr),
    )
    metrics['reference_characters'] += len(normalized_corrected)


def _finish_metrics(metrics: dict[str, int]) -> dict[str, int | float]:
    return {
        **metrics,
        'wer': round(metrics['word_errors'] / metrics['reference_words'], 4),
        'cer': round(
            metrics['character_errors'] / metrics['reference_characters'],
            4,
        ),
    }


def evaluate_ocr_feedback(dataset_path: Path = DEFAULT_DATASET_PATH) -> dict:
    with dataset_path.open(newline='', encoding='utf-8-sig') as dataset_file:
        reader = csv.DictReader(dataset_file)
        required = {'ocr_text', 'corrected_text', 'ocr_engine'}
        missing = sorted(required - set(reader.fieldnames or ()))
        if missing:
            raise ValueError(
                f'OCR feedback dataset is missing required columns: {missing}'
            )

        overall = _empty_metrics()
        by_engine = defaultdict(_empty_metrics)
        skipped_samples = 0
        for row in reader:
            ocr_text = (row.get('ocr_text') or '').strip()
            corrected_text = (row.get('corrected_text') or '').strip()
            if not ocr_text or not corrected_text:
                skipped_samples += 1
                continue
            engine = (row.get('ocr_engine') or '').strip() or 'unknown'
            _add_sample(overall, ocr_text, corrected_text)
            _add_sample(by_engine[engine], ocr_text, corrected_text)

    if overall['samples'] == 0:
        raise ValueError(
            'No complete OCR feedback examples found; review scanned work '
            'and export teacher feedback first.'
        )

    return {
        'dataset_path': str(dataset_path),
        'evaluated_samples': overall['samples'],
        'skipped_samples': skipped_samples,
        'overall': _finish_metrics(overall),
        'by_engine': {
            engine: _finish_metrics(metrics)
            for engine, metrics in sorted(by_engine.items())
        },
        'metric_definitions': {
            'wer': 'case-folded, whitespace-normalized word edit errors divided by reference word count',
            'cer': 'case-folded, whitespace-normalized character edit errors divided by reference character count',
            'reference': 'teacher-corrected OCR transcription',
        },
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Measure OCR errors against teacher-corrected transcriptions.'
    )
    parser.add_argument('--dataset', type=Path, default=DEFAULT_DATASET_PATH)
    parser.add_argument(
        '--output',
        type=Path,
        help='Optional path for the JSON metrics report.',
    )
    args = parser.parse_args()
    result = evaluate_ocr_feedback(args.dataset)
    report = json.dumps(result, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report + '\n', encoding='utf-8')
    print(report)
