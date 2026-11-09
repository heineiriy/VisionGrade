# AES2 essay scoring dataset

VisionGrade uses `aes2_essay_scoring.csv` only for the separate free-form essay
scoring model. It is not merged into the short-answer/reference-answer model
because it has no expected answers, curriculum keywords, or diagram labels.

- Source: AES2 essay scoring dataset on Hugging Face
- License: CC BY-NC-4.0
- Rows used: 17,307 essays
- Labels: human essay scores mapped to integer levels 0 through 10
- Validation: stratified random holdout; essays from the same prompt may occur
  on both sides, so this is not a prompt-disjoint generalization estimate

The non-commercial license must be reviewed before deploying this model in a
commercial product. Instructor review remains mandatory.
