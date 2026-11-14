enum AppRole { admin, manager, supervisor }

class AppUser {
  const AppUser({
    required this.uid,
    required this.username,
    required this.role,
    required this.isActive,
    this.email = '',
    this.assignedContractIds = const [],
    this.assignedCustomerIds = const [],
    this.assignedAdSpaceIds = const [],
    this.permissions = const {},
    this.notificationPreferences = const {},
  });

  final String uid;
  final String username;
  final String email;
  final AppRole role;
  final bool isActive;
  final List<String> assignedContractIds;
  final List<String> assignedCustomerIds;
  final List<String> assignedAdSpaceIds;
  final Map<String, bool> permissions;
  final Map<String, bool> notificationPreferences;

  bool canAccess(String module) =>
      role != AppRole.supervisor || permissions[module] == true;

  factory AppUser.fromJson(String uid, Map<String, dynamic> json) => AppUser(
    uid: uid,
    username: json['username'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: AppRole.values.firstWhere(
      (role) => role.name == json['role'],
      orElse: () => AppRole.supervisor,
    ),
    isActive: json['isActive'] as bool? ?? false,
    assignedContractIds: (json['assignedContractIds'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList(),
    assignedCustomerIds: (json['assignedCustomerIds'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList(),
    assignedAdSpaceIds: (json['assignedAdSpaceIds'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList(),
    permissions: Map<String, bool>.from(
      (json['permissions'] as Map<dynamic, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
    ),
    notificationPreferences: Map<String, bool>.from(
      (json['notificationPreferences'] as Map<dynamic, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
    ),
  );
}
