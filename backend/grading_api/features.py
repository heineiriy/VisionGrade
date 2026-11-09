import re

import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin
from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS, TfidfVectorizer


class AnswerPairFeatures(BaseEstimator, TransformerMixin):
    def __init__(self):
        self._word_vectorizer = TfidfVectorizer(
            ngram_range=(1, 2),
            min_df=2,
            sublinear_tf=True,
        )
        self._char_vectorizer = TfidfVectorizer(
            analyzer='char_wb',
            ngram_range=(3, 5),
            min_df=2,
            sublinear_tf=True,
        )

    def _split_pair(self, value: str) -> tuple[str, str]:
        student, separator, expected = value.partition(' expected:')
        if not separator:
            raise ValueError('Grading text must include an expected answer.')
        if student.startswith('student:'):
            student = student[len('student:'):]
        return student, expected

    def fit(self, X, y=None):
        pairs = [self._split_pair(str(value)) for value in X]
        answer_texts = [text for pair in pairs for text in pair]
        self._word_vectorizer.fit(answer_texts)
        self._char_vectorizer.fit(answer_texts)
        return self

    def transform(self, X):
        pairs = [self._split_pair(str(value)) for value in X]
        student_answers = [student for student, _ in pairs]
        expected_answers = [expected for _, expected in pairs]

        student_words = self._word_vectorizer.transform(student_answers)
        expected_words = self._word_vectorizer.transform(expected_answers)
        student_chars = self._char_vectorizer.transform(student_answers)
        expected_chars = self._char_vectorizer.transform(expected_answers)
        word_similarity = np.asarray(
            student_words.multiply(expected_words).sum(axis=1),
        ).ravel()
        char_similarity = np.asarray(
            student_chars.multiply(expected_chars).sum(axis=1),
        ).ravel()

        features = []
        for index, (student, expected) in enumerate(pairs):
            student_tokens = [
                token
                for token in re.findall(r"[a-z0-9']+", student)
                if token not in ENGLISH_STOP_WORDS
            ]
            expected_tokens = [
                token
                for token in re.findall(r"[a-z0-9']+", expected)
                if token not in ENGLISH_STOP_WORDS
            ]
            student_words_set = set(student_tokens)
            expected_words_set = set(expected_tokens)
            common_words = student_words_set & expected_words_set
            all_words = student_words_set | expected_words_set
            student_negated = any(
                token in {"no", "not", "never"}
                for token in re.findall(r"[a-z']+", student)
            )
            expected_negated = any(
                token in {"no", "not", "never"}
                for token in re.findall(r"[a-z']+", expected)
            )

            features.append([
                word_similarity[index],
                char_similarity[index],
                len(common_words) / max(len(student_words_set), 1),
                len(common_words) / max(len(expected_words_set), 1),
                len(common_words) / max(len(all_words), 1),
                len(student_tokens) / max(len(expected_tokens), 1),
                float(student == expected),
                float(student_negated != expected_negated),
            ])

        return np.asarray(features, dtype=float)
