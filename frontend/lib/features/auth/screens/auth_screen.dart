import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';

enum _AuthMode { login, register }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  _AuthMode _mode = _AuthMode.login;

  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  String _gender = 'M';
  DateTime? _birthdate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_mode == _AuthMode.login) {
      await ref.read(authControllerProvider.notifier).login(int.parse(_idController.text.trim()));
      return;
    }

    if (_birthdate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a birthdate')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = await ref.read(authControllerProvider.notifier).registerOnly(
            name: _nameController.text.trim(),
            surname: _surnameController.text.trim(),
            gender: _gender,
            birthdate: _birthdate!,
          );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NewUserIdDialog(user: user),
      );

      await ref.read(authControllerProvider.notifier).completeLogin(user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 110),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    ref.listen(authControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final message = next.error is Exception ? next.error.toString() : 'Something went wrong';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 560),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(flex: 5, child: _BrandPanel()),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                    child: _buildForm(authState),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AsyncValue authState) {
    final isLoading = authState.isLoading || _isSubmitting;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _mode == _AuthMode.login ? 'Welcome back' : 'Create your account',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _mode == _AuthMode.login
                  ? 'Enter your user ID to continue.'
                  : 'A few details to set up your profile.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            if (_mode == _AuthMode.login) ..._loginFields() else ..._registerFields(),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_mode == _AuthMode.login ? 'Log in' : 'Create account'),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: isLoading
                    ? null
                    : () => setState(() {
                          _mode = _mode == _AuthMode.login ? _AuthMode.register : _AuthMode.login;
                        }),
                child: Text(
                  _mode == _AuthMode.login
                      ? "Don't have an account? Register"
                      : 'Already have an account? Log in',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _loginFields() {
    return [
      TextFormField(
        controller: _idController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'User ID'),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your user ID' : null,
      ),
    ];
  }

  List<Widget> _registerFields() {
    return [
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'First name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: _surnameController,
              decoration: const InputDecoration(labelText: 'Surname'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: _genderSelector()),
          const SizedBox(width: 16),
          Expanded(child: _birthdateField()),
        ],
      ),
    ];
  }

  Widget _genderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gender', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'M', label: Text('Male')),
            ButtonSegment(value: 'F', label: Text('Female')),
          ],
          selected: {_gender},
          onSelectionChanged: (s) => setState(() => _gender = s.first),
        ),
      ],
    );
  }

  Widget _birthdateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Birthdate', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _pickBirthdate,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.centerLeft,
          ),
          child: Text(
            _birthdate == null
                ? 'Select date'
                : '${_birthdate!.year}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
          ),
        ),
      ],
    );
  }
}

class _NewUserIdDialog extends StatefulWidget {
  const _NewUserIdDialog({required this.user});

  final AppUser user;

  @override
  State<_NewUserIdDialog> createState() => _NewUserIdDialogState();
}

class _NewUserIdDialogState extends State<_NewUserIdDialog> {
  bool _copied = false;

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: widget.user.id.toString()));
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 40),
              const SizedBox(height: 16),
              Text(
                'Account created, ${widget.user.name}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                "This ID is the only way to log back in. Copy it and keep it somewhere safe.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${widget.user.id}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _copyId,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? 'Copied' : 'Copy ID'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continue to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.black,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.front_hand_outlined, color: Colors.white, size: 22),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Prosthetic Arm\nControl System',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'EMG gesture recognition, live calibration and real-time servo control for a 5-motor prosthetic hand.',
                style: TextStyle(color: Color(0xFFB5B5B5), fontSize: 14, height: 1.5),
              ),
            ],
          ),
          const Text(
            'Biomekatronik',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
