import 'dart:convert';

import '../domain/plan.dart';
import 'page_store.dart';

/// Keeps the last plan the store reported (`settings/plan.json`), so the app
/// opens on the right plan offline and before the store answers.
class PlanCacheStore {
  PlanCacheStore(this._files);

  final PageStore _files;

  static const planFile = 'settings/plan.json';

  /// The saved plan, or null when none is saved or it cannot be read.
  Future<AppPlan?> load() async {
    try {
      final text = await _files.readText(planFile);
      if (text == null) return null;
      return AppPlan.values.asNameMap()[(jsonDecode(text) as Map)['plan']];
    } catch (_) {
      return null;
    }
  }

  Future<void> save(AppPlan plan) => _files.writeFileAtomically(planFile, utf8.encode(jsonEncode({'plan': plan.name})));
}
