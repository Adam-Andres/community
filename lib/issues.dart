import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'tasks.dart';

const issueStatuses = ['open', 'closed'];

class IssuesTab extends StatefulWidget {
  const IssuesTab({super.key});
  @override
  State<IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<IssuesTab> {
  String _filter = 'all';
  final _stream = issuesCol.orderBy('createdAt', descending: true).snapshots();

  Future<void> _create() async {
    final r = await showItemForm(context, heading: 'New issue', statuses: issueStatuses);
    if (r == null) return;
    try {
      await issuesCol.add({
        ...r,
        'ownerId': myUid,
        'ownerName': memberName(myUid),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newIssue',
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Issue'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            for (final f in const ['all', 'open', 'mine'])
              ChoiceChip(
                label: Text(f[0].toUpperCase() + f.substring(1)),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ]),
        ),
        Expanded(
          child: QueryList(
            stream: _stream,
            builder: (docs) {
              final shown = docs.where((d) {
                final x = d.data();
                return switch (_filter) {
                  'open' => x['status'] == 'open',
                  'mine' => x['ownerId'] == myUid,
                  _ => true,
                };
              }).toList();
              if (shown.isEmpty) return const EmptyState('No issues here.');
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = shown[i];
                  final x = d.data();
                  return ListTile(
                    title: Text(x['title'] ?? ''),
                    subtitle: Text(
                        'by ${memberName(x['ownerId'], x['ownerName'])} · ${fmtTime(x['createdAt'])}'),
                    trailing: StatusChip(x['status'] ?? 'open'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => IssueDetailPage(id: d.id))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class IssueDetailPage extends StatelessWidget {
  const IssueDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final ref = issuesCol.doc(id);
    return StreamBuilder<DocumentSnapshot<Json>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final x = snap.data?.data();
        final isOwner = x != null && x['ownerId'] == myUid;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Issue'),
            actions: [
              if (isOwner) ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final r = await showItemForm(context,
                        heading: 'Edit issue', statuses: issueStatuses, initial: x);
                    if (r == null) return;
                    try {
                      await ref.update({...r, 'updatedAt': FieldValue.serverTimestamp()});
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    // Tasks must always belong to an issue, so an issue that
                    // still has tasks can't be deleted (close it instead).
                    final linked = await tasksCol.where('issueId', isEqualTo: id).limit(1).get();
                    if (!context.mounted) return;
                    if (linked.docs.isNotEmpty) {
                      showInfo(context,
                          'This issue still has tasks, so it can\'t be deleted. Set it to closed instead.');
                      return;
                    }
                    if (!await confirm(context, 'Delete this issue?')) return;
                    try {
                      await ref.delete();
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ],
            ],
          ),
          body: snap.hasError
              ? EmptyState('Error: ${snap.error}')
              : !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : x == null
                      ? const EmptyState('This issue was deleted.')
                      : ListView(padding: const EdgeInsets.all(16), children: [
                          Row(children: [
                            Expanded(
                                child: Text(x['title'] ?? '',
                                    style: Theme.of(context).textTheme.headlineSmall)),
                            StatusChip(x['status'] ?? 'open'),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                              'Reported by ${memberName(x['ownerId'], x['ownerName'])} · ${fmtTime(x['createdAt'])}',
                              style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          SelectableText((x['description'] as String?)?.isNotEmpty == true
                              ? x['description']
                              : 'No description.'),
                          const Divider(height: 32),
                          Row(children: [
                            Expanded(
                                child: Text('Tasks',
                                    style: Theme.of(context).textTheme.titleMedium)),
                            TextButton.icon(
                              onPressed: () => createTask(context, issueId: id),
                              icon: const Icon(Icons.add),
                              label: const Text('Add task'),
                            ),
                          ]),
                          _IssueTasks(issueId: id),
                        ]),
        );
      },
    );
  }
}

class _IssueTasks extends StatefulWidget {
  const _IssueTasks({required this.issueId});
  final String issueId;
  @override
  State<_IssueTasks> createState() => _IssueTasksState();
}

class _IssueTasksState extends State<_IssueTasks> {
  late final _stream = tasksCol.where('issueId', isEqualTo: widget.issueId).snapshots();

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Json>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Text('Error: ${snap.error}');
          if (!snap.hasData) return const LinearProgressIndicator();
          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final ta = a.data()['createdAt'], tb = b.data()['createdAt'];
              if (ta is! Timestamp || tb is! Timestamp) return 0;
              return ta.compareTo(tb);
            });
          if (docs.isEmpty) {
            return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No tasks yet.', style: TextStyle(color: Colors.grey)));
          }
          return Column(children: [for (final d in docs) TaskTile(d, showIssue: false)]);
        },
      );
}
