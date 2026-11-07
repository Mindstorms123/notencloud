/// Configuration and credentials for connecting to an orchestra's Nextcloud instance
class NextcloudAccount {
  final String serverUrl;
  final String username;
  final String password; // App password or user password
  final String rootFolder; // Path inside Nextcloud, e.g. "/Notenarchiv" or "/"
  final bool isValidated;
  final String? serverVersion;

  const NextcloudAccount({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.rootFolder = '/Notenarchiv',
    this.isValidated = false,
    this.serverVersion,
  });

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;

  String get cleanServerUrl {
    var url = serverUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  String get webDavBaseUrl {
    final clean = cleanServerUrl;
    return '$clean/remote.php/dav/files/$username';
  }

  String get cleanRootFolder {
    var folder = rootFolder.trim();
    if (!folder.startsWith('/')) {
      folder = '/$folder';
    }
    if (folder.length > 1 && folder.endsWith('/')) {
      folder = folder.substring(0, folder.length - 1);
    }
    return folder;
  }

  NextcloudAccount copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? rootFolder,
    bool? isValidated,
    String? serverVersion,
  }) {
    return NextcloudAccount(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      rootFolder: rootFolder ?? this.rootFolder,
      isValidated: isValidated ?? this.isValidated,
      serverVersion: serverVersion ?? this.serverVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'rootFolder': rootFolder,
        'isValidated': isValidated,
        'serverVersion': serverVersion,
      };

  factory NextcloudAccount.fromJson(Map<String, dynamic> json) =>
      NextcloudAccount(
        serverUrl: json['serverUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        rootFolder: json['rootFolder'] as String? ?? '/Notenarchiv',
        isValidated: json['isValidated'] as bool? ?? false,
        serverVersion: json['serverVersion'] as String?,
      );
}
