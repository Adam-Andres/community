import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

typedef Json = Map<String, dynamic>;

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

String get myUid => auth.currentUser!.uid;

CollectionReference<Json> get membersCol => db.collection('members');
CollectionReference<Json> get issuesCol => db.collection('issues');
CollectionReference<Json> get tasksCol => db.collection('tasks');
CollectionReference<Json> commentsCol(String taskId) =>
    tasksCol.doc(taskId).collection('comments');

/// Live map of uid -> member data, kept fresh by HomePage.
final members = ValueNotifier<Map<String, Json>>({});

String memberName(String? uid, [String? fallback]) {
  final m = members.value[uid];
  final n = (m?['name'] as String?)?.trim();
  if (n != null && n.isNotEmpty) return n;
  return fallback ?? 'Unknown';
}

String fmtTime(dynamic ts) {
  if (ts is! Timestamp) return 'just now';
  final d = ts.toDate();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

void showError(BuildContext context, Object e) {
  final msg = e is FirebaseException ? (e.message ?? e.code) : e.toString();
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
}

void showInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
      ],
    ),
  );
  return r ?? false;
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'open' || 'todo' => Colors.orange,
      'in progress' => Colors.blue,
      _ => Colors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ),
      );
}

/// Shared StreamBuilder wrapper that handles loading & error states.
class QueryList extends StatelessWidget {
  const QueryList({super.key, required this.stream, required this.builder});
  final Stream<QuerySnapshot<Json>> stream;
  final Widget Function(List<QueryDocumentSnapshot<Json>> docs) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Json>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return EmptyState('Error: ${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return builder(snap.data!.docs);
        },
      );
}

/// Dialog for creating/editing an issue or task.
/// Returns {title, description, status, assigneeId?} or null if cancelled.
Future<Json?> showItemForm(
  BuildContext context, {
  required String heading,
  required List<String> statuses,
  Json? initial,
  bool withAssignee = false,
}) {
  final title = TextEditingController(text: initial?['title'] ?? '');
  final desc = TextEditingController(text: initial?['description'] ?? '');
  String status = initial?['status'] ?? statuses.first;
  String? assignee = initial?['assigneeId'];
  final formKey = GlobalKey<FormState>();

  return showDialog<Json>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final memberEntries = members.value.entries.toList()
          ..sort((a, b) => memberName(a.key).toLowerCase().compareTo(memberName(b.key).toLowerCase()));
        return AlertDialog(
          title: Text(heading),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: desc,
                    decoration: const InputDecoration(labelText: 'Description'),
                    minLines: 3,
                    maxLines: 8,
                  ),
                  const SizedBox(height: 8),
                  if (withAssignee)
                    DropdownButtonFormField<String>(
                      initialValue: members.value.containsKey(assignee) ? assignee : null,
                      decoration: const InputDecoration(labelText: 'Assigned to'),
                      items: [
                        for (final e in memberEntries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(memberName(e.key) + (e.key == myUid ? ' (me)' : '')),
                          ),
                      ],
                      onChanged: (v) => setState(() => assignee = v),
                      validator: (v) => v == null ? 'Pick a member' : null,
                    ),
                  if (withAssignee) const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [for (final s in statuses) DropdownMenuItem(value: s, child: Text(s))],
                    onChanged: (v) => setState(() => status = v ?? status),
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(c, {
                  'title': title.text.trim(),
                  'description': desc.text.trim(),
                  'status': status,
                  if (withAssignee) 'assigneeId': assignee,
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
