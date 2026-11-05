import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'issues.dart';

const taskStatuses = ['todo', 'in progress', 'done'];

/// Opens the task form and creates the task. Every task must belong to an issue;
/// pass [issueId] to preselect it (e.g. when adding a task from an issue page).
Future<void> createTask(BuildContext context, {String? issueId}) async {
  if (issues.value.isEmpty) {
    showInfo(context, 'Create an issue first. Every task belongs to an issue.');
    return;
  }
  final r = await showItemForm(context,
      heading: 'New task',
      statuses: taskStatuses,
      withAssignee: true,
      withIssue: true,
      initial: issueId == null ? null : {'issueId': issueId});
  if (r == null) return;
  try {
    await tasksCol.add({
      ...r,
      'ownerId': myUid,
      'ownerName': memberName(myUid),
      'assigneeName': memberName(r['assigneeId']),
      'issueTitle': issueTitle(r['issueId']),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// List tile used on the Tasks page and on an issue's page.
class TaskTile extends StatelessWidget {
  const TaskTile(this.doc, {super.key, this.showIssue = true});
  final QueryDocumentSnapshot<Json> doc;
  final bool showIssue;

  @override
  Widget build(BuildContext context) {
    final x = doc.data();
    final people =
        '→ ${memberName(x['assigneeId'], x['assigneeName'])} · by ${memberName(x['ownerId'], x['ownerName'])}';
    return ListTile(
      title: Text(x['title'] ?? ''),
      subtitle: Text(showIssue ? 'Issue: ${issueTitle(x['issueId'], x['issueTitle'])}\n$people' : people),
      isThreeLine: showIssue,
      trailing: StatusChip(x['status'] ?? 'todo'),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => TaskDetailPage(id: doc.id))),
    );
  }
}

class TasksTab extends StatefulWidget {
  const TasksTab({super.key});
  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  String _filter = 'all';
  final _stream = tasksCol.orderBy('createdAt', descending: true).snapshots();

  static const _filters = {
    'all': 'All',
    'assigned': 'Assigned to me',
    'created': 'Created by me',
    'open': 'Not done',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newTask',
        onPressed: () => createTask(context),
        icon: const Icon(Icons.add),
        label: const Text('Task'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final f in _filters.entries)
              ChoiceChip(
                label: Text(f.value),
                selected: _filter == f.key,
                onSelected: (_) => setState(() => _filter = f.key),
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
                  'assigned' => x['assigneeId'] == myUid,
                  'created' => x['ownerId'] == myUid,
                  'open' => x['status'] != 'done',
                  _ => true,
                };
              }).toList();
              if (shown.isEmpty) return const EmptyState('No tasks here.');
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => TaskTile(shown[i]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.id});
  final String id;
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late final _ref = tasksCol.doc(widget.id);
  late final _taskStream = _ref.snapshots();
  late final _commentStream =
      commentsCol(widget.id).orderBy('createdAt').snapshots();
  final _comment = TextEditingController();
  bool _sending = false;

  Future<void> _addComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await commentsCol(widget.id).add({
        'text': text,
        'ownerId': myUid,
        'ownerName': memberName(myUid),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _comment.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editComment(DocumentReference<Json> ref, String current) async {
    final c = TextEditingController(text: current);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: c, minLines: 2, maxLines: 6, autofocus: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (r == null || r.isEmpty) return;
    try {
      await ref.update({'text': r, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Json>>(
      stream: _taskStream,
      builder: (context, snap) {
        final x = snap.data?.data();
        final isOwner = x != null && x['ownerId'] == myUid;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Task'),
            actions: [
              if (isOwner) ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final r = await showItemForm(context,
                        heading: 'Edit task',
                        statuses: taskStatuses,
                        initial: x,
                        withAssignee: true,
                        withIssue: true);
                    if (r == null) return;
                    try {
                      await _ref.update({
                        ...r,
                        'assigneeName': memberName(r['assigneeId']),
                        'issueTitle': issueTitle(r['issueId']),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirm(context, 'Delete this task?')) return;
                    try {
                      await _ref.delete();
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
                      ? const EmptyState('This task was deleted.')
                      : Column(children: [
                          Expanded(child: _body(context, x)),
                          _commentBox(),
                        ]),
        );
      },
    );
  }

  Widget _body(BuildContext context, Json x) {
    final grey = const TextStyle(color: Colors.grey);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text(x['title'] ?? '', style: Theme.of(context).textTheme.headlineSmall)),
        StatusChip(x['status'] ?? 'todo'),
      ]),
      const SizedBox(height: 4),
      InkWell(
        onTap: issues.value.containsKey(x['issueId'])
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => IssueDetailPage(id: x['issueId'])))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            const Icon(Icons.report_outlined, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Issue: ${issueTitle(x['issueId'], x['issueTitle'])}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
        ),
      ),
      Text('Assigned to ${memberName(x['assigneeId'], x['assigneeName'])}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      Text('Created by ${memberName(x['ownerId'], x['ownerName'])} · ${fmtTime(x['createdAt'])}',
          style: grey),
      const SizedBox(height: 16),
      SelectableText(
          (x['description'] as String?)?.isNotEmpty == true ? x['description'] : 'No description.'),
      const Divider(height: 32),
      Text('Comments', style: Theme.of(context).textTheme.titleMedium),
      StreamBuilder<QuerySnapshot<Json>>(
        stream: _commentStream,
        builder: (context, cs) {
          if (cs.hasError) return Text('Error: ${cs.error}');
          if (!cs.hasData) return const LinearProgressIndicator();
          final docs = cs.data!.docs;
          if (docs.isEmpty) {
            return Padding(padding: const EdgeInsets.only(top: 8), child: Text('No comments yet.', style: grey));
          }
          return Column(children: [
            for (final d in docs) _commentTile(d),
          ]);
        },
      ),
    ]);
  }

  Widget _commentTile(QueryDocumentSnapshot<Json> d) {
    final c = d.data();
    final mine = c['ownerId'] == myUid;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(memberName(c['ownerId'], c['ownerName']),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(c['text'] ?? ''),
        Text(fmtTime(c['createdAt']) + (c['updatedAt'] != null ? ' (edited)' : ''),
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
      trailing: mine
          ? PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  await _editComment(d.reference, c['text'] ?? '');
                } else if (await confirm(context, 'Delete this comment?')) {
                  try {
                    await d.reference.delete();
                  } catch (e) {
                    if (mounted) showError(context, e);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          : null,
    );
  }

  Widget _commentBox() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _comment,
                decoration: const InputDecoration(hintText: 'Add a comment…', border: OutlineInputBorder()),
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _addComment(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _addComment,
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
      );
}
