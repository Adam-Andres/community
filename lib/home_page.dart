import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'issues.dart';
import 'tasks.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = membersCol.snapshots().listen((s) {
      members.value = {for (final d in s.docs) d.id: d.data()};
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    members.value = {};
    super.dispose();
  }

  static const _titles = ['Members', 'Issues', 'Tasks', 'My profile'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: members,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(title: Text(_titles[_tab])),
        // Non-const so tabs rebuild when member names change.
        body: IndexedStack(index: _tab, children: [
          MembersTab(),
          IssuesTab(),
          TasksTab(),
          const ProfileTab(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people_outline), label: 'Members'),
            NavigationDestination(icon: Icon(Icons.report_outlined), label: 'Issues'),
            NavigationDestination(icon: Icon(Icons.task_alt), label: 'Tasks'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class MembersTab extends StatelessWidget {
  const MembersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final list = members.value.entries.toList()
      ..sort((a, b) => memberName(a.key).toLowerCase().compareTo(memberName(b.key).toLowerCase()));
    if (list.isEmpty) return const EmptyState('No members yet.');
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final id = list[i].key;
        final m = list[i].value;
        final name = memberName(id);
        final phone = (m['phone'] as String?) ?? '';
        return ListTile(
          leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
          title: Text(id == myUid ? '$name (you)' : name),
          subtitle: SelectableText([m['email'] ?? '', if (phone.isNotEmpty) phone].join('  ·  ')),
        );
      },
    );
  }
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    membersCol.doc(myUid).get().then((d) {
      if (!mounted) return;
      _name.text = d.data()?['name'] ?? '';
      _phone.text = d.data()?['phone'] ?? '';
      setState(() => _loaded = true);
    }, onError: (e) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // Only the signed-in member can write members/{their uid} (see firestore.rules).
      await membersCol.doc(myUid).set({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': auth.currentUser!.email,
      }, SetOptions(merge: true));
      if (mounted) showInfo(context, 'Profile saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                initialValue: auth.currentUser!.email,
                enabled: false,
                decoration: const InputDecoration(
                    labelText: 'Email (login)', helperText: 'Your login email is unique and cannot be edited here.'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save profile')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
