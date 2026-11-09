import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'instructor_homepage.dart';
import 'student_homepage.dart';
import 'settings_screen.dart';
import 'draft_store.dart';

class SavedDraftPage extends StatefulWidget {
  static const Color burgundy = AppPalette.burgundy;

  final UserRole role;
  final String userName;
  final String? profileImageUrl;
  final Future<void> Function(BuildContext, DraftItem, int)? onEdit;

  const SavedDraftPage({
    super.key,
    required this.role,
    this.userName = '',
    this.profileImageUrl,
    this.onEdit,
  });

  @override
  State<SavedDraftPage> createState() => _SavedDraftPageState();
}

class _SavedDraftPageState extends State<SavedDraftPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top white header with logo and avatar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Expanded(child: VisionGradeWordmark(fontSize: 22)),
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: widget.profileImageUrl != null
                        ? NetworkImage(widget.profileImageUrl!)
                        : null,
                    backgroundColor: AppPalette.cream,
                    child: widget.profileImageUrl == null
                        ? const Icon(
                            Icons.person,
                            color: AppPalette.burgundyDark,
                          )
                        : null,
                  ),
                ],
              ),
            ),
            // Burgundy back bar
            Container(
              color: SavedDraftPage.burgundy,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Image.asset(
                      'white_curved_back_arrow.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Saved Drafts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: DraftStore.revision,
                builder: (context, _, child) {
                  return DraftStore.items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 84,
                                color: const Color(0xFF6284BD),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'No Drafts',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Your saved drafts will appear here',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: DraftStore.items.length,
                          itemBuilder: (context, index) {
                            final draft = DraftStore.items[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: Icon(
                                  draft.type == 'Task'
                                      ? Icons.assignment_outlined
                                      : Icons.campaign_outlined,
                                  color: SavedDraftPage.burgundy,
                                ),
                                title: Text(
                                  draft.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${draft.type} • ${draft.subjectTitle}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Edit draft',
                                      onPressed: widget.onEdit == null
                                          ? null
                                          : () => widget.onEdit!(
                                              context,
                                              draft,
                                              index,
                                            ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Delete draft',
                                      onPressed: () =>
                                          _confirmDeleteDraft(index, draft),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 44,
        decoration: const BoxDecoration(
          color: SavedDraftPage.burgundy,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: IconButton(
                  onPressed: () {
                    if (widget.role == UserRole.instructor) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => InstructorHomePage(
                            instructorName: widget.userName,
                            profileImageUrl: widget.profileImageUrl,
                          ),
                        ),
                        (route) => false,
                      );
                    } else {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => StudentHomePage(
                            studentName: widget.userName,
                            profileImageUrl: widget.profileImageUrl,
                          ),
                        ),
                        (route) => false,
                      );
                    }
                  },
                  tooltip: 'Home',
                  icon: SvgPicture.asset(
                    'home_icon.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                          role: widget.role,
                          userName: widget.userName,
                          profileImageUrl: widget.profileImageUrl,
                        ),
                      ),
                    );
                  },
                  icon: SvgPicture.asset(
                    'settings_offpage.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDraft(int index, DraftItem draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text('Delete "${draft.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    DraftStore.remove(index);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Draft deleted')));
  }
}
