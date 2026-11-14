import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import nodemailer from 'nodemailer';
import { deliveryId, isReminderTime, reminderOffset } from './reminderSchedule.js';
import { canAssignResponsible } from './assignmentPolicy.js';
initializeApp();
const smtpHost = defineSecret('SMTP_HOST');
const smtpPort = defineSecret('SMTP_PORT');
const smtpUser = defineSecret('SMTP_USER');
const smtpPassword = defineSecret('SMTP_PASSWORD');
const mailFrom = defineSecret('MAIL_FROM');
const whatsappToken = defineSecret('WHATSAPP_ACCESS_TOKEN');
const whatsappPhoneNumberId = defineSecret('WHATSAPP_PHONE_NUMBER_ID');
const whatsappTemplateName = defineSecret('WHATSAPP_TEMPLATE_NAME');
const workspaceId = 'rst_dolapdere';
const usernameDomain = 'login.rst-dolapdere.invalid';
async function caller(request) {
    if (!request.auth)
        throw new HttpsError('unauthenticated', 'Oturum açın.');
    const snapshot = await getFirestore()
        .collection('workspaces').doc(workspaceId)
        .collection('users').doc(request.auth.uid).get();
    const profile = snapshot.data();
    if (!profile || profile.isActive !== true) {
        throw new HttpsError('permission-denied', 'Kullanıcı hesabı etkin değil.');
    }
    return { uid: request.auth.uid, role: profile.role };
}
async function requireManager(request) {
    const user = await caller(request);
    if (user.role !== 'admin' && user.role !== 'manager') {
        throw new HttpsError('permission-denied', 'Yönetici yetkisi gerekiyor.');
    }
    return user.uid;
}
function workspaceCollection(name) {
    return getFirestore().collection('workspaces').doc(workspaceId).collection(name);
}
export const adminCreateUser = onCall({ region: 'europe-west1' }, async (request) => {
    const actor = await caller(request);
    const username = String(request.data?.username ?? '').trim().toLowerCase();
    const initialPassword = String(request.data?.initialPassword ?? '');
    const role = String(request.data?.role ?? '');
    const allowedRoles = ['admin', 'manager', 'supervisor'];
    if (!/^[a-z0-9._-]{3,32}$/.test(username) || initialPassword.length < 10 || !allowedRoles.includes(role)) {
        throw new HttpsError('invalid-argument', 'Kullanıcı adı, rol veya başlangıç şifresi geçersiz.');
    }
    if (actor.role === 'manager' && role === 'admin') {
        throw new HttpsError('permission-denied', 'Yalnız sistem yöneticisi admin rolü verebilir.');
    }
    const db = getFirestore();
    const index = workspaceCollection('usernameIndex').doc(username);
    await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(index);
        if (existing.exists)
            throw new HttpsError('already-exists', 'Kullanıcı adı kullanılıyor.');
        transaction.create(index, { pending: true });
    });
    const email = `${username}@${usernameDomain}`;
    let createdUid;
    try {
        const user = await getAuth().createUser({
            email,
            password: initialPassword,
            disabled: request.data?.isActive !== true,
        });
        createdUid = user.uid;
        await workspaceCollection('users').doc(user.uid).set({
            username,
            authEmail: email,
            email: String(request.data?.email ?? '').trim(),
            role,
            isActive: request.data?.isActive === true,
            permissions: request.data?.permissions ?? {},
            notificationPreferences: {
                inApp: true,
                push: true,
                email: true,
            },
            assignedContractIds: [],
            assignedCustomerIds: [],
            assignedAdSpaceIds: [],
            createdAt: FieldValue.serverTimestamp(),
        });
        await index.set({ uid: user.uid });
        await getAuth().setCustomUserClaims(user.uid, { role });
    }
    catch (error) {
        console.error('adminCreateUser failed', error);
        if (createdUid) {
            await Promise.all([
                getAuth().deleteUser(createdUid).catch(() => undefined),
                workspaceCollection('users').doc(createdUid).delete().catch(() => undefined),
            ]);
        }
        await index.delete().catch(() => undefined);
        if (error instanceof HttpsError)
            throw error;
        const code = typeof error === 'object' && error !== null && 'code' in error
            ? String(error.code)
            : '';
        if (code === 'auth/email-already-exists') {
            throw new HttpsError('already-exists', 'Bu kullanıcı adıyla bir hesap zaten var.');
        }
        if (code === 'auth/invalid-email') {
            throw new HttpsError('failed-precondition', 'Firebase kullanıcı e-posta aliasını kabul etmedi.');
        }
        if (code === 'auth/weak-password') {
            throw new HttpsError('invalid-argument', 'Başlangıç şifresi Firebase politikalarını karşılamıyor.');
        }
        throw new HttpsError('internal', `Kullanıcı oluşturulamadı (${code || 'unknown'}).`);
    }
    return { uid: createdUid };
});
export const adminUpdateUser = onCall({ region: 'europe-west1' }, async (request) => {
    const actor = await caller(request);
    if (actor.role !== 'admin' && actor.role !== 'manager') {
        throw new HttpsError('permission-denied', 'Yönetici yetkisi gerekiyor.');
    }
    const uid = String(request.data?.uid ?? '');
    const role = String(request.data?.role ?? '');
    const isActive = request.data?.isActive === true;
    if (!uid || !['admin', 'manager', 'supervisor'].includes(role)) {
        throw new HttpsError('invalid-argument', 'Kullanıcı veya rol geçersiz.');
    }
    const reference = workspaceCollection('users').doc(uid);
    const snapshot = await reference.get();
    if (!snapshot.exists)
        throw new HttpsError('not-found', 'Kullanıcı bulunamadı.');
    const current = snapshot.data();
    if (actor.role === 'manager' && (current.role === 'admin' || role === 'admin')) {
        throw new HttpsError('permission-denied', 'Admin hesaplarını yalnız sistem yöneticisi düzenleyebilir.');
    }
    const updates = {
        role,
        isActive,
        permissions: request.data?.permissions ?? {},
        updatedAt: FieldValue.serverTimestamp(),
    };
    if (request.data?.email !== undefined)
        updates.email = String(request.data.email).trim();
    await Promise.all([
        reference.update(updates),
        getAuth().updateUser(uid, { disabled: !isActive }),
        getAuth().setCustomUserClaims(uid, { role }),
    ]);
    if (current.isActive !== isActive) {
        await workspaceCollection('users').doc(uid).collection('inbox').add({
            title: 'Hesap durumu değişti',
            message: isActive ? 'Hesabınız yeniden etkinleştirildi.' : 'Hesabınız devre dışı bırakıldı.',
            createdAt: FieldValue.serverTimestamp(),
            read: false,
        });
    }
    return { ok: true };
});
export const updateOwnNotificationPreferences = onCall({ region: 'europe-west1' }, async (request) => {
    const user = await caller(request);
    const submitted = request.data?.preferences;
    const allowed = ['inApp', 'push', 'email'];
    if (!submitted || Object.keys(submitted).some((key) => !allowed.includes(key)) ||
        Object.values(submitted).some((value) => typeof value !== 'boolean')) {
        throw new HttpsError('invalid-argument', 'Bildirim tercihleri geçersiz.');
    }
    await workspaceCollection('users').doc(user.uid).update({
        notificationPreferences: submitted,
        updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true };
});
export const adminDeleteUser = onCall({ region: 'europe-west1' }, async (request) => {
    const actor = await caller(request);
    if (actor.role !== 'admin' && actor.role !== 'manager') {
        throw new HttpsError('permission-denied', 'Yönetici yetkisi gerekiyor.');
    }
    const uid = String(request.data?.uid ?? '');
    const requester = request.auth.uid;
    if (!uid || uid === requester)
        throw new HttpsError('failed-precondition', 'Kendi hesabınızı silemezsiniz.');
    const reference = workspaceCollection('users').doc(uid);
    const snapshot = await reference.get();
    if (!snapshot.exists)
        throw new HttpsError('not-found', 'Kullanıcı bulunamadı.');
    const username = String(snapshot.data()?.username ?? '');
    if (actor.role === 'manager' && snapshot.data()?.role === 'admin') {
        throw new HttpsError('permission-denied', 'Admin hesabını yalnız sistem yöneticisi silebilir.');
    }
    const assignedContracts = await workspaceCollection('contracts')
        .where('responsibleUserId', '==', uid)
        .get();
    for (let start = 0; start < assignedContracts.docs.length; start += 450) {
        const batch = getFirestore().batch();
        for (const contract of assignedContracts.docs.slice(start, start + 450)) {
            batch.update(contract.ref, {
                responsibleUserId: FieldValue.delete(),
                responsibleUsername: FieldValue.delete(),
                updatedAt: FieldValue.serverTimestamp(),
            });
        }
        await batch.commit();
    }
    await Promise.all([
        getAuth().deleteUser(uid),
        reference.delete(),
        workspaceCollection('usernameIndex').doc(username).delete(),
    ]);
    return { ok: true };
});
export const assignContractResponsible = onCall({ region: 'europe-west1' }, async (request) => {
    const actor = await caller(request);
    const contractId = String(request.data?.contractId ?? '');
    const uid = String(request.data?.responsibleUserId ?? '');
    const [contract, user] = await Promise.all([
        workspaceCollection('contracts').doc(contractId).get(),
        workspaceCollection('users').doc(uid).get(),
    ]);
    if (!contract.exists || !user.exists || user.data()?.isActive !== true) {
        throw new HttpsError('not-found', 'Sözleşme veya etkin kullanıcı bulunamadı.');
    }
    const contractData = contract.data();
    const previousUid = String(contractData.responsibleUserId ?? '');
    if (!canAssignResponsible(actor.role, actor.uid, uid, previousUid)) {
        if (actor.role === 'supervisor' && uid !== actor.uid) {
            throw new HttpsError('permission-denied', 'Sorumlu yalnızca kendisini atayabilir.');
        }
        if (actor.role === 'supervisor' && previousUid && previousUid !== actor.uid) {
            throw new HttpsError('permission-denied', 'Başka bir sorumluya atanmış sözleşmeyi devralamazsınız.');
        }
        throw new HttpsError('permission-denied', 'Sorumlu atama yetkiniz yok.');
    }
    const customerId = String(contractData.customerId ?? '');
    const adSpaceId = String(contractData.adSpaceId ?? '');
    const previousProfile = previousUid && previousUid !== uid
        ? await workspaceCollection('users').doc(previousUid).get()
        : null;
    await workspaceCollection('contracts').doc(contractId).update({
        responsibleUserId: uid,
        responsibleUsername: String(user.data()?.username ?? ''),
        updatedAt: FieldValue.serverTimestamp(),
    });
    await workspaceCollection('users').doc(uid).update({
        assignedContractIds: FieldValue.arrayUnion(contractId),
        assignedCustomerIds: FieldValue.arrayUnion(String(contractData.customerId ?? '')),
        assignedAdSpaceIds: FieldValue.arrayUnion(String(contractData.adSpaceId ?? '')),
    });
    if (previousProfile?.exists) {
        const remaining = await workspaceCollection('contracts')
            .where('responsibleUserId', '==', previousUid)
            .get();
        const stillHasCustomer = remaining.docs.some((document) => document.id !== contractId && document.data().customerId === customerId);
        const stillHasAdSpace = remaining.docs.some((document) => document.id !== contractId && document.data().adSpaceId === adSpaceId);
        const updates = {
            assignedContractIds: FieldValue.arrayRemove(contractId),
        };
        if (!stillHasCustomer) {
            updates.assignedCustomerIds = FieldValue.arrayRemove(customerId);
        }
        if (!stillHasAdSpace) {
            updates.assignedAdSpaceIds = FieldValue.arrayRemove(adSpaceId);
        }
        await workspaceCollection('users').doc(previousUid).update(updates);
    }
    return { ok: true };
});
export const listAvailableContracts = onCall({ region: 'europe-west1' }, async (request) => {
    const actor = await caller(request);
    if (actor.role !== 'supervisor') {
        throw new HttpsError('permission-denied', 'Bu liste yalnız sorumlu kullanıcılar içindir.');
    }
    const profile = await workspaceCollection('users').doc(actor.uid).get();
    if (profile.data()?.permissions?.contracts !== true) {
        throw new HttpsError('permission-denied', 'Sözleşme görüntüleme izniniz yok.');
    }
    const snapshot = await workspaceCollection('contracts').get();
    const available = snapshot.docs.filter((document) => {
        const contract = document.data();
        return !contract.responsibleUserId && contract.isFinalized !== true;
    });
    const customerIds = [...new Set(available.map((document) => String(document.data().customerId ?? '')).filter(Boolean))];
    const adSpaceIds = [...new Set(available.map((document) => String(document.data().adSpaceId ?? '')).filter(Boolean))];
    const [customers, adSpaces] = await Promise.all([
        Promise.all(customerIds.map((id) => workspaceCollection('customers').doc(id).get())),
        Promise.all(adSpaceIds.map((id) => workspaceCollection('adSpaces').doc(id).get())),
    ]);
    const customerNames = new Map(customers.map((document) => [document.id, document.data()?.name ?? 'Kiracı']));
    const adSpaceNames = new Map(adSpaces.map((document) => [document.id, document.data()?.name ?? 'Reklam alanı']));
    return available.map((document) => ({
        id: document.id,
        ...document.data(),
        customerName: customerNames.get(String(document.data().customerId ?? '')) ?? 'Kiracı',
        adSpaceName: adSpaceNames.get(String(document.data().adSpaceId ?? '')) ?? 'Reklam alanı',
    }));
});
export const submitContractChange = onCall({ region: 'europe-west1' }, async (request) => {
    const user = await caller(request);
    if (user.role !== 'supervisor')
        throw new HttpsError('permission-denied', 'Bu işlem yalnızca sorumlu hesabı içindir.');
    const operation = String(request.data?.operation ?? '');
    const contractId = String(request.data?.contractId ?? '');
    const contractData = request.data?.contract;
    if (!['create', 'renew'].includes(operation) || !contractData) {
        throw new HttpsError('invalid-argument', 'Sözleşme talebi geçersiz.');
    }
    if (Number(contractData.monthlyPrice ?? 0) <= 0) {
        throw new HttpsError('invalid-argument', 'Birim fiyat zorunludur.');
    }
    const [profileSnapshot, startDate, endDate] = await Promise.all([
        workspaceCollection('users').doc(user.uid).get(),
        Promise.resolve(parseDate(contractData.startDate)),
        Promise.resolve(parseDate(contractData.endDate)),
    ]);
    if (!startDate || !endDate || endDate <= startDate) {
        throw new HttpsError('invalid-argument', 'Sözleşme tarihleri geçersiz.');
    }
    const profile = profileSnapshot.data() ?? {};
    const assignedCustomers = profile.assignedCustomerIds ?? [];
    const assignedAdSpaces = profile.assignedAdSpaceIds ?? [];
    const customerId = String(contractData.customerId ?? '');
    const adSpaceId = String(contractData.adSpaceId ?? '');
    if (!assignedCustomers.includes(customerId) || !assignedAdSpaces.includes(adSpaceId)) {
        throw new HttpsError('permission-denied', 'Yalnız size atanmış kiracı ve alanlarda sözleşme işlemi yapabilirsiniz.');
    }
    if (operation === 'renew') {
        const source = await workspaceCollection('contracts').doc(contractId).get();
        const sourceData = source.data();
        if (!source.exists || sourceData?.responsibleUserId !== user.uid) {
            throw new HttpsError('permission-denied', 'Sözleşme size atanmamış.');
        }
        const sourceEndDate = parseDate(sourceData?.endDate);
        if (!sourceEndDate || endDate <= sourceEndDate ||
            customerId !== sourceData?.customerId || adSpaceId !== sourceData?.adSpaceId) {
            throw new HttpsError('invalid-argument', 'Uzatma, atanmış sözleşmenin bitişini ileri taşımalıdır.');
        }
    }
    else {
        const overlapping = await workspaceCollection('contracts')
            .where('adSpaceId', '==', adSpaceId)
            .get();
        const hasOverlap = overlapping.docs.some((document) => {
            const current = document.data();
            if (current.isActive !== true || current.isFinalized === true)
                return false;
            const currentStart = parseDate(current.startDate);
            const currentEnd = parseDate(current.endDate);
            return currentStart != null && currentEnd != null &&
                currentStart <= endDate && currentEnd >= startDate;
        });
        if (hasOverlap) {
            throw new HttpsError('already-exists', 'Reklam alanında çakışan aktif sözleşme var.');
        }
    }
    const reference = await workspaceCollection('contractRequests').add({
        operation,
        contractId: contractId || null,
        contract: contractData,
        submittedBy: user.uid,
        status: 'pending',
        createdAt: FieldValue.serverTimestamp(),
    });
    const managers = await workspaceCollection('users').where('role', 'in', ['admin', 'manager']).get();
    await Promise.all(managers.docs.map((manager) => workspaceCollection('users')
        .doc(manager.id).collection('inbox').add({
        title: 'Sözleşme onayı bekliyor',
        message: `${operation === 'create' ? 'Yeni sözleşme' : 'Sözleşme uzatma'} talebi inceleme bekliyor.`,
        requestId: reference.id,
        createdAt: FieldValue.serverTimestamp(),
        read: false,
    })));
    return { requestId: reference.id };
});
export const reviewContractRequest = onCall({ region: 'europe-west1' }, async (request) => {
    const reviewer = await requireManager(request);
    const requestId = String(request.data?.requestId ?? '');
    const approve = request.data?.approve === true;
    const reference = workspaceCollection('contractRequests').doc(requestId);
    const result = await getFirestore().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        const data = snapshot.data();
        if (!data || data.status !== 'pending')
            throw new HttpsError('failed-precondition', 'Talep bulunamadı veya daha önce işlendi.');
        const submitterRef = workspaceCollection('users').doc(String(data.submittedBy));
        const submitter = await transaction.get(submitterRef);
        if (!submitter.exists)
            throw new HttpsError('not-found', 'Talep sahibi bulunamadı.');
        if (approve) {
            const contract = data.contract;
            if (data.operation === 'create') {
                const contractRef = workspaceCollection('contracts').doc(String(contract.id));
                const [existingContract, sameSpaceContracts] = await Promise.all([
                    transaction.get(contractRef),
                    transaction.get(workspaceCollection('contracts').where('adSpaceId', '==', String(contract.adSpaceId ?? ''))),
                ]);
                if (existingContract.exists) {
                    throw new HttpsError('already-exists', 'Sözleşme kimliği zaten kullanılıyor.');
                }
                const newStart = parseDate(contract.startDate);
                const newEnd = parseDate(contract.endDate);
                const overlaps = sameSpaceContracts.docs.some((document) => {
                    const current = document.data();
                    if (current.isActive !== true || current.isFinalized === true)
                        return false;
                    const currentStart = parseDate(current.startDate);
                    const currentEnd = parseDate(current.endDate);
                    return newStart != null && newEnd != null &&
                        currentStart != null && currentEnd != null &&
                        currentStart <= newEnd && currentEnd >= newStart;
                });
                if (overlaps) {
                    throw new HttpsError('already-exists', 'Onay öncesinde bu alanda çakışan sözleşme oluşturuldu.');
                }
                transaction.set(contractRef, {
                    ...contract,
                    isActive: true,
                    isFinalized: false,
                    responsibleUserId: data.submittedBy,
                    responsibleUsername: String(submitter.data()?.username ?? ''),
                    createdBy: data.submittedBy,
                    approvedBy: reviewer,
                    createdAt: FieldValue.serverTimestamp(),
                    history: [{
                            action: 'created',
                            occurredAt: new Date().toISOString(),
                            newEndDate: contract.endDate,
                            newMonthlyPrice: contract.monthlyPrice,
                        }],
                });
            }
            else {
                const contractRef = workspaceCollection('contracts').doc(String(data.contractId));
                const existing = await transaction.get(contractRef);
                const source = existing.data();
                if (!source)
                    throw new HttpsError('not-found', 'Sözleşme bulunamadı.');
                transaction.update(contractRef, {
                    ...contract,
                    id: data.contractId,
                    customerId: source.customerId,
                    adSpaceId: source.adSpaceId,
                    startDate: source.startDate,
                    responsibleUserId: source.responsibleUserId,
                    responsibleUsername: source.responsibleUsername,
                    isActive: true,
                    isFinalized: false,
                    finalizedAt: null,
                    approvedBy: reviewer,
                    history: [
                        ...(source.history ?? []),
                        {
                            action: 'renewed',
                            occurredAt: new Date().toISOString(),
                            previousEndDate: source.endDate,
                            newEndDate: contract.endDate,
                            previousMonthlyPrice: source.monthlyPrice,
                            newMonthlyPrice: contract.monthlyPrice,
                        },
                    ],
                });
            }
            transaction.update(submitterRef, {
                assignedContractIds: FieldValue.arrayUnion(String(data.contractId ?? contract.id ?? '')),
                assignedCustomerIds: FieldValue.arrayUnion(String(contract.customerId ?? '')),
                assignedAdSpaceIds: FieldValue.arrayUnion(String(contract.adSpaceId ?? '')),
            });
        }
        transaction.update(reference, {
            status: approve ? 'approved' : 'rejected',
            reviewedBy: reviewer,
            reviewedAt: FieldValue.serverTimestamp(),
            reviewNote: String(request.data?.note ?? '').trim(),
        });
        return data.submittedBy;
    });
    await workspaceCollection('users').doc(result).collection('inbox').add({
        title: approve ? 'Sözleşme talebi onaylandı' : 'Sözleşme talebi reddedildi',
        message: String(request.data?.note ?? '').trim() || (approve ? 'Talebiniz onaylandı.' : 'Talebiniz reddedildi.'),
        requestId,
        createdAt: FieldValue.serverTimestamp(),
        read: false,
    });
    return { ok: true };
});
export const setContractActive = onCall({ region: 'europe-west1' }, async (request) => {
    const user = await caller(request);
    const contractId = String(request.data?.contractId ?? '');
    const reference = workspaceCollection('contracts').doc(contractId);
    const snapshot = await reference.get();
    if (!snapshot.exists)
        throw new HttpsError('not-found', 'Sözleşme bulunamadı.');
    const source = snapshot.data();
    if (user.role === 'supervisor' && source.responsibleUserId !== user.uid) {
        throw new HttpsError('permission-denied', 'Sözleşme size atanmamış.');
    }
    if (user.role !== 'admin' && user.role !== 'manager' && user.role !== 'supervisor') {
        throw new HttpsError('permission-denied', 'İşlem yetkiniz yok.');
    }
    const isActive = request.data?.isActive === true;
    await reference.update({
        isActive,
        isFinalized: !isActive,
        finalizedAt: isActive ? null : FieldValue.serverTimestamp(),
        history: FieldValue.arrayUnion({
            action: isActive ? 'activated' : 'ended',
            occurredAt: new Date().toISOString(),
            previousEndDate: source.endDate,
            newEndDate: source.endDate,
            previousMonthlyPrice: source.monthlyPrice,
            newMonthlyPrice: source.monthlyPrice,
        }),
    });
    return { ok: true };
});
export const sendUserNotification = onCall({
    region: 'europe-west1',
    secrets: [smtpHost, smtpPort, smtpUser, smtpPassword, mailFrom],
}, async (request) => {
    await requireManager(request);
    const userId = String(request.data?.userId ?? '');
    const title = String(request.data?.title ?? '').trim();
    const message = String(request.data?.message ?? '').trim();
    if (!userId || !title || !message || title.length > 120 || message.length > 2000) {
        throw new HttpsError('invalid-argument', 'Bildirim alanları geçersiz.');
    }
    const profile = await workspaceCollection('users').doc(userId).get();
    if (!profile.exists || profile.data()?.isActive !== true)
        throw new HttpsError('not-found', 'Etkin kullanıcı bulunamadı.');
    const preferences = profile.data()?.notificationPreferences ?? {};
    if (preferences.inApp !== false) {
        await workspaceCollection('users').doc(userId).collection('inbox').add({
            title,
            message,
            createdAt: FieldValue.serverTimestamp(),
            read: false,
        });
    }
    const devices = await workspaceCollection('users').doc(userId).collection('devices').get();
    const tokens = devices.docs.map((document) => String(document.data().token ?? '')).filter(Boolean);
    if (preferences.push !== false && tokens.length)
        await getMessaging().sendEachForMulticast({
            tokens,
            notification: { title, body: message },
        });
    const email = String(profile.data()?.email ?? '').trim();
    if (preferences.email !== false && email) {
        const port = Number(smtpPort.value());
        const transporter = nodemailer.createTransport({
            host: smtpHost.value(),
            port,
            secure: port === 465,
            auth: { user: smtpUser.value(), pass: smtpPassword.value() },
        });
        await transporter.sendMail({ from: mailFrom.value(), to: email, subject: title, text: message });
    }
    return { ok: true };
});
function parseDate(value) {
    if (value instanceof Date)
        return value;
    if (value instanceof Timestamp)
        return value.toDate();
    if (typeof value === 'string') {
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? null : date;
    }
    return null;
}
function escapeHtml(text) {
    return text.replace(/[&<>"']/g, (character) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
    })[character]);
}
async function sendOnce(id, channel, send) {
    const db = getFirestore();
    const reference = db
        .collection('workspaces')
        .doc(workspaceId)
        .collection('reminderDeliveries')
        .doc(id);
    const claimed = await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        if (snapshot.data()?.status === 'sent')
            return false;
        transaction.set(reference, {
            channel,
            status: 'sending',
            updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        return true;
    });
    if (!claimed)
        return;
    try {
        await send();
        await reference.set({
            status: 'sent',
            sentAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    catch (error) {
        await reference.set({
            status: 'failed',
            error: String(error).slice(0, 500),
            updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        throw error;
    }
}
async function sendEmail(to, details) {
    const port = Number(smtpPort.value());
    const transporter = nodemailer.createTransport({
        host: smtpHost.value(),
        port,
        secure: port === 465,
        auth: { user: smtpUser.value(), pass: smtpPassword.value() },
    });
    const timing = details.offset === 0 ? 'bugün sona eriyor' : `${details.offset} gün sonra sona eriyor`;
    const text = [
        'DST Dolapdere sözleşme hatırlatması',
        '',
        `Kiracı: ${details.customer}`,
        `Reklam alanı: ${details.adSpace}`,
        `Bitiş tarihi: ${details.endDate}`,
        `Sözleşme ${timing}.`,
    ].join('\n');
    await transporter.sendMail({
        from: mailFrom.value(),
        to,
        subject: `Sözleşme hatırlatması: ${details.adSpace}`,
        text,
        html: `<p>DST Dolapdere sözleşme hatırlatması</p><p><b>${escapeHtml(details.adSpace)}</b> alanındaki sözleşme ${escapeHtml(timing)}.</p><p>Kiracı: ${escapeHtml(details.customer)}<br>Bitiş: ${escapeHtml(details.endDate)}</p>`,
    });
}
async function sendWhatsApp(to, details) {
    const phone = to.replace(/[^0-9]/g, '');
    if (phone.length < 8)
        throw new Error('WhatsApp alıcı numarası geçersiz.');
    const timing = details.offset === 0 ? 'son gün' : `${details.offset} gün kala`;
    const response = await fetch(`https://graph.facebook.com/v22.0/${whatsappPhoneNumberId.value()}/messages`, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${whatsappToken.value()}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            messaging_product: 'whatsapp',
            to: phone,
            type: 'template',
            template: {
                name: whatsappTemplateName.value(),
                language: { code: 'tr' },
                components: [{
                        type: 'body',
                        parameters: [
                            { type: 'text', text: details.customer },
                            { type: 'text', text: details.adSpace },
                            { type: 'text', text: details.endDate },
                            { type: 'text', text: timing },
                        ],
                    }],
            },
        }),
    });
    if (!response.ok)
        throw new Error(`WhatsApp API ${response.status}: ${await response.text()}`);
}
export const sendContractReminders = onSchedule({
    schedule: '*/5 * * * *',
    timeZone: 'Europe/Istanbul',
    region: 'europe-west1',
    timeoutSeconds: 300,
    secrets: [
        smtpHost, smtpPort, smtpUser, smtpPassword, mailFrom,
        whatsappToken, whatsappPhoneNumberId, whatsappTemplateName,
    ],
}, async () => {
    const db = getFirestore();
    const workspace = db.collection('workspaces').doc(workspaceId);
    const settingsSnapshot = await workspace.collection('settings').doc('reminders').get();
    const settings = settingsSnapshot.data() ?? {};
    const reminderMinutes = Number(settings.reminderTimeMinutes ?? 540);
    if (!isReminderTime(new Date(), reminderMinutes))
        return;
    const emailEnabled = settings.emailRemindersEnabled === true;
    const whatsappEnabled = settings.whatsappRemindersEnabled === true;
    if (!emailEnabled && !whatsappEnabled)
        return;
    const managerEmail = String(settings.managerEmail ?? '').trim();
    const managerWhatsapp = String(settings.managerWhatsapp ?? '').trim();
    if (emailEnabled && !managerEmail)
        throw new Error('Yönetici e-posta adresi ayarlanmamış.');
    if (whatsappEnabled && !managerWhatsapp)
        throw new Error('Yönetici WhatsApp numarası ayarlanmamış.');
    const [contractSnapshot, customersSnapshot, spacesSnapshot] = await Promise.all([
        workspace.collection('contracts').where('isActive', '==', true).get(),
        workspace.collection('customers').get(),
        workspace.collection('adSpaces').get(),
    ]);
    const customers = new Map(customersSnapshot.docs.map((doc) => [doc.id, doc.data()]));
    const spaces = new Map(spacesSnapshot.docs.map((doc) => [doc.id, doc.data()]));
    const now = new Date();
    for (const document of contractSnapshot.docs) {
        const contract = { ...document.data(), id: document.id };
        if (contract.isFinalized)
            continue;
        const endDate = parseDate(contract.endDate);
        if (!endDate)
            continue;
        const offset = reminderOffset(endDate, now);
        if (offset === null)
            continue;
        const customer = customers.get(String(contract.customerId ?? '')) ?? {};
        const adSpace = spaces.get(String(contract.adSpaceId ?? '')) ?? {};
        const details = {
            customer: String(customer.name ?? 'Kiracı'),
            adSpace: String(adSpace.name ?? 'Reklam alanı'),
            endDate: new Intl.DateTimeFormat('tr-TR', {
                timeZone: 'Europe/Istanbul',
                day: '2-digit', month: '2-digit', year: 'numeric',
            }).format(endDate),
            offset,
        };
        if (emailEnabled) {
            await sendOnce(deliveryId(document.id, endDate, offset, 'email'), 'email', () => sendEmail(managerEmail, details));
        }
        if (whatsappEnabled) {
            await sendOnce(deliveryId(document.id, endDate, offset, 'whatsapp'), 'whatsapp', () => sendWhatsApp(managerWhatsapp, details));
        }
    }
});
