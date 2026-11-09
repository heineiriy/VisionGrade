import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import Ridge
from sklearn.metrics import accuracy_score, cohen_kappa_score, mean_absolute_error
from sklearn.model_selection import train_test_split
from sklearn.pipeline import FeatureUnion, Pipeline

from .train_model import ModelArtifactError

BASE_DIR = Path(__file__).resolve().parent
ESSAY_DATASET_PATH = BASE_DIR.parent / 'data' / 'aes2_essay_scoring.csv'
ESSAY_MODEL_PATH = BASE_DIR / 'models' / 'essay_scorer.joblib'


def _load_essay_dataset(path=ESSAY_DATASET_PATH):
    frame = pd.read_csv(path)
    required = {'full_text', 'score'}
    missing = sorted(required - set(frame.columns))
    if missing:
        raise ValueError(f'Essay dataset is missing required columns: {missing}')
    frame = frame.loc[:, ['full_text', 'score']].copy()
    frame['full_text'] = frame['full_text'].fillna('').astype(str).str.strip()
    frame['score'] = pd.to_numeric(frame['score'], errors='coerce')
    frame = frame.dropna(subset=['score'])
    frame = frame[frame['full_text'] != ''].copy()
    frame['score'] = frame['score'].round().clip(0, 10).astype(int)
    return frame.drop_duplicates()


def train_essay_model(
    dataset_path=ESSAY_DATASET_PATH,
    save_path=ESSAY_MODEL_PATH,
):
    frame = _load_essay_dataset(dataset_path)
    if len(frame) < 100 or frame['score'].nunique() < 2:
        raise ValueError('The essay dataset is too small to train a scoring model.')

    indices = np.arange(len(frame))
    train_indices, test_indices = train_test_split(
        indices,
        test_size=0.2,
        random_state=42,
        stratify=frame['score'],
    )
    pipeline = Pipeline([
        ('tfidf', FeatureUnion([
            ('word', TfidfVectorizer(
                ngram_range=(1, 2),
                min_df=2,
                max_features=100000,
                sublinear_tf=True,
            )),
            ('char', TfidfVectorizer(
                analyzer='char_wb',
                ngram_range=(3, 5),
                min_df=2,
                max_features=100000,
                sublinear_tf=True,
            )),
        ])),
        ('regressor', Ridge(alpha=1.0)),
    ])
    text = frame['full_text']
    labels = frame['score']
    pipeline.fit(text.iloc[train_indices], labels.iloc[train_indices])
    raw_predictions = pipeline.predict(text.iloc[test_indices])
    predictions = np.clip(np.rint(raw_predictions), 1, 6).astype(int)
    actual = labels.iloc[test_indices].to_numpy()
    kappa = cohen_kappa_score(actual, predictions, weights='quadratic')

    pipeline.fit(text, labels)
    save_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipeline, save_path)
    metadata = {
        'model_path': str(save_path),
        'dataset_path': str(dataset_path),
        'training_samples': int(len(frame)),
        'test_samples': int(len(test_indices)),
        'score_range': [1, 6],
        'exact_accuracy': round(float(accuracy_score(actual, predictions)), 4),
        'within_one_level_accuracy': round(
            float((np.abs(actual - predictions) <= 1).mean()), 4
        ),
        'mean_absolute_error': round(float(mean_absolute_error(actual, predictions)), 4),
        'quadratic_weighted_kappa': round(float(kappa), 4)
        if pd.notna(kappa) else None,
        'validation': 'stratified random holdout; not a prompt-disjoint benchmark',
        'production_scope': 'free-form essay scoring only; not short answers or diagrams',
        'license': 'CC BY-NC-4.0',
        'prediction_method': 'Ridge regression rounded to the nearest AES2 score level',
    }
    save_path.with_suffix('.json').write_text(
        json.dumps(metadata, indent=2),
        encoding='utf-8',
    )
    return metadata


def load_essay_model(model_path=ESSAY_MODEL_PATH):
    if not model_path.exists():
        raise ModelArtifactError(
            'The essay scoring model is missing. Train it explicitly before '
            'requesting AI grading.'
        )
    return joblib.load(model_path)


def predict_essay_score(essay_text, model_path=ESSAY_MODEL_PATH):
    if not isinstance(essay_text, str) or not essay_text.strip():
        raise ValueError('essay_text must be a non-empty string.')
    model = load_essay_model(model_path)
    raw_prediction = float(model.predict([essay_text])[0])
    prediction = int(np.clip(np.rint(raw_prediction), 1, 6))
    confidence = float(max(0.0, 1.0 - abs(raw_prediction - prediction)))
    return {
        'predicted_score': prediction,
        'max_score': 6,
        'confidence': round(confidence, 3),
        'requires_human_review': True,
        'model_scope': 'AES2 free-form essay scoring',
        'confidence_method': 'distance from rounded regression score; instructor review remains required',
    }


if __name__ == '__main__':
    print(json.dumps(train_essay_model(), indent=2))
