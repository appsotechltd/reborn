import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../blocks/block_actions.dart';
import 'appearance_settings.dart';
import 'reading_settings.dart';

final _handlePattern = RegExp(r'^[a-z0-9_]{3,30}$');

/// Appearance for everyone; signed in, also handle, bio and account.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _handle;
  late final TextEditingController _bio;
  String? _handleError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).user;
    _handle = TextEditingController(text: user?.handle ?? '');
    _bio = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _handleError = null);
    if (!_form.currentState!.validate()) return;
    final user = ref.read(sessionProvider).user;
    final handle = _handle.text.trim().toLowerCase();
    final bio = _bio.text.trim();
    final changedHandle = handle != (user?.handle ?? '');
    final changedBio = bio != (user?.bio ?? '');
    if (!changedHandle && !changedBio) return;
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(repositoryProvider)
          .updateMe(
            handle: changedHandle ? handle : null,
            bio: changedBio ? bio : null,
          );
      await ref.read(sessionProvider.notifier).setUser(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'handle_taken') {
        setState(() => _handleError = 'That handle is taken. Try another.');
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account and everything in it: '
          'collections, reviews, favourites, follows, comments and '
          'contributions. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
      router.go('/home');
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!session.signedIn) {
      return Scaffold(
        appBar: AppBar(
          leading: exitLeading(context),
          title: const Text('Settings'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            ReadingWidth(child: AppearanceSettings()),
            SizedBox(height: 8),
            SignInPrompt(
              icon: Icons.settings_outlined,
              title: 'Your profile',
              message: 'Sign in to edit your profile.',
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ReadingWidth(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppearanceSettings(),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('Public profile', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('settings-handle'),
                    controller: _handle,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Handle',
                      prefixText: '@',
                      helperText: '3-30 lowercase letters, digits or _',
                      errorText: _handleError,
                    ),
                    validator: (v) =>
                        _handlePattern.hasMatch((v ?? '').trim().toLowerCase())
                        ? null
                        : 'Use 3-30 lowercase letters, digits or _',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('settings-bio'),
                    controller: _bio,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Bio'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                  if (session.user?.handle.isNotEmpty ?? false)
                    TextButton(
                      onPressed: () => context.push(
                        '/users/${Uri.encodeComponent(session.user!.handle)}',
                      ),
                      child: const Text('View your public profile'),
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const ReadingSettings(),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('Blocked and muted', style: theme.textTheme.titleMedium),
                  const BlockedList(),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Delete account',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Permanently delete your account and all of its data.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('delete-account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _deleteAccount,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
