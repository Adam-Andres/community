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
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(membersCol.snapshots().listen((s) {
      members.value = {for (final d in s.docs) d.id: d.data()};
    }));
    _subs.add(issuesCol.snapshots().listen((s) {
      issues.value = {for (final d in s.docs) d.id: d.data()};
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    members.value = {};
    issues.value = {};
    super.dispose();
  }

  static const _pages = [
    (title: 'Members', icon: Icons.people_outline),
    (title: 'Issues', icon: Icons.report_outlined),
    (title: 'Tasks', icon: Icons.task_alt),
    (title: 'My profile', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([members, issues]),
      builder: (context, _) => Scaffold(
        // A drawer puts the hamburger button on the left of the AppBar.
        appBar: AppBar(title: Text(_pages[_tab].title)),
        drawer: _drawer(context),
        // Non-const so pages rebuild when member/issue names change.
        body: IndexedStack(index: _tab, children: [
          MembersTab(),
          IssuesTab(),
          TasksTab(),
          const ProfileTab(),
        ]),
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    final email = auth.currentUser?.email ?? '';
    return NavigationDrawer(
      selectedIndex: _tab,
      onDestinationSelected: (i) {
        Navigator.pop(context); // close the drawer
        if (i < _pages.length) {
          setState(() => _tab = i);
        } else {
          auth.signOut();
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(memberName(myUid, email), style: Theme.of(context).textTheme.titleMedium),
            Text(email, style: const TextStyle(color: Colors.grey)),
          ]),
        ),
        for (final p in _pages)
          NavigationDrawerDestination(icon: Icon(p.icon), label: Text(p.title)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider()),
        const NavigationDrawerDestination(icon: Icon(Icons.logout), label: Text('Sign out')),
      ],
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
