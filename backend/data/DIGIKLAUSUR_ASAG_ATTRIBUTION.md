# DigiKlausur ASAG Dataset Attribution

- Dataset: Assisted Short Answer Grading (ASAG) Dataset
- Source: https://github.com/DigiKlausur/ASAG-Dataset
- Upstream revision: `1bfa98fa7edbb0e86fd66e067c64927e4d89e0c7`
- Repository license: Mozilla Public License 2.0; see `DIGIKLAUSUR-MPL-2.0-LICENSE.txt`
- Source dataset: `asag_dataset.csv`
- Original collection: 646 answers from 38 graduate students across 17 neural-network exam questions, graded by one human judge. 607 nonempty student answers are included in this training file.

The upstream dataset uses grades 0 (incorrect), 1 (partially correct), and 2 (perfect). VisionGrade maps these to 0, 3, and 5 on its 0–5 grading scale. The answers are specific to a graduate neural-networks course and may not represent other subjects.

Only the question identifier, student answer, reference answer, and mapped score are retained. The training question IDs are prefixed with `digiklausur_asag:` to keep them separate from other datasets.
