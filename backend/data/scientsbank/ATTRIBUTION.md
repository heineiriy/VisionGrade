# SciEntsBank Dataset Attribution

- Dataset: SciEntsBank student response analysis corpus
- Source: https://huggingface.co/datasets/nkazi/SciEntsBank
- License: CC BY 4.0
- Original task and paper: Dzikovska et al. (2013), "SemEval-2013 Task 7: The Joint Student Response Analysis and 8th Recognizing Textual Entailment Challenge," https://aclanthology.org/S13-2045/
- Dataset card and split documentation: https://huggingface.co/datasets/nkazi/SciEntsBank

The CSV files preserve the dataset's official train, unseen-answer (`test-ua`),
unseen-question (`test-uq`), and unseen-domain (`test-ud`) splits. Only `train.csv`
is used for model fitting. The three test splits are retained for evaluation and
must not be added to training.

The original five-way labels are mapped to this app's 0-5 grading scale as
follows: `correct` = 5, `partially_correct_incomplete` = 3,
`contradictory` = 0, `irrelevant` = 0, and `non_domain` = 0. Partial answers
receive 3 because the app treats predicted scores of 3 or higher as earning
credit. This is a task-specific mapping, not a claim that the original corpus
used a numeric 0-5 score.
