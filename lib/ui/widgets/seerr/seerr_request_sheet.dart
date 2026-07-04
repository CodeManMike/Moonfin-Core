import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';

/// Season-selection + submit sheet for requesting a title on Seerr. Reused by
/// both the Seerr discovery detail screen and the "Request on Seerr"
/// affordance on real library series detail screens (Classic and Modern).
class SeerrRequestSheet extends StatefulWidget {
  final SeerrMediaDetailViewModel vm;
  final bool isTv;
  final int numberOfSeasons;
  final Set<int> requestedSeasons;

  const SeerrRequestSheet({
    super.key,
    required this.vm,
    required this.isTv,
    required this.numberOfSeasons,
    this.requestedSeasons = const {},
  });

  @override
  State<SeerrRequestSheet> createState() => SeerrRequestSheetState();
}

class SeerrRequestSheetState extends State<SeerrRequestSheet> {
  bool _is4k = false;
  bool _allSeasons = true;
  bool _submitting = false;
  final Set<int> _selectedSeasons = {};
  bool _showAdvanced = false;

  List<SeerrServiceServerDetails>? _servers;
  int? _selectedServerId;
  int? _selectedProfileId;
  int? _selectedRootFolderId;
  bool _loadingServers = false;

  @override
  void initState() {
    super.initState();
    _applySavedPreferences();
    if (widget.vm.canRequestAdvanced) {
      _loadServers();
    }
  }

  Future<void> _loadServers() async {
    setState(() => _loadingServers = true);
    try {
      final repo = GetIt.instance<SeerrRepository>();

      if (widget.isTv) {
        final sonarrServers = await repo.getSonarrServers();
        final details = await Future.wait(
          sonarrServers.map((s) => repo.getSonarrServerDetails(s.id)),
        );
        setState(() {
          _servers = details;
          _applySavedPreferences();
        });
      } else {
        final radarrServers = await repo.getRadarrServers();
        final details = await Future.wait(
          radarrServers.map((s) => repo.getRadarrServerDetails(s.id)),
        );
        setState(() {
          _servers = details;
          _applySavedPreferences();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingServers = false);
    }
  }

  void _applySavedPreferences() {
    final vm = widget.vm;
    final savedServer = _is4k ? vm.saved4kServerId : vm.savedServerId;
    final savedProfile = _is4k ? vm.saved4kProfileId : vm.savedProfileId;
    final savedFolder = _is4k ? vm.saved4kRootFolderId : vm.savedRootFolderId;

    if (savedServer != null && savedServer.isNotEmpty) {
      _selectedServerId = int.tryParse(savedServer);
    }
    if (savedProfile != null && savedProfile.isNotEmpty) {
      _selectedProfileId = int.tryParse(savedProfile);
    }
    if (savedFolder != null && savedFolder.isNotEmpty) {
      _selectedRootFolderId = int.tryParse(savedFolder);
    }

    _applyServerDefaults();
  }

  void _applyServerDefaults() {
    final server = _activeServer;
    if (server == null) return;
    _selectedServerId ??= server.server.id;

    final isAnime = widget.vm.state.isAnime;
    final int? animeProfileId = server.server.activeAnimeProfileId;
    final String? animeDir = server.server.activeAnimeDirectory;

    if (isAnime && animeProfileId != null) {
      _selectedProfileId ??= animeProfileId;
    } else {
      _selectedProfileId ??= server.server.activeProfileId;
    }

    final String dir;
    if (isAnime && animeDir != null && animeDir.isNotEmpty) {
      dir = animeDir;
    } else {
      dir = server.server.activeDirectory;
    }

    if (_selectedRootFolderId == null && dir.isNotEmpty) {
      final match = server.rootFolders.where((f) => f.path == dir).firstOrNull;
      if (match != null) _selectedRootFolderId = match.id;
    }
  }

  int? get _effectiveServerId {
    return _selectedServerId ?? _servers?.firstOrNull?.server.id;
  }

  int? get _effectiveProfileId {
    if (_selectedProfileId != null) return _selectedProfileId;
    final server = _activeServer;
    if (server == null) return null;
    final isAnime = widget.vm.state.isAnime;
    final int? animeProfileId = server.server.activeAnimeProfileId;
    if (isAnime && animeProfileId != null) {
      return animeProfileId;
    }
    return server.server.activeProfileId;
  }

  String? get _effectiveRootFolderPath {
    final server = _activeServer;
    if (server == null) return null;

    if (_selectedRootFolderId != null) {
      return server.rootFolders
          .where((f) => f.id == _selectedRootFolderId)
          .firstOrNull
          ?.path;
    }

    final isAnime = widget.vm.state.isAnime;
    final String? animeDir = server.server.activeAnimeDirectory;
    final String dir;
    if (isAnime && animeDir != null && animeDir.isNotEmpty) {
      dir = animeDir;
    } else {
      dir = server.server.activeDirectory;
    }

    if (dir.isNotEmpty) {
      final match = server.rootFolders.where((f) => f.path == dir).firstOrNull;
      if (match != null) return match.path;
    }

    return server.rootFolders.firstOrNull?.path;
  }

  void _submit() {
    if (_submitting) {
      return;
    }

    List<int>? seasons;
    if (widget.isTv && !_allSeasons) {
      seasons = _selectedSeasons.toList()..sort();
      if (seasons.isEmpty) return;
    }

    _submitting = true;

    widget.vm.submitRequest(
      is4k: _is4k,
      seasons: seasons,
      allSeasons: widget.isTv && _allSeasons,
      profileId: _effectiveProfileId,
      rootFolder: _effectiveRootFolderPath,
      serverId: _effectiveServerId,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.vm.canRequest4k)
            SwitchListTile.adaptive(
              title: Text(
                l10n.uhd4k,
                style: const TextStyle(color: Colors.white),
              ),
              value: _is4k,
              onChanged: (v) => setState(() {
                _is4k = v;
                _selectedProfileId = null;
                _selectedRootFolderId = null;
                _applySavedPreferences();
              }),
              contentPadding: EdgeInsets.zero,
            ),
          if (widget.isTv) ...[
            const Divider(color: Colors.white12),
            _buildSeasonSelector(),
          ],
          if (widget.vm.canRequestAdvanced) ...[
            const Divider(color: Colors.white12),
            _buildAdvancedOptions(theme),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              l10n.submitRequest,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonSelector() {
    final l10n = AppLocalizations.of(context);
    final seasonCount = widget.numberOfSeasons;
    final requested = widget.requestedSeasons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          title: Text(
            l10n.allSeasons,
            style: const TextStyle(color: Colors.white),
          ),
          value: _allSeasons,
          onChanged: (v) => setState(() {
            _allSeasons = v ?? true;
            if (_allSeasons) _selectedSeasons.clear();
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (!_allSeasons && seasonCount > 0)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(seasonCount, (i) {
              final num = i + 1;
              final alreadyRequested = requested.contains(num);
              final selected = _selectedSeasons.contains(num);
              return FilterChip(
                label: Text(
                  l10n.seasonChip(num),
                  style: TextStyle(
                    fontSize: 13,
                    color: alreadyRequested
                        ? Colors.white38
                        : selected
                        ? Colors.white
                        : Colors.white70,
                  ),
                ),
                selected: selected,
                onSelected: alreadyRequested
                    ? null
                    : (v) => setState(() {
                        if (v) {
                          _selectedSeasons.add(num);
                        } else {
                          _selectedSeasons.remove(num);
                        }
                      }),
                selectedColor: const Color(0xFF6366F1),
                checkmarkColor: Colors.white,
                disabledColor: Colors.white.withValues(alpha: 0.05),
                backgroundColor: Colors.white12,
                side: BorderSide.none,
              );
            }),
          ),
      ],
    );
  }

  Widget _buildAdvancedOptions(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(
        l10n.advancedOptions,
        style: const TextStyle(color: Colors.white70),
      ),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _showAdvanced,
      onExpansionChanged: (v) => _showAdvanced = v,
      children: [
        if (_loadingServers)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_servers != null && _servers!.isNotEmpty) ...[
          _buildServerDropdown(),
          const SizedBox(height: 16),
          _buildProfileDropdown(),
          const SizedBox(height: 16),
          _buildRootFolderDropdown(),
        ] else
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.noServiceServersConfigured,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
      ],
    );
  }

  SeerrServiceServerDetails? get _activeServer {
    if (_servers == null || _servers!.isEmpty) return null;
    if (_selectedServerId == null) return _servers!.first;
    return _servers!
            .where((s) => s.server.id == _selectedServerId)
            .firstOrNull ??
        _servers!.first;
  }

  Widget _buildServerDropdown() {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        labelText: l10n.server,
        labelStyle: const TextStyle(color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: ThemeRegistry.active.borders.chipBorder,
        ),
      ),
      dropdownColor: const Color(0xFF1A1A2E),
      initialValue: _selectedServerId ?? _servers?.firstOrNull?.server.id,
      items: _servers
          ?.map(
            (s) => DropdownMenuItem(
              value: s.server.id,
              child: Text(
                '${s.server.name}${s.server.is4k ? " (4K)" : ""}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() {
        _selectedServerId = v;
        _selectedProfileId = null;
        _selectedRootFolderId = null;
        _applyServerDefaults();
      }),
    );
  }

  Widget _buildProfileDropdown() {
    final l10n = AppLocalizations.of(context);
    final profiles = _activeServer?.profiles ?? [];
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        labelText: l10n.qualityProfile,
        labelStyle: const TextStyle(color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: ThemeRegistry.active.borders.chipBorder,
        ),
      ),
      dropdownColor: const Color(0xFF1A1A2E),
      initialValue: _selectedProfileId ?? profiles.firstOrNull?.id,
      items: profiles
          .map(
            (p) => DropdownMenuItem(
              value: p.id,
              child: Text(p.name, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedProfileId = v),
    );
  }

  Widget _buildRootFolderDropdown() {
    final l10n = AppLocalizations.of(context);
    final folders = _activeServer?.rootFolders ?? [];
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
        labelText: l10n.rootFolder,
        labelStyle: const TextStyle(color: Colors.white54),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: ThemeRegistry.active.borders.chipBorder,
        ),
      ),
      dropdownColor: const Color(0xFF1A1A2E),
      initialValue: _selectedRootFolderId ?? folders.firstOrNull?.id,
      items: folders
          .map(
            (f) => DropdownMenuItem(
              value: f.id,
              child: Text(f.path, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedRootFolderId = v),
    );
  }
}
