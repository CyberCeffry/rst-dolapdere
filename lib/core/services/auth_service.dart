import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/app_user.dart';
import '../../models/contract_model.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  static const workspaceId = 'rst_dolapdere';
  static const _usernameDomain = 'login.rst-dolapdere.invalid';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authChanges => _auth.authStateChanges();

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('workspaces').doc(workspaceId).collection('users');

  Future<AppUser?> loadProfile(String uid) async {
    final snapshot = await _users.doc(uid).get();
    if (!snapshot.exists) return null;
    return AppUser.fromJson(uid, snapshot.data()!);
  }

  Stream<AppUser?> watchProfile(String uid) => _users
      .doc(uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? AppUser.fromJson(uid, snapshot.data()!) : null,
      );

  Stream<List<AppUser>> watchUsers() => _users.snapshots().map(
    (snapshot) =>
        snapshot.docs
            .map((document) => AppUser.fromJson(document.id, document.data()))
            .toList()
          ..sort((a, b) => a.username.compareTo(b.username)),
  );

  Stream<List<Map<String, dynamic>>> watchContractRequests() => _firestore
      .collection('workspaces')
      .doc(workspaceId)
      .collection('contractRequests')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => {'id': document.id, ...document.data()})
            .toList(),
      );

  Stream<List<Map<String, dynamic>>> watchInbox(String uid) => _users
      .doc(uid)
      .collection('inbox')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => {'id': document.id, ...document.data()})
            .toList(),
      );

  Future<void> markInboxRead(String uid, String messageId) =>
      _users.doc(uid).collection('inbox').doc(messageId).update({'read': true});

  Future<AppUser> signIn({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) {
      throw ArgumentError('Kullanıcı adı ve şifre zorunludur.');
    }
    final credential = await _auth.signInWithEmailAndPassword(
      email: '$normalized@$_usernameDomain',
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Oturum açılamadı.');
    final profile = await loadProfile(user.uid);
    if (profile == null || !profile.isActive) {
      await _auth.signOut();
      throw StateError('Kullanıcı hesabı etkin değil. Yöneticiyle görüşün.');
    }
    return profile;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw StateError('Oturum bulunamadı.');
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> createUser({
    required String username,
    required String initialPassword,
    required AppRole role,
    required bool isActive,
    required Map<String, bool> permissions,
    String email = '',
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(normalizedUsername)) {
      throw ArgumentError('Kullanıcı adı 3-32 karakter olmalı.');
    }
    if (initialPassword.length < 10) {
      throw ArgumentError('Şifre en az 10 karakter olmalı.');
    }
    final indexReference = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('usernameIndex')
        .doc(normalizedUsername);
    if ((await indexReference.get()).exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'already-exists',
        message: 'Bu kullanıcı adı zaten kullanımda.',
      );
    }
    final authApp = await Firebase.initializeApp(
      name: 'user-provision-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final provisioningAuth = FirebaseAuth.instanceFor(app: authApp);
    String? createdUid;
    try {
      final credential = await provisioningAuth.createUserWithEmailAndPassword(
        email: '$normalizedUsername@$_usernameDomain',
        password: initialPassword,
      );
      final uid = credential.user!.uid;
      createdUid = uid;
      final userReference = _users.doc(uid);
      final batch = _firestore.batch();
      batch.set(indexReference, {'uid': uid});
      batch.set(userReference, {
        'username': normalizedUsername,
        'authEmail': '$normalizedUsername@$_usernameDomain',
        'email': email.trim(),
        'role': role.name,
        'isActive': isActive,
        'permissions': permissions,
        'notificationPreferences': {'inApp': true, 'push': true},
        'assignedContractIds': <String>[],
        'assignedCustomerIds': <String>[],
        'assignedAdSpaceIds': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (error) {
      if (createdUid != null) {
        await provisioningAuth.currentUser?.delete().catchError((_) {});
      }
      if (error is FirebaseException && error.code == 'permission-denied') {
        final racedIndex = await indexReference.get();
        if (racedIndex.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'already-exists',
            message: 'Bu kullanıcı adı başka bir yönetici tarafından alındı.',
          );
        }
      }
      rethrow;
    } finally {
      await provisioningAuth.signOut();
      await authApp.delete();
    }
  }

  Future<void> updateUser({
    required String uid,
    required AppRole role,
    required bool isActive,
    required Map<String, bool> permissions,
    String? email,
  }) async {
    final actorUid = _auth.currentUser?.uid;
    if (actorUid == null) throw StateError('Oturum bulunamadı.');
    final actorSnapshot = await _users.doc(actorUid).get();
    final targetReference = _users.doc(uid);
    final targetSnapshot = await targetReference.get();
    if (!targetSnapshot.exists) throw StateError('Kullanıcı bulunamadı.');
    final actorRole = actorSnapshot.data()?['role'];
    final targetRole = targetSnapshot.data()?['role'];
    if (actorRole != AppRole.admin.name && actorRole != AppRole.manager.name) {
      throw StateError('Kullanıcı yönetme yetkiniz yok.');
    }
    if (actorRole == AppRole.manager.name &&
        (targetRole == AppRole.admin.name || role == AppRole.admin)) {
      throw StateError(
        'Admin hesaplarını yalnız sistem yöneticisi düzenleyebilir.',
      );
    }
    await targetReference.update({
      'role': role.name,
      'isActive': isActive,
      'permissions': permissions,
      if (email != null) 'email': email.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUser(String uid) async {
    final user = await loadProfile(uid);
    if (user == null) throw StateError('Kullanıcı bulunamadı.');
    await updateUser(
      uid: uid,
      role: user.role,
      isActive: false,
      permissions: user.permissions,
      email: user.email,
    );
  }

  Future<void> updateOwnNotificationPreferences(
    Map<String, bool> preferences,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Oturum bulunamadı.');
    await _users.doc(uid).update({
      'notificationPreferences': preferences,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> assignContract({
    required String contractId,
    required String responsibleUserId,
  }) async {
    final actorUid = _auth.currentUser?.uid;
    if (actorUid == null) throw StateError('Oturum bulunamadı.');
    final contractReference = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contracts')
        .doc(contractId);
    final actorReference = _users.doc(actorUid);
    final targetReference = _users.doc(responsibleUserId);
    final initialContractSnapshot = await contractReference.get();
    final initialOldResponsibleId =
        initialContractSnapshot.data()?['responsibleUserId'] as String?;
    var previousContracts = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (initialOldResponsibleId != null &&
        initialOldResponsibleId.isNotEmpty &&
        initialOldResponsibleId != responsibleUserId) {
      final previousContractsQuery = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contracts')
          .where('responsibleUserId', isEqualTo: initialOldResponsibleId)
          .get();
      previousContracts = previousContractsQuery.docs;
    }
    await _firestore.runTransaction((transaction) async {
      final contractSnapshot = await transaction.get(contractReference);
      final actorSnapshot = await transaction.get(actorReference);
      final targetSnapshot = responsibleUserId == actorUid
          ? actorSnapshot
          : await transaction.get(targetReference);
      if (!contractSnapshot.exists || !targetSnapshot.exists) {
        throw StateError('Sözleşme veya kullanıcı bulunamadı.');
      }
      final contract = contractSnapshot.data()!;
      final actor = actorSnapshot.data()!;
      final target = targetSnapshot.data()!;
      final role = actor['role'] as String?;
      final oldResponsibleId = contract['responsibleUserId'] as String?;
      if (oldResponsibleId != initialOldResponsibleId) {
        throw StateError('Sorumlu aynı anda değiştirildi. Yeniden deneyin.');
      }
      if (target['isActive'] != true) {
        throw StateError('Pasif kullanıcı sorumlu atanamaz.');
      }
      if (role == AppRole.supervisor.name) {
        if (responsibleUserId != actorUid) {
          throw StateError('Sorumlu yalnızca kendisini atayabilir.');
        }
        if (oldResponsibleId != null &&
            oldResponsibleId.isNotEmpty &&
            oldResponsibleId != actorUid) {
          throw StateError(
            'Başka bir sorumluya atanmış sözleşmeyi devralamazsınız.',
          );
        }
      } else if (role != AppRole.admin.name && role != AppRole.manager.name) {
        throw StateError('Sorumlu atama yetkiniz yok.');
      }

      DocumentSnapshot<Map<String, dynamic>>? previousUserSnapshot;
      if (oldResponsibleId != null &&
          oldResponsibleId.isNotEmpty &&
          oldResponsibleId != responsibleUserId) {
        final previousReference = _users.doc(oldResponsibleId);
        previousUserSnapshot = await transaction.get(previousReference);
      }

      final now = DateTime.now();
      transaction.update(contractReference, {
        'responsibleUserId': responsibleUserId,
        'responsibleUsername': target['username'] ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          {
            'action': 'assigned',
            'occurredAt': now.toIso8601String(),
            'actorUid': actorUid,
            'actorUsername': actor['username'] ?? '',
            'targetUserId': responsibleUserId,
            'targetUsername': target['username'] ?? '',
          },
        ]),
      });
      transaction.update(targetReference, {
        'assignedContractIds': FieldValue.arrayUnion([contractId]),
        'assignedCustomerIds': FieldValue.arrayUnion([
          contract['customerId'] as String,
        ]),
        'assignedAdSpaceIds': FieldValue.arrayUnion([
          contract['adSpaceId'] as String,
        ]),
        if (role == AppRole.supervisor.name) ...{
          'lastAssignedContractId': contractId,
          'lastAssignedCustomerId': contract['customerId'],
          'lastAssignedAdSpaceId': contract['adSpaceId'],
        },
      });
      if (previousUserSnapshot?.exists == true) {
        final previousProfile = previousUserSnapshot!.data()!;
        final remaining = previousContracts.where(
          (document) => document.id != contractId,
        );
        final hasCustomer = remaining.any(
          (document) => document.data()['customerId'] == contract['customerId'],
        );
        final hasAdSpace = remaining.any(
          (document) => document.data()['adSpaceId'] == contract['adSpaceId'],
        );
        transaction.update(_users.doc(oldResponsibleId), {
          'assignedContractIds': FieldValue.arrayRemove([contractId]),
          if (!hasCustomer)
            'assignedCustomerIds': FieldValue.arrayRemove([
              contract['customerId'],
            ]),
          if (!hasAdSpace)
            'assignedAdSpaceIds': FieldValue.arrayRemove([
              contract['adSpaceId'],
            ]),
          if (previousProfile['role'] == AppRole.supervisor.name)
            'lastAssignedContractId': FieldValue.delete(),
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> listAvailableContracts() async {
    final blank = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contracts')
        .where('responsibleUserId', isEqualTo: '')
        .get();
    final legacyNull = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contracts')
        .where('responsibleUserId', isNull: true)
        .get();
    final byId = <String, Map<String, dynamic>>{
      for (final document in [...blank.docs, ...legacyNull.docs])
        document.id: {...document.data(), 'id': document.id},
    };
    return byId.values.toList();
  }

  Future<String> submitContractChange({
    required String operation,
    required ContractModel contract,
    String? contractId,
  }) async {
    final result = await _functions.httpsCallable('submitContractChange').call({
      'operation': operation,
      'contractId': contractId,
      'contract': contract.toJson(),
    });
    return (result.data as Map)['requestId'] as String;
  }

  Future<void> reviewContractRequest({
    required String requestId,
    required bool approve,
    String note = '',
  }) => _call('reviewContractRequest', {
    'requestId': requestId,
    'approve': approve,
    'note': note,
  });

  Future<void> setContractActive({
    required String contractId,
    required bool isActive,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Oturum bulunamadı.');
    final contractReference = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contracts')
        .doc(contractId);
    final actorSnapshot = await _users.doc(uid).get();
    final actorRole = actorSnapshot.data()?['role'];
    await _firestore.runTransaction((transaction) async {
      final contractSnapshot = await transaction.get(contractReference);
      if (!contractSnapshot.exists) throw StateError('Sözleşme bulunamadı.');
      final contract = contractSnapshot.data()!;
      if (actorRole == AppRole.supervisor.name &&
          contract['responsibleUserId'] != uid) {
        throw StateError('Yalnız size atanmış sözleşmeyi değiştirebilirsiniz.');
      }
      if (actorRole != AppRole.admin.name &&
          actorRole != AppRole.manager.name &&
          actorRole != AppRole.supervisor.name) {
        throw StateError('Sözleşme durumu değiştirme yetkiniz yok.');
      }
      final now = DateTime.now();
      final actor = actorSnapshot.data() ?? {};
      transaction.update(contractReference, {
        'isActive': isActive,
        'isFinalized': !isActive,
        'finalizedAt': isActive ? null : FieldValue.serverTimestamp(),
        'history': FieldValue.arrayUnion([
          {
            'action': isActive ? 'activated' : 'ended',
            'occurredAt': now.toIso8601String(),
            'previousEndDate': contract['endDate'],
            'newEndDate': contract['endDate'],
            'previousMonthlyPrice': contract['monthlyPrice'],
            'newMonthlyPrice': contract['monthlyPrice'],
            'actorUid': uid,
            'actorUsername': actor['username'] ?? '',
          },
        ]),
      });
    });
  }

  Future<void> sendUserNotification({
    required String userId,
    required String title,
    required String message,
  }) => _call('sendUserNotification', {
    'userId': userId,
    'title': title,
    'message': message,
  });

  Future<void> registerPushToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final tokenId = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    await _users.doc(uid).collection('devices').doc(tokenId).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    await _functions.httpsCallable(name).call<void>(data);
  }
}
