import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../subjects/domain/ad_subject.dart";
import "../../domain/user_search_result.dart";
import "../providers/market_providers.dart";

/// Search over subjects and users (CLAUDE.md section 12: "Search must
/// support users and subjects, and eventually hashtags").
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<AdSubject> _subjects = const <AdSubject>[];
  List<UserSearchResult> _users = const <UserSearchResult>[];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _subjects = const <AdSubject>[];
        _users = const <UserSearchResult>[];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final repository = ref.read(marketRepositoryProvider);
      final results = await Future.wait(<Future<dynamic>>[
        repository.searchSubjects(trimmed),
        repository.searchUsers(trimmed),
      ]);
      if (mounted) {
        setState(() {
          _subjects = results[0] as List<AdSubject>;
          _users = results[1] as List<UserSearchResult>;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Search subjects or people",
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                if (_subjects.isNotEmpty) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text("SUBJECTS", style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ..._subjects.map(
                    (AdSubject subject) => ListTile(
                      title: Text("${subject.displayName.toUpperCase()}™"),
                      subtitle: Text("${subject.adsCount} Ads"),
                      onTap: () => context.goTo(RoutePaths.subjectOf(subject.id)),
                    ),
                  ),
                ],
                if (_users.isNotEmpty) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text("PEOPLE", style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ..._users.map(
                    (UserSearchResult user) => ListTile(
                      title: Text("@${user.username}"),
                      subtitle: user.displayName != null ? Text(user.displayName!) : null,
                      onTap: () => context.goTo(RoutePaths.userProfileOf(user.username)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
