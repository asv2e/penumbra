import 'package:flutter/material.dart';

import 'editor_page.dart';
import 'open_photo.dart';
import 'project_store.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${_months[t.month - 1]} ${t.day}, ${t.year}';
}

/// Asks for a project name. Returns null if cancelled or left empty.
Future<String?> promptProjectName(BuildContext context, String initial) async {
  final ctl = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Project name'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('OK')),
      ],
    ),
  );
  ctl.dispose();
  final t = name?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Home screen: every project saved in the app.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  Future<void> _new(BuildContext context) async {
    final photo = await choosePhoto(context);
    if (photo == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPage(newPhoto: photo)));
  }

  Future<void> _open(BuildContext context, ProjectMeta m) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPage(projectId: m.id)));

  Future<void> _menu(BuildContext context, String v, ProjectMeta m) async {
    final store = ProjectStore.instance;
    switch (v) {
      case 'rename':
        final n = await promptProjectName(context, m.name);
        if (n != null) await store.rename(m.id, n);
      case 'duplicate':
        await store.duplicate(m.id);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete "${m.name}"?'),
            content: const Text('The project and its edits are removed from this app. Photos you exported are not affected.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) await store.delete(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ProjectStore.instance;
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(backgroundColor: const Color(0xFF1B1B1B), title: const Text('Penumbra')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _new(context),
        icon: const Icon(Icons.add_photo_alternate),
        label: const Text('New project'),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: store.revision,
        builder: (context, _, __) {
          final projects = store.list();
          if (!store.available) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Saving projects is not available here, but you can still edit photos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          if (projects.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.photo_library_outlined, size: 72, color: Colors.white38),
                SizedBox(height: 16),
                Text('No projects yet', style: TextStyle(fontSize: 16)),
                SizedBox(height: 8),
                Text(
                  'Open a photo to start one. Edits save automatically.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: projects.length,
            itemBuilder: (context, i) {
              final m = projects[i];
              final thumb = store.thumb(m.id);
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _open(context, m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.expand(
                        child: thumb == null
                            ? const ColoredBox(color: Colors.white10, child: Icon(Icons.image_outlined, color: Colors.white24))
                            : Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        Text(_when(m.updated), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onSelected: (v) => _menu(context, v, m),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
