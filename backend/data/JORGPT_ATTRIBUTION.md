# JorGPT Dataset Attribution

- Dataset: A Multilingual Dataset of Student Answers, Human Grading, and Multi-LLM Evaluations for Automated Assessment Research using JorGPT
- Kaggle source: https://www.kaggle.com/datasets/javiersanchezsoriano/jorgpt-student-answers-and-multi-llm-grading
- Canonical dataset record: https://doi.org/10.5281/zenodo.18981627
- Dataset license: Creative Commons Attribution 4.0 International (CC BY 4.0); see `CREATIVE-COMMONS-BY-4.0-LICENSE.txt`
- Paper: Cisneros-Gonzalez, J.; Gordo-Herrera, N.; Barcia-Santos, I.; Cerezo, Y.; Sanchez-Soriano, J. (2026). "A Multilingual Dataset of Student Answers, Human Grading, and Multi-LLM Evaluations for Automated Assessment Research Using JorGPT." *Data*, 11(3), 59. https://doi.org/10.3390/data11030059

The dataset contains 3,041 real answers from 50 university-level computer-science questions, with instructor ideal answers and human grades. VisionGrade uses the English-translated responses and `teacher_grade`, not any of the LLM-generated grades. It keeps only nonempty answers with a teacher grade marked as corrected, removes exact duplicate grading examples, and retains the question ID, student answer, ideal answer, and mapped score.

Human grades on the source 0-10 scale are converted to VisionGrade's 0-5 scale by rounding `grade / 2` to the nearest integer, with half points rounded up. The cleaned examples are split by question using `GroupShuffleSplit(test_size=0.2, random_state=42)`: 2,473 examples from 40 questions are used for training, and 530 examples from 10 disjoint questions are held out for evaluation. The held-out questions are not included in model fitting.

The downloaded English file was verified against the MD5 checksum published for the Zenodo record before conversion. The training CSV is `jorgpt_en.csv`; the question-level evaluation CSV is `jorgpt_unseen_questions.csv`.
