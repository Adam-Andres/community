import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'common.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _register = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_register) {
        final cred = await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
        final user = cred.user!;
        await membersCol.doc(user.uid).set({
          'name': _name.text.trim(),
          'email': user.email,
          'phone': _phone.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) showError(context, _authMessage(e));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(FirebaseAuthException e) => switch (e.code) {
        'email-already-in-use' => 'An account with this email already exists.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Incorrect email or password.',
        'weak-password' => 'Password must be at least 6 characters.',
        'invalid-email' => 'That email address is not valid.',
        _ => e.message ?? e.code,
      };

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showInfo(context, 'Enter your email above first.');
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) showInfo(context, 'Password reset email sent to $email.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.groups, size: 64),
                  const SizedBox(height: 8),
                  Text('Community',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      autofillHints: const [AutofillHints.name],
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Phone (optional)'),
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Create account' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register
                        ? 'Already a member? Sign in'
                        : 'New member? Create an account'),
                  ),
                  if (!_register)
                    TextButton(onPressed: _resetPassword, child: const Text('Forgot password?')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
