import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/data/ocr_search.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';

class OcrSearchDelegate extends SearchDelegate<OcrSearchResult?> {
  OcrSearchDelegate()
      : super(
          searchFieldLabel: t.home.search.hint,
        );

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResults(query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) {
      return Center(
        child: Text(
          t.home.search.hint,
          style: TextStyle(color: ColorScheme.of(context).onSurfaceVariant),
        ),
      );
    }

    return _SearchResults(query: query);
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OcrSearchResult>>(
      future: OcrSearchService.search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return Center(
            child: Text(
              t.home.search.noResults,
              style: TextStyle(
                color: ColorScheme.of(context).onSurfaceVariant,
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final result = results[index];
            return ListTile(
              title: Text(result.noteName),
              subtitle: Text(
                result.context,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ColorScheme.of(context).onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              leading: const Icon(Icons.description_outlined),
              onTap: () {
                context.push(RoutePaths.editFilePath(result.notePath));
              },
            );
          },
        );
      },
    );
  }
}
