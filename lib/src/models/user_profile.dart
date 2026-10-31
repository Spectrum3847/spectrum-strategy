import 'user_role.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.email,
    required this.roles,
    this.canonicalUid,
    this.linkedEmails = const [],
  });

  final String uid;
  final String displayName;
  final String? email;

  final Set<UserRole> roles;

  final String? canonicalUid;

  final List<String> linkedEmails;

  bool get isLinkedSecondary =>
      canonicalUid != null && canonicalUid!.isNotEmpty;

  factory UserProfile.fromJson(String uid, Map<String, dynamic> data) {
    final Set<UserRole> roles;
    final rolesField = data['roles'];
    if (rolesField is List && rolesField.isNotEmpty) {
      final parsed = rolesField
          .whereType<String>()
          .map(UserRole.tryParse)
          .whereType<UserRole>()
          .toSet();
      roles = parsed.isEmpty ? {UserRole.viewer} : parsed;
    } else {
      final legacyRole = data['role'];
      roles = {
        legacyRole is String
            ? UserRole.fromString(legacyRole)
            : UserRole.viewer,
      };
    }
    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String?,
      roles: roles,
      canonicalUid: data['canonicalUid'] as String?,
      linkedEmails:
          (data['linkedEmails'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }

  static int byDisplayName(UserProfile a, UserProfile b) {
    final byName = a.displayName.toLowerCase().compareTo(
      b.displayName.toLowerCase(),
    );
    return byName != 0 ? byName : a.uid.compareTo(b.uid);
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'displayName': displayName,
    if (email != null) 'email': email,
    'roles': roles.map((r) => r.name).toList(),
    if (canonicalUid != null) 'canonicalUid': canonicalUid,
    if (linkedEmails.isNotEmpty) 'linkedEmails': linkedEmails,
  };
}
