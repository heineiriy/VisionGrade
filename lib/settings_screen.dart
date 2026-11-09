import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remember_me_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_theme.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
import 'home_screen.dart';
import 'instructor_homepage.dart';
import 'student_homepage.dart';
import 'splashscreen.dart';
import 'presence_service.dart';
import 'local_notification_service.dart';

class SettingsScreen extends StatefulWidget {
  final UserRole role;
  final String userName;
  final String userEmail;
  final String? profileImageUrl;

  const SettingsScreen({
    super.key,
    required this.role,
    this.userName = '',
    this.userEmail = '',
    this.profileImageUrl,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _displayName;
  String _language = 'English';
  bool _notificationsEnabled = true;
  String? _currentProfileImageUrl;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _currentProfileImageUrl =
        widget.profileImageUrl ?? FirebaseAuth.instance.currentUser?.photoURL;
    _displayName = widget.userName.isNotEmpty
        ? widget.userName
        : FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ==
              true
        ? FirebaseAuth.instance.currentUser!.displayName!
        : (widget.role == UserRole.instructor ? 'Instructor' : 'Student');
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _language = prefs.getString('settings_language') ?? 'English';
      _notificationsEnabled = prefs.getBool('settings_notifications') ?? true;
    });
  }

  Future<void> _saveStringPreference(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBoolPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openClassSchedule() {
    final email = widget.userEmail.trim().isNotEmpty
        ? widget.userEmail.trim()
        : FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstructorClassesScheduleScreen(instructorEmail: email),
      ),
    );
  }

  String _profileValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value == null ? '' : value.toString();
  }

  Future<void> _changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    if (currentPassword.trim().isEmpty) {
      _showMessage('Please enter your current password.');
      return;
    }

    if (newPassword.trim().length < 6) {
      _showMessage('New password must be at least 6 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      _showMessage('The new password and confirmation do not match.');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final email = currentUser?.email;
    if (currentUser == null || email == null || email.isEmpty) {
      _showMessage('You must be signed in to change the password.');
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await currentUser.reauthenticateWithCredential(credential);
      await currentUser.updatePassword(newPassword);
      _showMessage('Password updated successfully.');
    } on FirebaseAuthException catch (error) {
      if (error.code == 'wrong-password') {
        _showMessage('Your current password is incorrect.');
      } else {
        _showMessage('Unable to update password right now.');
      }
    } catch (_) {
      _showMessage('Unable to update password right now.');
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    try {
      await _saveBoolPreference('settings_notifications', value);
      await LocalNotificationService.setEnabled(value);
      if (mounted) {
        setState(() {
          _notificationsEnabled = value;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Could not update notification settings: $error\n$stackTrace');
      _showMessage('Could not save notification settings. Please try again.');
    }
  }

  Future<void> _setLanguage(String value) async {
    await _saveStringPreference('settings_language', value);
    setState(() {
      _language = value;
    });
  }

  Future<void> _pickAndUploadProfileImage({
    required VoidCallback onUploadStateChanged,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Please sign in before changing your picture.');
      return;
    }

    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a picture'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1000,
        maxHeight: 1000,
      );
      if (pickedFile == null || !mounted) return;

      setState(() {
        _isUploadingAvatar = true;
      });
      onUploadStateChanged();

      final fileSize = await pickedFile.length().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Reading the selected picture size timed out.',
        ),
      );
      if (fileSize > 10 * 1024 * 1024) {
        _showMessage('Choose a smaller picture (maximum size is 10 MB).');
        return;
      }

      final imageBytes = await pickedFile.readAsBytes().timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw TimeoutException('Reading the selected picture timed out.'),
      );
      if (imageBytes.isEmpty) {
        _showMessage('The selected picture is empty. Choose another image.');
        return;
      }
      if (imageBytes.length > 10 * 1024 * 1024) {
        _showMessage('Choose a smaller picture (maximum size is 10 MB).');
        return;
      }
      final downloadUrl =
          await CloudinaryService.uploadBytes(
            bytes: imageBytes,
            fileName:
                'profile_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            timeout: const Duration(seconds: 60),
          ).timeout(
            const Duration(seconds: 65),
            onTimeout: () =>
                throw TimeoutException('Profile picture upload timed out.'),
          );

      final collection = widget.role == UserRole.instructor
          ? 'instructor_accounts'
          : 'students';
      final userDocs = await FirebaseFirestore.instance
          .collection(collection)
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get()
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw TimeoutException('Profile document request timed out.'),
          );

      if (userDocs.docs.isEmpty) {
        throw StateError('No profile document found for the signed-in user.');
      }
      await userDocs.docs.first.reference
          .update({'profileImageUrl': downloadUrl, 'photoUrl': downloadUrl})
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw TimeoutException('Profile update request timed out.'),
          );
      await currentUser
          .updatePhotoURL(downloadUrl)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw TimeoutException('Account profile update timed out.'),
          );

      if (!mounted) return;
      setState(() {
        _currentProfileImageUrl = downloadUrl;
      });
      _showMessage('Profile picture updated successfully.');
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Failed to update profile picture: $error\n$stackTrace');
      _showMessage(
        error.code == 'unauthorized' || error.code == 'permission-denied'
            ? 'Firebase blocked the picture update. Deploy the latest Firestore and Storage rules.'
            : 'Could not save the picture (${error.code}). Please try again.',
      );
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('Profile picture update timed out: $error\n$stackTrace');
      _showMessage(
        error.message ?? 'Picture update timed out. Please try again.',
      );
    } on CloudinaryUploadException catch (error, stackTrace) {
      debugPrint(
        'Cloudinary profile picture upload failed: $error\n$stackTrace',
      );
      _showMessage('Could not upload the picture. Please try again.');
    } catch (error, stackTrace) {
      debugPrint('Failed to update profile picture: $error\n$stackTrace');
      _showMessage('Something went wrong while updating your picture.');
    } finally {
      if (mounted && _isUploadingAvatar) {
        setState(() {
          _isUploadingAvatar = false;
        });
        onUploadStateChanged();
      }
    }
  }

  Future<void> _showProfileDialog() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Please sign in to edit your profile.');
      return;
    }

    final collection = widget.role == UserRole.instructor
        ? 'instructor_accounts'
        : 'students';
    QueryDocumentSnapshot<Map<String, dynamic>>? userDocument;
    Map<String, dynamic> userData = {};
    try {
      final result = await FirebaseFirestore.instance
          .collection(collection)
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();
      if (result.docs.isNotEmpty) {
        userDocument = result.docs.first;
        userData = userDocument.data();
      }
    } on FirebaseException {
      _showMessage('Could not load your profile. Please try again.');
      return;
    } catch (error, stackTrace) {
      debugPrint('Failed to load profile details: $error\n$stackTrace');
      _showMessage('Could not load your profile. Please try again.');
      return;
    }
    if (!mounted) return;
    final profileDocument = userDocument;
    if (profileDocument == null) {
      _showMessage(
        'Could not find your profile. Please contact your school administrator.',
      );
      return;
    }

    final savedProfileImageUrl =
        _profileValue(userData, 'profileImageUrl').isNotEmpty
        ? _profileValue(userData, 'profileImageUrl')
        : _profileValue(userData, 'photoUrl');
    if (savedProfileImageUrl.isNotEmpty &&
        savedProfileImageUrl != _currentProfileImageUrl) {
      setState(() {
        _currentProfileImageUrl = savedProfileImageUrl;
      });
    }

    final nameController = TextEditingController(
      text: _profileValue(userData, 'name').isNotEmpty
          ? _profileValue(userData, 'name')
          : _displayName,
    );
    final phoneController = TextEditingController(
      text: _profileValue(userData, 'phoneNumber').isNotEmpty
          ? _profileValue(userData, 'phoneNumber')
          : _profileValue(userData, 'phone'),
    );
    final emailController = TextEditingController(
      text: currentUser.email ?? widget.userEmail,
    );
    const genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];
    final storedGender = _profileValue(userData, 'gender').trim();
    var selectedGender = genderOptions.firstWhere(
      (option) => option.toLowerCase() == storedGender.toLowerCase(),
      orElse: () => '',
    );

    var didSave = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit profile'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _isUploadingAvatar
                        ? null
                        : () async {
                            await _pickAndUploadProfileImage(
                              onUploadStateChanged: () {
                                if (dialogContext.mounted) {
                                  setDialogState(() {});
                                }
                              },
                            );
                          },
                    borderRadius: BorderRadius.circular(48),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundImage: _currentProfileImageUrl == null
                              ? null
                              : NetworkImage(_currentProfileImageUrl!),
                          backgroundColor: Colors.grey.shade200,
                          child: _currentProfileImageUrl == null
                              ? const Icon(Icons.person, size: 38)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppPalette.burgundy,
                              shape: BoxShape.circle,
                            ),
                            child: _isUploadingAvatar
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isUploadingAvatar
                        ? null
                        : () async {
                            await _pickAndUploadProfileImage(
                              onUploadStateChanged: () {
                                if (dialogContext.mounted) {
                                  setDialogState(() {});
                                }
                              },
                            );
                          },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Change profile picture'),
                  ),
                  const SizedBox(height: 12),
                  _profileTextField(nameController, 'Full name'),
                  const SizedBox(height: 12),
                  _profileTextField(
                    emailController,
                    'Email Address',
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),
                  _profileTextField(phoneController, 'Phone Number'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGender.isEmpty
                        ? null
                        : selectedGender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      border: OutlineInputBorder(),
                    ),
                    items: genderOptions
                        .map(
                          (gender) => DropdownMenuItem(
                            value: gender,
                            child: Text(gender),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      selectedGender = value ?? '';
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Name cannot be empty.')),
                  );
                  return;
                }

                final updates = <String, dynamic>{
                  'name': name,
                  'phoneNumber': phoneController.text.trim(),
                  'gender': selectedGender,
                };
                try {
                  await currentUser.updateDisplayName(name);
                  await profileDocument.reference.update(updates);
                  if (!dialogContext.mounted) return;
                  didSave = true;
                  Navigator.of(dialogContext).pop();
                } on FirebaseAuthException {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Could not update your account name.'),
                    ),
                  );
                } on FirebaseException {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not save your profile. Please try again.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final savedName = nameController.text.trim();
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    if (didSave && mounted) {
      setState(() {
        _displayName = savedName;
      });
      _showMessage('Profile updated successfully.');
    }
  }

  Widget _profileTextField(
    TextEditingController controller,
    String label, {
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  void _showPasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _changePassword(
                currentPasswordController.text,
                newPasswordController.text,
                confirmPasswordController.text,
              );
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showNotificationDialog() {
    bool localValue = _notificationsEnabled;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Notification settings'),
          content: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable reminders'),
            subtitle: const Text('Receive assignment and class alerts.'),
            value: localValue,
            onChanged: (value) {
              localValue = value;
              setStateDialog(() {});
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _toggleNotifications(localValue);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    final options = ['English', 'Filipino', 'Spanish'];
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Language'),
        children: options.map((language) {
          final isSelected = _language == language;
          return RadioListTile<String>(
            title: Text(language),
            value: language,
            groupValue: _language,
            onChanged: (value) async {
              if (value == null) return;
              Navigator.of(dialogContext).pop();
              await _setLanguage(value);
            },
            selected: isSelected,
          );
        }).toList(),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Help & support'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. View your email and update your name, phone number, gender, or picture in Profile.',
              ),
              SizedBox(height: 8),
              Text(
                '2. Change your password anytime from the Password section.',
              ),
              SizedBox(height: 8),
              Text('3. Turn reminders on or off from Notifications.'),
              SizedBox(height: 8),
              Text(
                '4. Contact your school admin for class or subject concerns.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final supportUri = Uri(
                scheme: 'mailto',
                path: 'support@visiongrade.edu',
                query: 'subject=VisionGrade%20Support',
              );
              if (await canLaunchUrl(supportUri)) {
                await launchUrl(supportUri);
              }
            },
            child: const Text('Contact support'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSettingsList() {
    final settings = widget.role == UserRole.instructor
        ? [
            _SettingRow(
              icon: Icons.person_outline,
              title: 'Profile',
              subtitle:
                  'View your email and edit your name, phone, gender, and picture',
              onTap: _showProfileDialog,
            ),
            _SettingRow(
              icon: Icons.badge_outlined,
              title: 'Instructor Details',
              subtitle: 'Department, office hours, and contact info',
              onTap: () =>
                  _showMessage('Instructor details are ready for setup.'),
            ),
            _SettingRow(
              icon: Icons.class_rounded,
              title: 'Classes & Schedule',
              subtitle: 'Manage assigned classes and teaching timetable',
              onTap: _openClassSchedule,
            ),
            _SettingRow(
              icon: Icons.lock_outline,
              title: 'Password',
              subtitle: 'Set a stronger account password',
              onTap: _showPasswordDialog,
            ),
            _SettingRow(
              icon: Icons.notifications_none,
              title: 'Notification',
              subtitle: 'Assignment reminders and updates',
              onTap: _showNotificationDialog,
            ),
            _SettingRow(
              icon: Icons.help_outline,
              title: 'Help',
              subtitle: 'Support and guidance for account usage',
              onTap: _showHelpDialog,
            ),
          ]
        : [
            _SettingRow(
              icon: Icons.person_outline,
              title: 'Profile',
              subtitle:
                  'View your email and edit your name, phone, gender, and picture',
              onTap: _showProfileDialog,
            ),
            _SettingRow(
              icon: Icons.lock_outline,
              title: 'Password',
              subtitle: 'Set a stronger account password',
              onTap: _showPasswordDialog,
            ),
            _SettingRow(
              icon: Icons.notifications_none,
              title: 'Notification',
              subtitle: 'Task reminders and class updates',
              onTap: _showNotificationDialog,
            ),
            _SettingRow(
              icon: Icons.help_outline,
              title: 'Help',
              subtitle: 'Tips for using the app',
              onTap: _showHelpDialog,
            ),
          ];

    final rows = <Widget>[];
    for (var i = 0; i < settings.length; i++) {
      rows.add(settings[i]);
      if (i < settings.length - 1) {
        rows.add(const Divider(height: 1));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppPalette.burgundy,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Image.asset(
                          'white_curved_back_arrow.png',
                          width: 18,
                          height: 18,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        color: AppPalette.cream,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundImage: _currentProfileImageUrl != null
                                    ? NetworkImage(_currentProfileImageUrl!)
                                    : null,
                                backgroundColor: Colors.white,
                                child: _currentProfileImageUrl == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.userEmail,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        color: AppPalette.cream,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(children: _buildSettingsList()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await LocalNotificationService.stop();
                                await PresenceService.stop();
                                await RememberMeStore.clear();
                                await FirebaseAuth.instance.signOut();
                                if (!context.mounted) return;
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const SplashScreen(),
                                  ),
                                  (route) => false,
                                );
                              },
                              icon: const Icon(
                                Icons.logout,
                                size: 15,
                                color: AppPalette.ink,
                              ),
                              label: const Text(
                                'Log out',
                                style: TextStyle(
                                  color: AppPalette.ink,
                                  fontSize: 11,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppPalette.ink,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 4,
                                ),
                                side: const BorderSide(color: AppPalette.ink),
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 44,
        decoration: const BoxDecoration(
          color: AppPalette.burgundy,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned(
                left: constraints.maxWidth * 0.25,
                top: 2,
                child: _buildBottomNavButton(
                  icon: SvgPicture.asset(
                    'home_icon.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: () {
                    if (widget.role == UserRole.instructor) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => InstructorHomePage(
                            instructorName: widget.userName,
                            instructorEmail: widget.userEmail,
                            profileImageUrl: _currentProfileImageUrl,
                          ),
                        ),
                        (route) => false,
                      );
                    } else {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => StudentHomePage(
                            studentName: widget.userName,
                            studentEmail: widget.userEmail,
                            profileImageUrl: _currentProfileImageUrl,
                          ),
                        ),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),
              Positioned(
                right: constraints.maxWidth * 0.25,
                top: 2,
                child: _buildBottomNavButton(
                  icon: SvgPicture.asset(
                    'settings_onpage.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      AppPalette.burgundyDark,
                      BlendMode.srcIn,
                    ),
                  ),
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavButton({
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    const buttonSize = 40.0;
    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(
          width: buttonSize,
          height: buttonSize,
        ),
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }
}

class InstructorClassesScheduleScreen extends StatelessWidget {
  final String instructorEmail;

  const InstructorClassesScheduleScreen({
    super.key,
    required this.instructorEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classes & Schedule')),
      body: instructorEmail.isEmpty
          ? const Center(child: Text('Sign in to view your assigned classes.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.instructorSubjectsStream(
                instructorEmail,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Unable to load your classes. Please try again.',
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final classes =
                    (snapshot.data?.docs ?? const [])
                        .where((doc) => doc.data()['isArchived'] != true)
                        .toList()
                      ..sort((a, b) {
                        final aName = (a.data()['name'] as String? ?? '')
                            .toLowerCase();
                        final bName = (b.data()['name'] as String? ?? '')
                            .toLowerCase();
                        return aName.compareTo(bName);
                      });

                if (classes.isEmpty) {
                  return const Center(
                    child: Text('No active classes are assigned to you.'),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${classes.length} ${classes.length == 1 ? 'class' : 'classes'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final classDocument in classes)
                      _InstructorClassOverviewCard(data: classDocument.data()),
                  ],
                );
              },
            ),
    );
  }
}

class _InstructorClassOverviewCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _InstructorClassOverviewCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = _firstClassValue(data, const ['name', 'title']) ?? 'Class';
    final grade = _firstClassValue(data, const ['year', 'yearLevel', 'grade']);
    final section = _firstClassValue(data, const ['section', 'classSection']);
    final room = _firstClassValue(data, const [
      'room',
      'classroom',
      'location',
      'roomNumber',
    ]);
    final schedule =
        data.entries
            .where((entry) => _isScheduleField(entry.key))
            .map(
              (entry) => MapEntry(entry.key, _formatScheduleValue(entry.value)),
            )
            .where((entry) => entry.value.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppPalette.cream,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppPalette.burgundy,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.class_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (grade != null || section != null) ...[
              const SizedBox(height: 12),
              _ClassDetailLine(
                icon: Icons.school_outlined,
                text: [grade, section].whereType<String>().join(' · '),
              ),
            ],
            if (room != null) ...[
              const SizedBox(height: 8),
              _ClassDetailLine(icon: Icons.location_on_outlined, text: room),
            ],
            const Divider(height: 24),
            const Text(
              'Schedule',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (schedule.isEmpty)
              const Text(
                'No schedule details are available for this class.',
                style: TextStyle(color: AppPalette.muted),
              )
            else
              for (var index = 0; index < schedule.length; index++) ...[
                _ClassDetailLine(
                  icon: Icons.schedule_outlined,
                  text:
                      '${_formatFieldName(schedule[index].key)}: '
                      '${schedule[index].value}',
                ),
                if (index < schedule.length - 1) const SizedBox(height: 6),
              ],
          ],
        ),
      ),
    );
  }
}

class _ClassDetailLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ClassDetailLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppPalette.burgundyDark),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

String? _firstClassValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

bool _isScheduleField(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('schedule') ||
      normalized.contains('day') ||
      normalized.contains('time') ||
      normalized.contains('meeting') ||
      normalized.contains('period');
}

String _formatFieldName(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );
  return spaced.replaceAll('_', ' ').trim();
}

String _formatScheduleValue(Object? value) {
  if (value == null) return '';
  if (value is Timestamp) return _formatScheduleValue(value.toDate());
  if (value is DateTime) {
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$date at $hour:$minute $period';
  }
  if (value is Iterable) {
    return value
        .map(_formatScheduleValue)
        .where((item) => item.isNotEmpty)
        .join(', ');
  }
  if (value is Map) {
    return value.entries
        .map(
          (entry) =>
              '${_formatFieldName(entry.key.toString())}: '
              '${_formatScheduleValue(entry.value)}',
        )
        .where((item) => !item.endsWith(': '))
        .join(' · ');
  }
  return value.toString().trim();
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}
