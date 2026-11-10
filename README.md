# visiongrade

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Student password resets

The web admin displays `student123` as the student password reset target. The
Reset to default action calls the authenticated `resetStudentPassword` Firebase
callable function; it does not read or store a student's current password.

Install the function dependencies from the `functions` directory, then deploy
the callable from the project root:

```powershell
cd functions
npm install
cd ..
firebase deploy --only functions:resetStudentPassword
```

The callable only permits the dashboard administrator emails listed in
`functions/index.js`. Firebase Functions deployment may require billing to be
enabled for the Firebase project.

## Short-answer grading model

Before an instructor reviews a text submission, VisionGrade sends the answer,
task context, and rubric to the Django grading API for an AI score suggestion.
Hardcopy scans use the same rubric grading after OCR. The suggested score is
pre-filled for teacher review and can be edited before publishing; the AI score
is never published as the final grade without instructor review. Configure the
API base URL with `GRADING_API_URL` when building or running Flutter:

```powershell
flutter run --dart-define=GRADING_API_URL=https://your-grading-api.example.com
```

For Android, the default API address is `http://10.59.80.76:8000` for the
physical device on the developer's current Wi-Fi network. Android emulators
should override it with `--dart-define=GRADING_API_URL=http://10.0.2.2:8000`;
web and desktop use `http://127.0.0.1:8000`. Start the backend from `backend`
for Android emulator testing with:

```powershell
$env:DJANGO_ALLOWED_HOSTS = 'localhost,127.0.0.1,10.0.2.2'
python manage.py runserver 0.0.0.0:8000
```

Production builds need a reachable HTTPS backend URL. The scan and task rubric
are sent to the API; extracted text, score suggestion, confidence, and rubric
insights are saved on the submission. AI scores remain suggestions until an
instructor reviews and saves a grade.
PDF task attachments open in the in-app viewer from task details and classwork
cards.

For Android debug testing over Wi-Fi, connect the phone and development
computer to the same trusted network. Start Django bound to all interfaces and
allow the computer's current LAN IP in `DJANGO_ALLOWED_HOSTS` (replace
`10.59.80.76` if the address changes):

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = Join-Path $env:APPDATA 'gcloud\application_default_credentials.json'
$env:DJANGO_ALLOWED_HOSTS = 'localhost,127.0.0.1,10.59.80.76'
Set-Location backend
python manage.py runserver 0.0.0.0:8000
```

In another terminal opened at the project root, build the debug APK with the
computer's current Wi-Fi IPv4 address:

```powershell
flutter build apk --debug --dart-define=GRADING_API_URL=http://10.59.80.76:8000
```

Install `build\app\outputs\flutter-apk\app-debug.apk` on the phone. The debug
Android manifest permits cleartext HTTP for this local development connection;
release builds do not inherit that setting. If the phone still cannot connect,
verify both devices are on the same Wi-Fi and allow inbound TCP port 8000 on
the Windows private network firewall. The backend also requires Google
Application Default Credentials, an available grading model, and a verified
active instructor account. Do not use this local HTTP configuration in
production; use a deployed HTTPS API.

Analytic rubric `score` values and weighted-criteria `weight` values are
criterion weights; blank weights use equal weighting, and holistic rubrics use
their configured point bands. Scan pages with OCR confidence below 40% are
returned for instructor review without an AI score. Rubric feedback is derived
from the teacher's level descriptions. Each rubric comparison includes the task
title and instructions, reference answers, learning objectives, and expected
concepts as context for interpreting the student's response; rubric criteria,
descriptions, and weights remain the scoring standard. When an instructor
scans work assigned to a named student, a clearly different name next to a
`Name:` or `Student name:` label prevents an AI score from being produced and
asks the instructor to verify the scan. Unlabeled or unclear names do not prove
ownership, so instructors must still verify every scan. When an instructor
publishes a grade, the submission retains the AI pre-score,
normalized teacher final score, any override reason, and the reviewed OCR,
rubric, score difference, and feedback in its `aiTrainingExample`. This is
evaluation logging only; model training remains an explicit operation.

The rubric editor also lets instructors select an optional grade-matched lesson
plan. Its learning objectives and expected concepts are stored with the task
rubric and sent as additional AI context; they do not replace the instructor's
rubric. The bundled
[`lesson_plans_g7_g10.json`](./assets/curriculum/lesson_plans_g7_g10.json)
contains 19 unique plans extracted from the provided PDFs after removing three
exact duplicate groups. The source plans declare AI assistance and do not
specify references, so instructors should verify the selected plan and its
concepts. Curriculum records are not score-labeled training examples and do not
automatically retrain either model.

To test grading on a physical Android device over USB, start the backend in one
PowerShell terminal. Port 8001 is used here to avoid conflicts with the web
admin server:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = Join-Path $env:APPDATA 'gcloud\application_default_credentials.json'
$env:DJANGO_ALLOWED_HOSTS = 'localhost,127.0.0.1'
Set-Location backend
python manage.py runserver 127.0.0.1:8001
```

In a second terminal, forward the API port to the connected phone and start the
app with the local grading launch configuration:

```powershell
adb reverse tcp:8001 tcp:8001
flutter run -d <device-id> --dart-define=GRADING_API_URL=http://127.0.0.1:8001
```

Alternatively, select **VisionGrade (Android with local grading API)** in
VS Code's Run and Debug menu; it supplies the API URL automatically. This
development setup requires USB debugging, the backend's trained model,
Tesseract OCR, and Google Application Default Credentials authorized to verify
instructors and read `instructor_accounts`. It is for local testing only; use a
deployed HTTPS API for production.

For Flutter Web, set `GRADING_ALLOWED_ORIGINS` on Django to the exact web-app
origin(s), comma-separated, so the browser can call the API. Install the
backend packages with `pip install -r requirements.txt` from `backend`.
EasyOCR is the primary OCR engine. When it cannot initialize, returns no text,
or has confidence below 40%, the backend retries with Azure Computer Vision
Image Analysis Read OCR. Configure the resource endpoint and key only on the
backend host:

```powershell
$env:AZURE_VISION_ENDPOINT = 'https://your-resource.cognitiveservices.azure.com'
$env:AZURE_VISION_KEY = 'your-resource-key'
```

The backend sends each fallback scan to Azure Computer Vision's synchronous
Image Analysis `read` API. Never put the key in the Flutter app or commit it to
source control. Azure fallback requires backend internet access and is subject
to Azure limits and pricing. Azure fallback results do not supply the app's
aggregate OCR confidence score, so scans using this fallback can receive an
AI score suggestion but always require instructor verification against the
original scan and are never eligible for high-confidence assisted grading. If
Azure is not configured or is unavailable, the API reports an explicit OCR
service error. Tesseract remains installed only for optional page orientation
detection. The backend verifies Firebase ID tokens and active instructor
accounts, so run it with Firebase Admin Application Default Credentials that
can read `instructor_accounts` (locally, configure
`GOOGLE_APPLICATION_CREDENTIALS`).

When an instructor saves a grade for a scanned submission, VisionGrade stores a
`aiTrainingExample` with the OCR text, task reference, and instructor's
corrected score (normalized to the model's 0-5 scale) in that submission.
Export only these reviewed examples from Firestore (the export omits student
names and email addresses) using Firebase Admin credentials authorized to read
the VisionGrade project:

```powershell
cd backend
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\path\to\firebase-service-account.json'
python -m grading_api.export_teacher_feedback
python -m unittest grading_api.test_train_model
python manage.py test grading_api.test_views
python -m grading_api.train_model
```

The export writes `backend/data/teacher_feedback.csv`, refuses to overwrite an
existing export unless `--overwrite` is specified, and is ignored by Git because
it contains student work. The trainer includes this optional CSV alongside the
existing training splits. Keep official benchmark test splits out of
teacher-feedback data. Model scores are imperfect suggestions; retain
instructor review, especially for handwriting and scans with low OCR quality.

The backend grader is trained with the local teacher-scored examples, Mohler
ASAG, SciEntsBank, Beetle, DigiKlausur ASAG, and the training portion of JorGPT.
JorGPT provides
real university computer-science answers with human grades; VisionGrade uses
its English translations and teacher grades only, not its LLM-generated
scores. The 0–10 human grades are mapped to VisionGrade's 0–5 scale. Its
question-level training/evaluation split, CC BY 4.0 license, and citation are
documented in
[`backend/data/JORGPT_ATTRIBUTION.md`](backend/data/JORGPT_ATTRIBUTION.md).
SciEntsBank and Beetle are also CC BY 4.0; their citations, score mappings, and
official split details are in
[`backend/data/scientsbank/ATTRIBUTION.md`](backend/data/scientsbank/ATTRIBUTION.md)
and [`backend/data/beetle/ATTRIBUTION.md`](backend/data/beetle/ATTRIBUTION.md).
Only dataset training splits are used for fitting. Public unseen-answer,
unseen-question, and unseen-domain data, plus ten disjoint JorGPT questions,
are held out for evaluation. The earlier DigiKlausur neural-network dataset
is not included in the current trainer because its measured held-out
performance was worse than training without it.

A Kaggle primary-school science dataset was also evaluated. Although it
contains 4,274 synthetic training answers under CC BY 4.0, adding its 3,331
unique usable examples improved its 37-answer test accuracy from 24.32% to
37.84%, but reduced SciEntsBank unseen-domain accuracy from 55.63% to 46.73%.
Because its holdout is small and it harmed broader generalization, it is not
mixed into the general model.

From the `backend` directory, run the dataset checks and train the model with
Python 3.13 plus pandas, NumPy, scikit-learn, and joblib installed:

```powershell
python -m unittest grading_api.test_train_model
python -m grading_api.train_model
```

The trained model and its report are written to
`backend/grading_api/models/answer_grader.joblib` and
`backend/grading_api/models/answer_grader.json`. The JorGPT holdout is grouped
by question to measure performance on questions the model never trained on.
With 2,473 JorGPT training answers, the model reaches 36.04% exact-score
accuracy on 530 answers from 10 held-out JorGPT questions (the baseline without
JorGPT scored 15.28% on that same split). This indicates a useful gain on
similar computer-science questions. Across the five existing SciEntsBank and
Beetle test splits, average exact-score accuracy changed only from 60.79% to
60.81%, so this is not evidence of a meaningful general accuracy increase.
The training-time grouped holdout is 49.79%; it is not directly comparable
with older reports because the training data and held-out group composition
changed. Review the report's metrics for each separate test set; do not treat
results on one subject-specific test as a guarantee for another subject.
Keep teacher review enabled and collect school-specific instructor
corrections before claiming an accuracy gain for this school's curriculum.

### Separate essay-scoring model

The larger `backend/data/aes2_essay_scoring.csv` dataset is trained as a
separate free-form essay model; it is not mixed into the short-answer model.
This prevents essay length/style signals from contaminating reference-answer
grading. Train it with:

```powershell
python -m grading_api.essay_model
```

The essay model is available to authenticated instructors through the grading
API by sending `{"task_type":"essay","essay_text":"..."}`. It returns an
AES2 1-6 AI suggestion and always requires instructor review. Its AES2 validation
is a stratified random holdout, not a prompt-disjoint school-specific
benchmark, and its CC BY-NC-4.0 license requires non-commercial use.
