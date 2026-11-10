import json
import argparse
from functools import lru_cache
import re
from pathlib import Path

import joblib
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    cohen_kappa_score,
    f1_score,
    mean_absolute_error,
)
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import FeatureUnion, Pipeline

from .features import AnswerPairFeatures

BASE_DIR = Path(__file__).resolve().parent
MODEL_DIR = BASE_DIR / 'models'
MODEL_PATH = MODEL_DIR / 'answer_grader.joblib'
DATASET_PATH = BASE_DIR.parent / 'data' / 'student_answers.csv'
TEACHER_FEEDBACK_PATH = BASE_DIR.parent / 'data' / 'teacher_feedback.csv'
REFERENCE_DATASET_PATH = BASE_DIR.parent / 'data' / 'mohler_asag_open.csv'
SCIENTSBANK_TRAIN_PATH = BASE_DIR.parent / 'data' / 'scientsbank' / 'train.csv'
BEETLE_TRAIN_PATH = BASE_DIR.parent / 'data' / 'beetle' / 'train.csv'
JORGPT_TRAIN_PATH = BASE_DIR.parent / 'data' / 'jorgpt_en.csv'
JORGPT_VALIDATION_PATH = BASE_DIR.parent / 'data' / 'jorgpt_unseen_questions.csv'
DIGIKLAUSUR_TRAIN_PATH = BASE_DIR.parent / 'data' / 'digiklausur_asag.csv'
BENCHMARK_TEST_PATHS = {
    'scientsbank_unseen_answers': BASE_DIR.parent / 'data' / 'scientsbank' / 'test-ua.csv',
    'scientsbank_unseen_questions': BASE_DIR.parent / 'data' / 'scientsbank' / 'test-uq.csv',
    'scientsbank_unseen_domains': BASE_DIR.parent / 'data' / 'scientsbank' / 'test-ud.csv',
    'beetle_unseen_answers': BASE_DIR.parent / 'data' / 'beetle' / 'test-ua.csv',
    'beetle_unseen_questions': BASE_DIR.parent / 'data' / 'beetle' / 'test-uq.csv',
    'jorgpt_unseen_questions': JORGPT_VALIDATION_PATH,
}
TEMPLATE_PATH = BASE_DIR.parent / 'data' / 'student_answers_template.csv'


class ModelArtifactError(FileNotFoundError):
    pass


def normalize_text(value: str) -> str:
    if value is None:
        return ''
    text = re.sub(r'<[^>]+>', ' ', str(value))
    return re.sub(r'\s+', ' ', text).strip().lower()


def ensure_dataset(path: Path = DATASET_PATH, template_path: Path = TEMPLATE_PATH) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return path
    if path.resolve() != DATASET_PATH.resolve():
        raise FileNotFoundError(f'Dataset does not exist: {path}')

    template_rows = [
        {
            'question_id': 'q1',
            'student_answer': 'Plants make food using sunlight',
            'expected_answer': 'Photosynthesis is the process plants use to make food using sunlight',
            'score': 5,
        },
        {
            'question_id': 'q1',
            'student_answer': 'Plants use sunlight to grow',
            'expected_answer': 'Photosynthesis is the process plants use to make food using sunlight',
            'score': 3,
        },
        {
            'question_id': 'q1',
            'student_answer': 'They need water to live',
            'expected_answer': 'Photosynthesis is the process plants use to make food using sunlight',
            'score': 1,
        },
        {
            'question_id': 'q2',
            'student_answer': 'The heart pumps blood around the body',
            'expected_answer': 'The heart pumps blood around the body',
            'score': 5,
        },
        {
            'question_id': 'q2',
            'student_answer': 'The heart moves blood',
            'expected_answer': 'The heart pumps blood around the body',
            'score': 3,
        },
        {
            'question_id': 'q2',
            'student_answer': 'The brain controls the body',
            'expected_answer': 'The heart pumps blood around the body',
            'score': 0,
        },
        {
            'question_id': 'q3',
            'student_answer': 'Evaporation condensation and precipitation happen in the water cycle',
            'expected_answer': 'The water cycle includes evaporation, condensation and precipitation',
            'score': 5,
        },
        {
            'question_id': 'q3',
            'student_answer': 'Water goes into the air then falls as rain',
            'expected_answer': 'The water cycle includes evaporation, condensation and precipitation',
            'score': 4,
        },
        {
            'question_id': 'q3',
            'student_answer': 'There is rain and clouds',
            'expected_answer': 'The water cycle includes evaporation, condensation and precipitation',
            'score': 2,
        },
    ]

    df = pd.DataFrame(template_rows)
    df.to_csv(path, index=False)
    if template_path.exists() is False:
        df.to_csv(template_path, index=False)
    return path


def build_text(student_answer: str, expected_answer: str, question_id: str = '') -> str:
    student = normalize_text(student_answer)
    expected = normalize_text(expected_answer)
    # Dataset-specific identifiers do not transfer to new questions.
    return f"student:{student} expected:{expected}"


def _read_dataset(csv_path: Path) -> pd.DataFrame:
    dataset_path = ensure_dataset(csv_path)
    return pd.read_csv(dataset_path)


def load_dataset(csv_path: Path = DATASET_PATH) -> pd.DataFrame:
    frames = [_read_dataset(csv_path)]
    if csv_path.resolve() == DATASET_PATH.resolve():
        if TEACHER_FEEDBACK_PATH.is_file():
            frames.append(_read_dataset(TEACHER_FEEDBACK_PATH))
        for training_path in (
            REFERENCE_DATASET_PATH,
            SCIENTSBANK_TRAIN_PATH,
            BEETLE_TRAIN_PATH,
            JORGPT_TRAIN_PATH,
            DIGIKLAUSUR_TRAIN_PATH,
        ):
            frames.append(_read_dataset(training_path))
    df = pd.concat(frames, ignore_index=True)
    if 'expected_answer' not in df and 'ideal_answer' in df:
        df = df.rename(columns={'ideal_answer': 'expected_answer'})
    if 'score' not in df and 'teacher_grade' in df:
        df = df.rename(columns={'teacher_grade': 'score'})
    if 'question_id' not in df:
        df['question_id'] = 'teacher_feedback'
    if 'teacher_corrected' in df:
        corrected = df['teacher_corrected'].astype(str).str.strip().str.lower()
        df = df[corrected.isin({'true', '1', 'yes'})].copy()

    required = {'question_id', 'student_answer', 'expected_answer', 'score'}
    missing = sorted(required - set(df.columns))
    if missing:
        raise ValueError(f"Dataset is missing required columns: {missing}")

    df = df.loc[:, list(required)].copy()
    df['student_answer'] = df['student_answer'].fillna('').map(normalize_text)
    df['expected_answer'] = df['expected_answer'].fillna('').map(normalize_text)
    df['question_id'] = df['question_id'].fillna('unknown').astype(str)
    df['score'] = pd.to_numeric(df['score'], errors='coerce').astype(float)
    df = df.dropna(subset=['score']).copy()
    df = df[df['score'].between(0, 100)].copy()
    df = df[(df['student_answer'] != '') & (df['expected_answer'] != '')].drop_duplicates().copy()
    return df


def train_scoring_model(csv_path: Path = DATASET_PATH, save_path: Path = MODEL_PATH):
    df = load_dataset(csv_path)
    if len(df) < 10:
        raise ValueError('The dataset is too small to train a reliable model. Add at least 10 graded examples.')

    df['combined_text'] = df.apply(
        lambda row: build_text(row['student_answer'], row['expected_answer'], row['question_id']),
        axis=1,
    )

    X = df['combined_text']
    y = df['score'].round().astype(int)

    if y.nunique() < 2:
        raise ValueError('The dataset must contain more than one score label to train a classifier.')

    splitter = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
    train_indices, test_indices = next(
        splitter.split(X, y, groups=df['question_id'])
    )
    X_train, X_test = X.iloc[train_indices], X.iloc[test_indices]
    y_train, y_test = y.iloc[train_indices], y.iloc[test_indices]

    pipeline = Pipeline([
        ('tfidf', FeatureUnion([
            ('word', TfidfVectorizer(
                ngram_range=(1, 2),
                min_df=2,
                sublinear_tf=True,
            )),
            ('char', TfidfVectorizer(
                analyzer='char_wb',
                ngram_range=(3, 5),
                min_df=2,
                sublinear_tf=True,
            )),
            ('pair', AnswerPairFeatures()),
        ])),
        ('clf', LogisticRegression(max_iter=5000, C=1.0)),
    ])

    pipeline.fit(X_train, y_train)
    y_pred = pipeline.predict(X_test)
    test_probabilities = pipeline.predict_proba(X_test).max(axis=1)
    report = classification_report(y_test, y_pred, zero_division=0, output_dict=True)
    accuracy = accuracy_score(y_test, y_pred)
    weighted_kappa = cohen_kappa_score(y_test, y_pred, weights='quadratic')

    pipeline.fit(X, y)

    benchmark = {}
    for split_name, split_path in BENCHMARK_TEST_PATHS.items():
        test_df = _read_dataset(split_path)
        test_text = test_df.apply(
            lambda row: build_text(
                row['student_answer'],
                row['expected_answer'],
                row['question_id'],
            ),
            axis=1,
        )
        expected_scores = test_df['score'].round().astype(int)
        predicted_scores = pipeline.predict(test_text)
        split_kappa = cohen_kappa_score(
            expected_scores,
            predicted_scores,
            weights='quadratic',
        )
        benchmark[split_name] = {
            'samples': int(len(test_df)),
            'exact_accuracy': round(
                float(accuracy_score(expected_scores, predicted_scores)),
                4,
            ),
            'within_one_level_accuracy': round(
                float(
                    (
                        abs(
                            expected_scores.to_numpy()
                            - predicted_scores
                        )
                        <= 1
                    ).mean()
                ),
                4,
            ),
            'mean_absolute_error': round(
                float(mean_absolute_error(expected_scores, predicted_scores)),
                4,
            ),
            'quadratic_weighted_kappa': (
                round(float(split_kappa), 4)
                if pd.notna(split_kappa)
                else None
            ),
            'credit_decision_accuracy': round(
                float(accuracy_score(
                    expected_scores >= 3,
                    predicted_scores >= 3,
                )),
                4,
            ),
            'credit_decision_f1': round(
                float(f1_score(
                    expected_scores >= 3,
                    predicted_scores >= 3,
                    zero_division=0,
                )),
                4,
            ),
        }

    save_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipeline, save_path)

    metadata = {
        'model_path': str(save_path),
        'dataset_path': str(csv_path),
        'training_samples': int(len(df)),
        'test_samples': int(len(y_test)),
        'training_questions': int(df.iloc[train_indices]['question_id'].nunique()),
        'test_questions': int(df.iloc[test_indices]['question_id'].nunique()),
        'score_labels': sorted(y.unique().tolist()),
        'accuracy': round(float(accuracy), 4),
        'within_one_level_accuracy': round(
            float((abs(y_test.to_numpy() - y_pred) <= 1).mean()),
            4,
        ),
        'mean_absolute_error': round(float(mean_absolute_error(y_test, y_pred)), 4),
        'quadratic_weighted_kappa': (
            round(float(weighted_kappa), 4)
            if pd.notna(weighted_kappa)
            else None
        ),
        'confidence_coverage_metrics': {
            str(threshold): {
                'coverage': round(
                    float((test_probabilities >= threshold).mean()),
                    4,
                ),
                'exact_accuracy': round(
                    float(accuracy_score(
                        y_test[test_probabilities >= threshold],
                        y_pred[test_probabilities >= threshold],
                    )),
                    4,
                ) if (test_probabilities >= threshold).any() else None,
                'within_one_level_accuracy': round(
                    float((
                        abs(
                            y_test.to_numpy()[test_probabilities >= threshold]
                            - y_pred[test_probabilities >= threshold]
                        ) <= 1
                    ).mean()),
                    4,
                ) if (test_probabilities >= threshold).any() else None,
                'mean_absolute_error': round(
                    float(mean_absolute_error(
                        y_test[test_probabilities >= threshold],
                        y_pred[test_probabilities >= threshold],
                    )),
                    4,
                ) if (test_probabilities >= threshold).any() else None,
                'quadratic_weighted_kappa': round(
                    float(cohen_kappa_score(
                        y_test[test_probabilities >= threshold],
                        y_pred[test_probabilities >= threshold],
                        weights='quadratic',
                    )),
                    4,
                ) if (test_probabilities >= threshold).any() else None,
            }
            for threshold in (0.8, 0.9)
        },
        'held_out_benchmarks': benchmark,
        'report': report,
    }
    metadata_path = save_path.with_suffix('.json')
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding='utf-8')

    return metadata


def load_model(model_path: Path = MODEL_PATH):
    if not model_path.exists():
        raise ModelArtifactError(
            'The short-answer grading model is missing. Train it explicitly '
            'before requesting AI grading.'
        )
    resolved_path = model_path.resolve()
    stat = resolved_path.stat()
    return _load_model_cached(
        str(resolved_path),
        stat.st_mtime_ns,
        stat.st_size,
    )


@lru_cache(maxsize=4)
def _load_model_cached(model_path: str, modified_ns: int, size: int):
    return joblib.load(model_path)


def predict_score(student_answer: str, expected_answer: str, question_id: str = '', model_path: Path = MODEL_PATH):
    model = load_model(model_path)
    sample = build_text(student_answer, expected_answer, question_id)
    predicted_score = int(model.predict([sample])[0])
    probabilities = model.predict_proba([sample])[0]
    confidence = float(max(probabilities)) if len(probabilities) else 0.0
    return {
        'predicted_score': predicted_score,
        'max_score': int(model.classes_.max()),
        'confidence': round(confidence, 3),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Train the answer scoring model.')
    parser.add_argument('--dataset', type=Path, default=DATASET_PATH)
    parser.add_argument('--output', type=Path, default=MODEL_PATH)
    args = parser.parse_args()
    result = train_scoring_model(csv_path=args.dataset, save_path=args.output)
    print(json.dumps(result, indent=2, default=str))
