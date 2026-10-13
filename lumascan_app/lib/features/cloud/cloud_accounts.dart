import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/cloud/google_drive_provider.dart';
import '../../data/cloud/icloud_drive_provider.dart';
import '../../data/cloud/onedrive_provider.dart';
import '../../domain/cloud_storage.dart';

/// Every cloud storage service in Settings > Accounts, in display order.
/// Tests override it with fakes.
final cloudProvidersProvider = Provider<List<CloudStorageProvider>>(
  (ref) => [GoogleDriveProvider(), OneDriveProvider(), ICloudDriveProvider()],
);

/// Where downloaded files wait while they are imported. They are deleted
/// once the import finishes or fails.
final cloudDownloadDirProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'cloud_imports'));
    await dir.create(recursive: true);
    return dir;
  },
);

/// The connected account of each provider. A provider that is missing has
/// no account connected on this phone.
final cloudAccountsProvider = AsyncNotifierProvider<CloudAccountsController, Map<CloudProviderId, CloudAccount>>(
  CloudAccountsController.new,
);

class CloudAccountsController extends AsyncNotifier<Map<CloudProviderId, CloudAccount>> {
  @override
  Future<Map<CloudProviderId, CloudAccount>> build() async {
    final accounts = <CloudProviderId, CloudAccount>{};
    for (final provider in ref.read(cloudProvidersProvider)) {
      if (provider.usesSystemPicker || provider.availability != CloudAvailability.ready) continue;
      try {
        final account = await provider.restore();
        if (account != null) accounts[provider.id] = account;
      } on Object {
        // A saved sign-in that cannot be read counts as not connected.
      }
    }
    return accounts;
  }

  /// Signs in to [provider]. Returns null when the user backed out.
  Future<CloudAccount?> connect(CloudStorageProvider provider) async {
    final CloudAccount account;
    try {
      account = await provider.connect();
    } on CloudCancelled {
      return null;
    }
    final current = await future;
    state = AsyncData({...current, provider.id: account});
    return account;
  }

  /// Signs out of [provider] on this phone. Imported documents stay.
  Future<void> disconnect(CloudStorageProvider provider) async {
    await provider.disconnect();
    signedOut(provider.id);
  }

  /// Drops the account after the service refused its sign-in.
  void signedOut(CloudProviderId id) {
    final current = state.value;
    if (current == null || !current.containsKey(id)) return;
    state = AsyncData({...current}..remove(id));
  }
}
