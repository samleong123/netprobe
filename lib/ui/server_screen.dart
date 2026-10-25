import 'package:flutter/material.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/strings.dart';
import 'sheets.dart';
import 'widgets.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({
    super.key,
    required this.controller,
    required this.onSelected,
  });
  final AppController controller;
  final VoidCallback onSelected;
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  int filter = 0;
  late final TextEditingController search;
  @override
  void initState() {
    super.initState();
    search = TextEditingController(text: widget.controller.search);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final term = c.search.toLowerCase().trim();
    final list = filter == 0
        ? c.foundServers
        : c.savedServers
              .where(
                (s) =>
                    (filter == 2 ? s.custom : !s.custom) &&
                    (term.isEmpty ||
                        '${s.sponsor} ${s.name} ${s.country}'
                            .toLowerCase()
                            .contains(term)),
              )
              .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: TextField(
            controller: search,
            onChanged: c.setSearch,
            onSubmitted: (_) => c.discover(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: S.searchServers,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        search.clear();
                        c.setSearch('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 3; i++)
                      FilterChip(
                        label: Text([S.nearby, S.favorites, S.custom][i]),
                        selected: filter == i,
                        onSelected: (_) => setState(() => filter = i),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: S.refresh,
                onPressed: c.loadingServers ? null : c.discover,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (c.loadingServers && filter == 0) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.discover,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (filter == 0 && c.discoveryError != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      c.discoveryError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.loadingServers ? null : c.discover,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(S.retry),
                  ),
                ],
                if (list.isEmpty && !(c.loadingServers && filter == 0))
                  EmptyState(
                    icon: filter == 1
                        ? Icons.star_outline_rounded
                        : Icons.dns_outlined,
                    title: [S.noServers, S.noFavorites, S.noCustom][filter],
                    body: [
                      S.noServersHelp,
                      S.noFavoritesHelp,
                      S.noCustomHelp,
                    ][filter],
                  ),
                if (list.isEmpty && c.loadingServers && filter == 0)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text(S.findingServers)),
                  ),
                for (final server in list)
                  _ServerRow(
                    server: server,
                    selected: server.id == c.selectedServer?.id,
                    favorite: c.isSaved(server),
                    enabled: !c.running,
                    onSelect: () {
                      c.select(server);
                      widget.onSelected();
                    },
                    onFavorite: () => c.toggleFavorite(server),
                    onDelete: () async {
                      final remove = await confirm(
                        context,
                        title: S.deleteServer,
                        body: S.deleteServerBody,
                        action: S.delete,
                      );
                      if (remove) c.removeCustom(server);
                    },
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: c.running
                    ? null
                    : () => showCustomServer(context, c),
                icon: const Icon(Icons.add_rounded),
                label: const Text(S.addServer),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.favorite,
    required this.enabled,
    required this.onSelect,
    required this.onFavorite,
    required this.onDelete,
  });
  final TestServer server;
  final bool selected;
  final bool favorite;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: Icon(
          selected ? Icons.check_circle_rounded : Icons.dns_outlined,
          color: selected
              ? Theme.of(context).colorScheme.onSecondaryContainer
              : null,
        ),
        title: Text(server.sponsor),
        subtitle: Text(
          server.custom
              ? [
                  if (server.downloadUrl != null) S.download,
                  if (server.uploadUrl != null) S.upload,
                ].join(' + ')
              : server.subtitle,
        ),
        onTap: enabled ? onSelect : null,
        trailing: IconButton(
          tooltip: server.custom
              ? S.deleteServer
              : favorite
              ? S.unfavorite
              : S.favorite,
          onPressed: server.custom
              ? enabled
                    ? onDelete
                    : null
              : onFavorite,
          icon: Icon(
            server.custom
                ? Icons.delete_outline_rounded
                : favorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
          ),
        ),
      ),
    ),
  );
}
