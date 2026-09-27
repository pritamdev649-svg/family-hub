/**
 * Emergency cards: docs/03-API_CONTRACT.md §6 (`GET|PUT /family/members/:memberId/emergency-card`).
 *
 * Covers the empty card, create / replace / clear, normalisation, AES-256-GCM encryption at rest
 * (verified on the raw MongoDB document), the permission matrix (self / admin / member / managed
 * profile / other family / no family / no token), every contract limit with its boundary, 422
 * `details`, 400 for malformed ids / JSON, read-only keys being ignored, concurrent first saves,
 * decryption failures (never shown as "no allergies") and the envelope shape.
 *
 * Managed profiles are inserted with the Member model directly so these tests do not depend on
 * `POST /family/members` (family module).
 */
import { API, authHeader, joinFamilyAs, registerFamilyAdmin, resetDb, setupTestApp, teardownTestApp } from './helpers.js';
import assert from 'node:assert/strict';
import { isDeepStrictEqual } from 'node:util';
import { after, before, beforeEach, describe, it } from 'node:test';

const { default: mongoose } = await import('mongoose');
const { EmergencyCard, Member, User } = await import('../src/models/index.js');
const { decryptField } = await import('../src/lib/crypto.js');
const { plainCardFor, deleteCardForMember } = await import('../src/modules/emergencyCards/emergencyCards.service.js');

let request;

before(async () => {
  ({ request } = await setupTestApp());
});
beforeEach(resetDb);
after(teardownTestApp);

// ---------------------------------------------------------------- helpers

const OBJECT_ID = /^[a-f0-9]{24}$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const UNKNOWN_ID = 'aaaaaaaaaaaaaaaaaaaaaaaa';

const CARD_KEYS = [
  'allergies',
  'bloodGroup',
  'conditions',
  'doctorName',
  'doctorPhone',
  'emergencyContacts',
  'insurancePolicyNumber',
  'insuranceProvider',
  'medications',
  'memberId',
  'notes',
  'updatedAt',
  'updatedById',
].sort();

const ENCRYPTED_PATHS = ['allergiesEnc', 'medicationsEnc', 'conditionsEnc', 'insurancePolicyNumberEnc', 'notesEnc'];
const LIST_FIELDS = ['allergies', 'medications', 'conditions'];

const cardUrl = (memberId) => `${API}/family/members/${memberId}/emergency-card`;

function assertOk(res, status = 200) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, true);
  assert.ok('data' in res.body);
  assert.ok(!('meta' in res.body), 'meta only on paginated lists');
  return res.body.data;
}

function assertError(res, status, code) {
  assert.equal(res.status, status, JSON.stringify(res.body));
  assert.equal(res.body.success, false);
  assert.ok(!('data' in res.body));
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
  assert.ok(res.body.error.message.length > 0);
  assert.ok(!('stack' in res.body.error));
  return res.body.error;
}

/** 422 VALIDATION_ERROR whose `details` contain every expected path. */
function assertValidation(res, ...paths) {
  const error = assertError(res, 422, 'VALIDATION_ERROR');
  assert.equal(typeof error.details, 'object', JSON.stringify(res.body));
  for (const path of paths) {
    assert.equal(typeof error.details[path], 'string', `details.${path} missing in ${JSON.stringify(error.details)}`);
    assert.ok(error.details[path].length > 0);
  }
  return error.details;
}

function assertCardShape(card, memberId) {
  assert.deepEqual(Object.keys(card).sort(), CARD_KEYS);
  assert.equal(card.memberId, memberId);
  for (const forbidden of ['id', '_id', '__v', 'familyId', 'createdAt', ...ENCRYPTED_PATHS]) {
    assert.ok(!(forbidden in card), `${forbidden} must not be exposed`);
  }
}

function assertEmptyCard(card, memberId) {
  assertCardShape(card, memberId);
  assert.deepEqual(card, {
    memberId,
    bloodGroup: 'unknown',
    allergies: [],
    medications: [],
    conditions: [],
    doctorName: null,
    doctorPhone: null,
    insuranceProvider: null,
    insurancePolicyNumber: null,
    emergencyContacts: [],
    notes: null,
    updatedAt: null,
    updatedById: null,
  });
}

const fullCard = () => ({
  bloodGroup: 'B+',
  allergies: ['Peanuts', 'Penicillin'],
  medications: ['Metformin 500mg'],
  conditions: ['Asthma', 'Type 2 diabetes'],
  doctorName: 'Dr. Rao',
  doctorPhone: '+919876543210',
  insuranceProvider: 'Star Health',
  insurancePolicyNumber: 'P-123',
  emergencyContacts: [
    { name: 'Ravi', phone: '+919812345678', relation: 'Uncle' },
    { name: 'Meera', phone: '+14155550100', relation: 'Neighbour' },
  ],
  notes: 'Carries an inhaler in the blue bag.',
});

/** The raw MongoDB document (bypasses Mongoose virtuals / toJSON). */
function rawCard(memberId) {
  return EmergencyCard.collection.findOne({ memberId: new mongoose.Types.ObjectId(memberId) });
}

/** A managed profile (no account) in `familyId`. */
async function managedMember(familyId, overrides = {}) {
  const doc = await Member.create({
    familyId,
    name: 'Anaya',
    role: 'member',
    dateOfBirth: new Date('2016-08-01T00:00:00.000Z'),
    guardianConsent: true,
    ...overrides,
  });
  return { id: String(doc._id), ...doc.toJSON() };
}

/**
 * Family A: admin + member (with accounts) + managed child. Family B: its own admin + member.
 */
async function twoFamilies() {
  const admin = await registerFamilyAdmin({ name: 'Amit Sharma' });
  const member = await joinFamilyAs(admin.family.inviteCode, { name: 'Priya Sharma' });
  const child = await managedMember(admin.family.id);
  const otherAdmin = await registerFamilyAdmin({ name: 'Other Admin', family: { name: 'Other Family' } });
  const otherMember = await joinFamilyAs(otherAdmin.family.inviteCode, { name: 'Other Member' });
  return { admin, member, child, otherAdmin, otherMember };
}

const put = (auth, memberId, body) => request.put(cardUrl(memberId)).set(auth).send(body);
const get = (auth, memberId) => request.get(cardUrl(memberId)).set(auth);
/** PUT with a raw (string) JSON body, e.g. to send `__proto__` keys that `JSON.stringify` would drop. */
const putRaw = (auth, memberId, raw) =>
  request.put(cardUrl(memberId)).set(auth).set('Content-Type', 'application/json').send(raw);

/**
 * Holds the first card query or write the service makes (`EmergencyCard.findOne` /
 * `findOneAndUpdate`). The call runs, then `between()` runs before its result is handed back.
 * That opens the window between "read" and "write" of a read-modify-write, or the window after
 * an atomic write, so another request can be run in between deterministically.
 * Returns a restore function.
 */
function holdFirstCardCall({ before: beforeCall = async () => {}, between = async () => {} } = {}) {
  const originals = { findOne: EmergencyCard.findOne, findOneAndUpdate: EmergencyCard.findOneAndUpdate };
  let held = false;
  for (const [method, original] of Object.entries(originals)) {
    EmergencyCard[method] = function heldCall(...args) {
      if (held) return original.apply(this, args);
      held = true;
      return beforeCall()
        .then(() => original.apply(this, args))
        .then(async (result) => {
          await between();
          return result;
        });
    };
  }
  return () => Object.assign(EmergencyCard, originals);
}

/** The stored card without the per-save keys, for "is it exactly this body?" comparisons. */
async function storedFields(auth, memberId) {
  const { memberId: _m, updatedAt: _u, updatedById: _b, ...fields } = assertOk(await get(auth, memberId));
  return fields;
}

/** A body as the server stores it (every editable key present, empty values filled in). */
function asStored(body) {
  const { updatedAt: _u, updatedById: _b, memberId: _m, ...empty } = EmergencyCard.emptyCard(UNKNOWN_ID);
  return { ...empty, ...body };
}

// ---------------------------------------------------------------- GET

describe('GET /family/members/:memberId/emergency-card', () => {
  it('returns the contract empty card (updatedAt null) when none is saved, without creating one', async () => {
    const { admin } = await twoFamilies();
    const res = await get(admin.auth, admin.member.id);
    const card = assertOk(res);
    assertEmptyCard(card, admin.member.id);
    assert.match(res.headers['cache-control'], /no-store/);
    assert.equal(await EmergencyCard.countDocuments(), 0);
  });

  it('returns the saved, decrypted card', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const card = assertOk(await get(admin.auth, admin.member.id));
    assertCardShape(card, admin.member.id);
    const { memberId, updatedAt, updatedById, ...fields } = card;
    assert.deepEqual(fields, fullCard());
    assert.equal(memberId, admin.member.id);
    assert.match(updatedAt, ISO);
    assert.equal(updatedById, admin.member.id);
  });

  it('lets any member of the family read any card (self, admin, managed profile)', async () => {
    const { admin, member, child } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    assertOk(await put(admin.auth, child.id, { bloodGroup: 'O-' }));

    const adminsCard = assertOk(await get(member.auth, admin.member.id));
    assert.deepEqual(adminsCard.allergies, ['Peanuts', 'Penicillin']);
    assert.equal(adminsCard.insurancePolicyNumber, 'P-123');

    const childsCard = assertOk(await get(member.auth, child.id));
    assert.equal(childsCard.bloodGroup, 'O-');
    assert.equal(childsCard.updatedById, admin.member.id);

    assertEmptyCard(assertOk(await get(member.auth, member.member.id)), member.member.id);
  });

  it('404 for a member of another family (never leaks that the card exists)', async () => {
    const { admin, otherAdmin, otherMember } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    assertError(await get(otherAdmin.auth, admin.member.id), 404, 'NOT_FOUND');
    assertError(await get(otherMember.auth, admin.member.id), 404, 'NOT_FOUND');
    // Same answer as for an id that does not exist at all.
    assertError(await get(otherAdmin.auth, UNKNOWN_ID), 404, 'NOT_FOUND');
  });

  it('404 for a member that was removed, even if a stale card remains', async () => {
    const { admin, child } = await twoFamilies();
    assertOk(await put(admin.auth, child.id, fullCard()));
    await Member.deleteOne({ _id: child.id });
    assertError(await get(admin.auth, child.id), 404, 'NOT_FOUND');
  });

  it('400 BAD_REQUEST for a malformed member id', async () => {
    const { admin } = await twoFamilies();
    const error = assertError(await get(admin.auth, 'not-an-id'), 400, 'BAD_REQUEST');
    assert.equal(typeof error.details.memberId, 'string');
    assertError(await get(admin.auth, `${admin.member.id}0`), 400, 'BAD_REQUEST');
  });

  it('accepts an upper-case member id', async () => {
    const { admin } = await twoFamilies();
    const card = assertOk(await get(admin.auth, admin.member.id.toUpperCase()));
    assert.equal(card.memberId, admin.member.id);
  });

  it('401 without / with an invalid token', async () => {
    const { admin } = await twoFamilies();
    assertError(await request.get(cardUrl(admin.member.id)), 401, 'UNAUTHORIZED');
    assertError(await get(authHeader('garbage'), admin.member.id), 401, 'UNAUTHORIZED');
  });

  it('403 NO_FAMILY when the caller has no family', async () => {
    const { admin, member } = await twoFamilies();
    await User.updateOne({ _id: member.user.id }, { familyId: null, memberId: null });
    assertError(await get(member.auth, admin.member.id), 403, 'NO_FAMILY');
  });

  it('fails loudly (500) instead of showing an empty card when a field cannot be decrypted', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    await EmergencyCard.collection.updateOne(
      { memberId: new mongoose.Types.ObjectId(admin.member.id) },
      { $set: { allergiesEnc: 'enc:v1:AAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAA.AAAA' } },
    );
    const error = assertError(await get(admin.auth, admin.member.id), 500, 'INTERNAL_ERROR');
    assert.ok(!/decrypt|enc:v1|aes/i.test(error.message), 'no internals in the message');
  });
});

// ---------------------------------------------------------------- PUT

describe('PUT /family/members/:memberId/emergency-card', () => {
  it('self creates the card: 200, contract shape, updatedAt + updatedById set', async () => {
    const { member } = await twoFamilies();
    const res = await put(member.auth, member.member.id, fullCard());
    const card = assertOk(res);
    assertCardShape(card, member.member.id);
    const { memberId, updatedAt, updatedById, ...fields } = card;
    assert.deepEqual(fields, fullCard());
    assert.match(updatedAt, ISO);
    assert.equal(updatedById, member.member.id);
    assert.match(res.headers['cache-control'], /no-store/);

    const docs = await EmergencyCard.find({}).lean();
    assert.equal(docs.length, 1);
    assert.equal(String(docs[0].familyId), member.family.id);
    assert.equal(String(docs[0].memberId), member.member.id);
  });

  it('encrypts allergies, medications, conditions, policy number and notes at rest', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const raw = await rawCard(admin.member.id);
    assert.ok(raw);

    for (const path of ENCRYPTED_PATHS) {
      assert.equal(typeof raw[path], 'string', path);
      assert.match(raw[path], /^enc:v1:[\w-]+\.[\w-]+\.[\w-]+$/, path);
    }
    for (const plain of ['allergies', 'medications', 'conditions', 'insurancePolicyNumber', 'notes']) {
      assert.ok(!(plain in raw), `${plain} must not be stored in plaintext`);
    }
    const serialized = JSON.stringify(raw);
    for (const secret of ['Peanuts', 'Penicillin', 'Metformin', 'Asthma', 'diabetes', 'P-123', 'inhaler']) {
      assert.ok(!serialized.includes(secret), `"${secret}" leaked into the raw document`);
    }
    // The ciphertext decrypts to exactly what was sent.
    assert.deepEqual(decryptField(raw.allergiesEnc), ['Peanuts', 'Penicillin']);
    assert.deepEqual(decryptField(raw.medicationsEnc), ['Metformin 500mg']);
    assert.deepEqual(decryptField(raw.conditionsEnc), ['Asthma', 'Type 2 diabetes']);
    assert.equal(decryptField(raw.insurancePolicyNumberEnc), 'P-123');
    assert.equal(decryptField(raw.notesEnc), 'Carries an inhaler in the blue bag.');
    // Non-sensitive fields stay queryable in plaintext.
    assert.equal(raw.bloodGroup, 'B+');
    assert.equal(raw.doctorName, 'Dr. Rao');
    assert.equal(raw.emergencyContacts.length, 2);
  });

  it('uses a fresh IV on every save (same plaintext → different ciphertext)', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const first = await rawCard(admin.member.id);
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const second = await rawCard(admin.member.id);
    assert.notEqual(first.allergiesEnc, second.allergiesEnc);
    assert.deepEqual(decryptField(second.allergiesEnc), decryptField(first.allergiesEnc));
  });

  it('replaces the whole card: fields left out are reset, one document per member', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const card = assertOk(await put(admin.auth, admin.member.id, { bloodGroup: 'O+', allergies: ['Dust'] }));
    assert.equal(card.bloodGroup, 'O+');
    assert.deepEqual(card.allergies, ['Dust']);
    assert.deepEqual(card.medications, []);
    assert.deepEqual(card.conditions, []);
    assert.equal(card.doctorName, null);
    assert.equal(card.doctorPhone, null);
    assert.equal(card.insuranceProvider, null);
    assert.equal(card.insurancePolicyNumber, null);
    assert.deepEqual(card.emergencyContacts, []);
    assert.equal(card.notes, null);
    assert.equal(await EmergencyCard.countDocuments({ memberId: admin.member.id }), 1);

    const raw = await rawCard(admin.member.id);
    for (const path of ['medicationsEnc', 'conditionsEnc', 'insurancePolicyNumberEnc', 'notesEnc']) {
      assert.equal(raw[path], null, `${path} is cleared, not kept as ciphertext`);
    }
  });

  it('an empty body saves an empty card (bloodGroup "unknown") and sets updatedAt', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const card = assertOk(await put(admin.auth, admin.member.id, {}));
    const { updatedAt, updatedById, ...rest } = card;
    const { updatedAt: _emptyUpdatedAt, updatedById: _emptyUpdatedById, ...empty } = EmergencyCard.emptyCard(admin.member.id);
    assert.deepEqual(rest, empty);
    assert.match(updatedAt, ISO);
    assert.equal(updatedById, admin.member.id);
  });

  it('null and blank strings clear fields', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        bloodGroup: null,
        allergies: null,
        medications: [],
        conditions: null,
        doctorName: '',
        doctorPhone: '   ',
        insuranceProvider: null,
        insurancePolicyNumber: '  ',
        emergencyContacts: null,
        notes: '',
      }),
    );
    assert.equal(card.bloodGroup, 'unknown');
    for (const list of LIST_FIELDS) assert.deepEqual(card[list], []);
    for (const text of ['doctorName', 'doctorPhone', 'insuranceProvider', 'insurancePolicyNumber', 'notes']) {
      assert.equal(card[text], null, text);
    }
    assert.deepEqual(card.emergencyContacts, []);
  });

  it('normalises input: trims text, strips phone formatting, blood group case, blank / duplicate list items', async () => {
    const { admin } = await twoFamilies();
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        bloodGroup: ' ab - ',
        allergies: ['  Peanuts ', '', '   ', 'peanuts', 'PEANUTS', 'Shellfish'],
        medications: [' Metformin 500mg '],
        conditions: [],
        doctorName: '  Dr. Rao  ',
        doctorPhone: '+91 (987) 654-3210',
        insuranceProvider: ' Star Health ',
        insurancePolicyNumber: ' P-123 ',
        emergencyContacts: [{ name: '  Ravi ', phone: ' +91 98123 45678 ', relation: '  ' }, { name: 'Meera' }],
        notes: '  Keep calm.  ',
      }),
    );
    assert.equal(card.bloodGroup, 'AB-');
    assert.deepEqual(card.allergies, ['Peanuts', 'Shellfish']);
    assert.deepEqual(card.medications, ['Metformin 500mg']);
    assert.equal(card.doctorName, 'Dr. Rao');
    assert.equal(card.doctorPhone, '+919876543210');
    assert.equal(card.insuranceProvider, 'Star Health');
    assert.equal(card.insurancePolicyNumber, 'P-123');
    assert.deepEqual(card.emergencyContacts, [
      { name: 'Ravi', phone: '+919812345678', relation: null },
      { name: 'Meera', phone: null, relation: null },
    ]);
    assert.equal(card.notes, 'Keep calm.');
    assert.equal((await put(admin.auth, admin.member.id, { bloodGroup: 'UNKNOWN' })).body.data.bloodGroup, 'unknown');
  });

  it('accepts every blood group from the contract', async () => {
    const { admin } = await twoFamilies();
    for (const group of ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown']) {
      const card = assertOk(await put(admin.auth, admin.member.id, { bloodGroup: group }));
      assert.equal(card.bloodGroup, group);
    }
  });

  it('round-trips non-Latin text (Hindi, Arabic, emoji)', async () => {
    const { admin } = await twoFamilies();
    const body = {
      allergies: ['मूंगफली', 'فول سوداني'],
      conditions: ['दमा 🫁'],
      notes: 'नीले बैग में इनहेलर है। — يحمل جهاز استنشاق',
      emergencyContacts: [{ name: 'रवि', phone: '+919812345678', relation: 'चाचा' }],
    };
    const card = assertOk(await put(admin.auth, admin.member.id, body));
    assert.deepEqual(card.allergies, body.allergies);
    assert.deepEqual(card.conditions, body.conditions);
    assert.equal(card.notes, body.notes);
    assert.deepEqual(card.emergencyContacts, body.emergencyContacts);
    assert.deepEqual(assertOk(await get(admin.auth, admin.member.id)).allergies, body.allergies);
  });

  it('ignores read-only and unknown keys (memberId, updatedAt, updatedById, *Enc, familyId)', async () => {
    const { admin, member, otherAdmin } = await twoFamilies();
    // A GET response sent straight back must be accepted.
    const saved = assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const roundTrip = assertOk(await put(admin.auth, admin.member.id, saved));
    assert.deepEqual(roundTrip.allergies, saved.allergies);

    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        ...fullCard(),
        memberId: member.member.id,
        updatedById: member.member.id,
        updatedAt: '2000-01-01T00:00:00.000Z',
        familyId: otherAdmin.family.id,
        allergiesEnc: 'enc:v1:forged',
        notesEnc: 'plaintext',
        _id: UNKNOWN_ID,
        createdAt: '2000-01-01T00:00:00.000Z',
      }),
    );
    assert.equal(card.memberId, admin.member.id);
    assert.equal(card.updatedById, admin.member.id);
    assert.notEqual(card.updatedAt, '2000-01-01T00:00:00.000Z');
    assert.deepEqual(card.allergies, ['Peanuts', 'Penicillin']);

    const raw = await rawCard(admin.member.id);
    assert.equal(String(raw.familyId), admin.family.id);
    assert.notEqual(String(raw._id), UNKNOWN_ID);
    assert.deepEqual(decryptField(raw.allergiesEnc), ['Peanuts', 'Penicillin']);
    assert.equal(decryptField(raw.notesEnc), 'Carries an inhaler in the blue bag.');
    assert.equal(await EmergencyCard.countDocuments({ memberId: member.member.id }), 0);
  });

  it('bumps updatedAt on every save, even when nothing changed', async () => {
    const { admin } = await twoFamilies();
    const first = assertOk(await put(admin.auth, admin.member.id, {}));
    await new Promise((resolve) => setTimeout(resolve, 15));
    const second = assertOk(await put(admin.auth, admin.member.id, {}));
    assert.ok(new Date(second.updatedAt) > new Date(first.updatedAt), `${second.updatedAt} > ${first.updatedAt}`);
  });

  it('concurrent first saves create exactly one card (all requests succeed)', async () => {
    const { admin, member } = await twoFamilies();
    const bodies = [
      { bloodGroup: 'A+' },
      { bloodGroup: 'B+' },
      { bloodGroup: 'O+' },
      { bloodGroup: 'AB+' },
    ];
    const results = await Promise.all(
      bodies.map((body, i) => put(i % 2 ? member.auth : admin.auth, i % 2 ? member.member.id : admin.member.id, body)),
    );
    for (const res of results) assertOk(res);
    assert.equal(await EmergencyCard.countDocuments({ memberId: admin.member.id }), 1);
    assert.equal(await EmergencyCard.countDocuments({ memberId: member.member.id }), 1);
  });

  it('retries once when a racing first save wins the unique memberId index (duplicate key)', async () => {
    const { admin } = await twoFamilies();
    const original = EmergencyCard.findOneAndUpdate;
    let calls = 0;
    // First upsert: a competing request inserted the card between our "no match" and our insert.
    EmergencyCard.findOneAndUpdate = function racingUpsert(...args) {
      calls += 1;
      if (calls > 1) return original.apply(this, args);
      return EmergencyCard.create({ familyId: admin.family.id, memberId: admin.member.id, bloodGroup: 'A-' }).then(() => {
        throw Object.assign(new Error('E11000 duplicate key error collection: familyhub_test.emergency_cards'), {
          code: 11000,
          keyPattern: { memberId: 1 },
        });
      });
    };
    try {
      const card = assertOk(await put(admin.auth, admin.member.id, fullCard()));
      assert.equal(card.bloodGroup, 'B+');
      assert.deepEqual(card.allergies, ['Peanuts', 'Penicillin']);
    } finally {
      EmergencyCard.findOneAndUpdate = original;
    }
    assert.equal(calls, 2, 'saved on the second attempt');
    assert.equal(await EmergencyCard.countDocuments({ memberId: admin.member.id }), 1);
    assert.deepEqual(await storedFields(admin.auth, admin.member.id), fullCard());
  });

  it('removes the card again (404) when the member is deleted while the save is in flight', async () => {
    const { admin, child } = await twoFamilies();
    const restore = holdFirstCardCall({ before: () => Member.deleteOne({ _id: child.id }) });
    try {
      assertError(await put(admin.auth, child.id, fullCard()), 404, 'NOT_FOUND');
    } finally {
      restore();
    }
    assert.equal(await EmergencyCard.countDocuments(), 0, 'no orphaned health data');
  });

  // ---- permission matrix

  it('admin may edit any member of the family (member with account and managed profile)', async () => {
    const { admin, member, child } = await twoFamilies();
    const membersCard = assertOk(await put(admin.auth, member.member.id, { bloodGroup: 'A-' }));
    assert.equal(membersCard.memberId, member.member.id);
    assert.equal(membersCard.updatedById, admin.member.id);

    const childsCard = assertOk(await put(admin.auth, child.id, { bloodGroup: 'O+', allergies: ['Milk'] }));
    assert.equal(childsCard.memberId, child.id);
    assert.equal(childsCard.updatedById, admin.member.id);

    // The member sees who last edited their card.
    assert.equal(assertOk(await get(member.auth, member.member.id)).updatedById, admin.member.id);
  });

  it('a non-admin may edit only their own card (403 for others and managed profiles, nothing stored)', async () => {
    const { admin, member, child } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));

    assertError(await put(member.auth, admin.member.id, { bloodGroup: 'O-' }), 403, 'FORBIDDEN');
    assertError(await put(member.auth, child.id, { bloodGroup: 'O-' }), 403, 'FORBIDDEN');

    assert.equal(assertOk(await get(admin.auth, admin.member.id)).bloodGroup, 'B+');
    assert.equal(await EmergencyCard.countDocuments({ memberId: child.id }), 0);
    assertOk(await put(member.auth, member.member.id, { bloodGroup: 'O-' }));
  });

  it('a second admin may edit other admins\' cards', async () => {
    const { admin, member } = await twoFamilies();
    await Member.updateOne({ _id: member.member.id }, { role: 'admin' });
    const card = assertOk(await put(member.auth, admin.member.id, { bloodGroup: 'AB-' }));
    assert.equal(card.updatedById, member.member.id);
  });

  it('a member demoted from admin loses edit rights immediately', async () => {
    const { admin, member } = await twoFamilies();
    await Member.updateOne({ _id: member.member.id }, { role: 'admin' });
    assertOk(await put(member.auth, admin.member.id, { bloodGroup: 'AB-' }));
    await Member.updateOne({ _id: member.member.id }, { role: 'member' });
    assertError(await put(member.auth, admin.member.id, { bloodGroup: 'A+' }), 403, 'FORBIDDEN');
  });

  it('404 (not 403) for members of another family — admins and members alike — and nothing changes', async () => {
    const { admin, child, otherAdmin, otherMember } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    assertError(await put(otherAdmin.auth, admin.member.id, { bloodGroup: 'O-' }), 404, 'NOT_FOUND');
    assertError(await put(otherMember.auth, admin.member.id, { bloodGroup: 'O-' }), 404, 'NOT_FOUND');
    assertError(await put(otherAdmin.auth, child.id, { bloodGroup: 'O-' }), 404, 'NOT_FOUND');
    assertError(await put(otherAdmin.auth, UNKNOWN_ID, { bloodGroup: 'O-' }), 404, 'NOT_FOUND');
    assertError(await put(admin.auth, UNKNOWN_ID, { bloodGroup: 'O-' }), 404, 'NOT_FOUND');

    assert.equal(assertOk(await get(admin.auth, admin.member.id)).bloodGroup, 'B+');
    assert.equal(await EmergencyCard.countDocuments(), 1);
  });

  it('404 when the target member was removed from the family', async () => {
    const { admin, child } = await twoFamilies();
    await Member.deleteOne({ _id: child.id });
    assertError(await put(admin.auth, child.id, fullCard()), 404, 'NOT_FOUND');
    assert.equal(await EmergencyCard.countDocuments(), 0);
  });

  it('401 without a token, 403 NO_FAMILY without a family', async () => {
    const { admin, member } = await twoFamilies();
    assertError(await request.put(cardUrl(admin.member.id)).send(fullCard()), 401, 'UNAUTHORIZED');
    await User.updateOne({ _id: member.user.id }, { familyId: null, memberId: null });
    assertError(await put(member.auth, member.member.id, fullCard()), 403, 'NO_FAMILY');
  });

  it('400 BAD_REQUEST for a malformed member id or malformed JSON', async () => {
    const { admin } = await twoFamilies();
    assertError(await put(admin.auth, 'nope', fullCard()), 400, 'BAD_REQUEST');
    const res = await request
      .put(cardUrl(admin.member.id))
      .set(admin.auth)
      .set('Content-Type', 'application/json')
      .send('{"bloodGroup": "A+",');
    assertError(res, 400, 'BAD_REQUEST');
  });

  // ---- validation (422 + details)

  it('rejects an invalid blood group', async () => {
    const { admin } = await twoFamilies();
    for (const bloodGroup of ['C+', 'A', 'A++', 'positive', 7, true, ['A+']]) {
      assertValidation(await put(admin.auth, admin.member.id, { bloodGroup }), 'bloodGroup');
    }
  });

  for (const list of LIST_FIELDS) {
    it(`${list}: ≤ 20 items × 80 chars (boundaries accepted, one over rejected)`, async () => {
      const { admin } = await twoFamilies();
      const twenty = Array.from({ length: 20 }, (_, i) => `${String(i).padStart(2, '0')}${'x'.repeat(78)}`);
      assert.equal(twenty[0].length, 80);
      const card = assertOk(await put(admin.auth, admin.member.id, { [list]: twenty }));
      assert.deepEqual(card[list], twenty);

      assertValidation(await put(admin.auth, admin.member.id, { [list]: [...twenty, 'one more'] }), list);
      assertValidation(await put(admin.auth, admin.member.id, { [list]: ['ok', 'y'.repeat(81)] }), `${list}.1`);
      assertValidation(await put(admin.auth, admin.member.id, { [list]: ['ok', 42] }), `${list}.1`);
      assertValidation(await put(admin.auth, admin.member.id, { [list]: [null] }), `${list}.0`);
      assertValidation(await put(admin.auth, admin.member.id, { [list]: 'Peanuts' }), list);
      assertValidation(await put(admin.auth, admin.member.id, { [list]: { 0: 'Peanuts' } }), list);

      // Rejected requests leave the stored card untouched.
      assert.deepEqual(assertOk(await get(admin.auth, admin.member.id))[list], twenty);
    });
  }

  it('an item is measured after trimming (80 chars + surrounding spaces is fine)', async () => {
    const { admin } = await twoFamilies();
    const item = 'z'.repeat(80);
    const card = assertOk(await put(admin.auth, admin.member.id, { allergies: [`   ${item}   `] }));
    assert.deepEqual(card.allergies, [item]);
  });

  it('blank and duplicate items do not count towards the 20-item limit', async () => {
    const { admin } = await twoFamilies();
    const items = [...Array.from({ length: 20 }, (_, i) => `Item ${i}`), '', '  ', 'item 0', 'ITEM 1'];
    const card = assertOk(await put(admin.auth, admin.member.id, { allergies: items }));
    assert.equal(card.allergies.length, 20);
  });

  it('emergencyContacts: ≤ 5, name required, phone validated', async () => {
    const { admin } = await twoFamilies();
    const contact = (i) => ({ name: `Contact ${i}`, phone: `+9198765432${i}0`, relation: 'Friend' });
    const five = Array.from({ length: 5 }, (_, i) => contact(i));
    assert.equal(assertOk(await put(admin.auth, admin.member.id, { emergencyContacts: five })).emergencyContacts.length, 5);

    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [...five, contact(5)] }), 'emergencyContacts');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ phone: '+919876543210' }] }), 'emergencyContacts.0.name');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ name: '   ' }] }), 'emergencyContacts.0.name');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ name: 'x'.repeat(101) }] }), 'emergencyContacts.0.name');
    assertValidation(
      await put(admin.auth, admin.member.id, { emergencyContacts: [contact(1), { name: 'Bad', phone: '12345' }] }),
      'emergencyContacts.1.phone',
    );
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ name: 'Bad', phone: 'call me' }] }), 'emergencyContacts.0.phone');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ name: 'Bad', phone: '+1234567890123456' }] }), 'emergencyContacts.0.phone');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ name: 'Ok', relation: 'r'.repeat(61) }] }), 'emergencyContacts.0.relation');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: ['Ravi'] }), 'emergencyContacts.0');
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: { name: 'Ravi' } }), 'emergencyContacts');

    // Boundaries: 100-char name, 60-char relation, 6- and 15-digit phones.
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        emergencyContacts: [
          { name: 'n'.repeat(100), phone: '123456', relation: 'r'.repeat(60) },
          { name: 'Long', phone: '+123456789012345' },
        ],
      }),
    );
    assert.equal(card.emergencyContacts[0].name.length, 100);
    assert.equal(card.emergencyContacts[1].phone, '+123456789012345');
  });

  it('doctorPhone is validated', async () => {
    const { admin } = await twoFamilies();
    for (const doctorPhone of ['abc', '123', '+91 98765 43210 ext 5', 9876543210]) {
      assertValidation(await put(admin.auth, admin.member.id, { doctorPhone }), 'doctorPhone');
    }
    assert.equal(assertOk(await put(admin.auth, admin.member.id, { doctorPhone: '080-2345 6789' })).doctorPhone, '08023456789');
  });

  it('notes ≤ 500, other text fields ≤ backstop limits', async () => {
    const { admin } = await twoFamilies();
    assert.equal(assertOk(await put(admin.auth, admin.member.id, { notes: 'n'.repeat(500) })).notes.length, 500);
    assertValidation(await put(admin.auth, admin.member.id, { notes: 'n'.repeat(501) }), 'notes');
    assertValidation(await put(admin.auth, admin.member.id, { doctorName: 'd'.repeat(101) }), 'doctorName');
    assertValidation(await put(admin.auth, admin.member.id, { insuranceProvider: 'i'.repeat(101) }), 'insuranceProvider');
    assertValidation(await put(admin.auth, admin.member.id, { insurancePolicyNumber: 'p'.repeat(101) }), 'insurancePolicyNumber');
    assertValidation(await put(admin.auth, admin.member.id, { notes: 42 }), 'notes');
    assertValidation(await put(admin.auth, admin.member.id, { doctorName: { first: 'Dr' } }), 'doctorName');
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        doctorName: 'd'.repeat(100),
        insuranceProvider: 'i'.repeat(100),
        insurancePolicyNumber: 'p'.repeat(100),
      }),
    );
    assert.equal(card.doctorName.length, 100);
    assert.equal(card.insurancePolicyNumber.length, 100);
  });

  it('reports every invalid field at once', async () => {
    const { admin } = await twoFamilies();
    const details = assertValidation(
      await put(admin.auth, admin.member.id, {
        bloodGroup: 'Z',
        allergies: Array(21).fill('a').map((a, i) => `${a}${i}`),
        doctorPhone: 'nope',
        emergencyContacts: [{ name: '' }],
        notes: 'n'.repeat(501),
      }),
      'bloodGroup',
      'allergies',
      'doctorPhone',
      'emergencyContacts.0.name',
      'notes',
    );
    assert.equal(Object.keys(details).length, 5);
    assert.equal(await EmergencyCard.countDocuments(), 0);
  });

  it('a body that is not an object → 422', async () => {
    const { admin } = await twoFamilies();
    const res = await request.put(cardUrl(admin.member.id)).set(admin.auth).set('Content-Type', 'application/json').send('[]');
    assertValidation(res, 'body');
  });
});

// ---------------------------------------------------------------- adversarial hardening

describe('PUT /family/members/:memberId/emergency-card: hardening', () => {
  // ---- data loss / integrity

  it('a PUT without a JSON body is rejected (422) and never wipes the card', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const attempts = [
      ['no body at all', () => request.put(cardUrl(admin.member.id)).set(admin.auth)],
      ['empty JSON body', () => putRaw(admin.auth, admin.member.id, '')],
      [
        'JSON sent as text/plain',
        () => request.put(cardUrl(admin.member.id)).set(admin.auth).set('Content-Type', 'text/plain').send(JSON.stringify(fullCard())),
      ],
      ['form-encoded body', () => request.put(cardUrl(admin.member.id)).set(admin.auth).type('form').send({ bloodGroup: 'A+' })],
    ];
    for (const [label, send] of attempts) {
      const details = assertValidation(await send(), 'body');
      assert.equal(Object.keys(details).length, 1, label);
      assert.deepEqual(await storedFields(admin.auth, admin.member.id), fullCard(), `${label} must leave the card untouched`);
    }
    // An explicit `{}` is still the documented way to clear the card.
    assertOk(await putRaw(admin.auth, admin.member.id, '{}'));
    assert.deepEqual(await storedFields(admin.auth, admin.member.id), asStored({}));
  });

  it('the missing-body check keeps the documented error order (401 → 403 NO_FAMILY → 400 id → 422 body)', async () => {
    const { member } = await twoFamilies();
    assertError(await request.put(cardUrl(member.member.id)), 401, 'UNAUTHORIZED');
    assertError(await request.put(cardUrl('nope')).set(member.auth), 400, 'BAD_REQUEST');
    await User.updateOne({ _id: member.user.id }, { familyId: null, memberId: null });
    assertError(await request.put(cardUrl(member.member.id)).set(member.auth), 403, 'NO_FAMILY');
  });

  it('two racing PUTs never leave a mix of both cards (the whole card is replaced atomically)', async () => {
    const { admin, member } = await twoFamilies();
    await Member.updateOne({ _id: member.member.id }, { role: 'admin' });
    const original = { bloodGroup: 'B+', allergies: ['Original'], doctorName: 'Dr. Rao', notes: 'Original notes' };
    // A keeps blood group + doctor from the original card; B changes everything.
    const bodyA = { bloodGroup: 'B+', allergies: ['From A'], doctorName: 'Dr. Rao', notes: 'Notes from A' };
    const bodyB = { bloodGroup: 'O-', allergies: ['From B'], doctorName: 'Dr. B', notes: 'Notes from B' };
    assertOk(await put(admin.auth, admin.member.id, original));

    // B runs completely inside A's read→write window (or right after A's atomic write).
    const restore = holdFirstCardCall({ between: async () => assertOk(await put(member.auth, admin.member.id, bodyB)) });
    try {
      assertOk(await put(admin.auth, admin.member.id, bodyA));
    } finally {
      restore();
    }
    const stored = await storedFields(admin.auth, admin.member.id);
    const isA = isDeepStrictEqual(stored, asStored(bodyA));
    const isB = isDeepStrictEqual(stored, asStored(bodyB));
    assert.ok(isA || isB, `torn card: ${JSON.stringify(stored)}`);
    assert.equal(await EmergencyCard.countDocuments({ memberId: admin.member.id }), 1);
  });

  it('many concurrent full-card PUTs on an existing card: the result is exactly one of the bodies', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const bodies = Array.from({ length: 8 }, (_, i) => ({
      ...fullCard(),
      bloodGroup: i % 2 ? 'A+' : 'B+', // half of them keep the stored blood group
      allergies: [`Allergy ${i}`],
      doctorName: i % 3 ? 'Dr. Rao' : `Dr. ${i}`,
      notes: `Notes ${i}`,
    }));
    for (const res of await Promise.all(bodies.map((body) => put(admin.auth, admin.member.id, body)))) assertOk(res);
    const stored = await storedFields(admin.auth, admin.member.id);
    assert.ok(bodies.some((body) => isDeepStrictEqual(stored, asStored(body))), `torn card: ${JSON.stringify(stored)}`);
  });

  // ---- injection / mass assignment

  it('NoSQL operator objects are rejected in every field (422, nothing stored)', async () => {
    const { admin } = await twoFamilies();
    const details = assertValidation(
      await put(admin.auth, admin.member.id, {
        bloodGroup: { $ne: null },
        allergies: { $exists: true },
        medications: [{ $gt: '' }],
        doctorName: { $regex: '.*' },
        doctorPhone: { $ne: null },
        insurancePolicyNumber: { $where: 'sleep(1000)' },
        emergencyContacts: [{ name: { $ne: null }, phone: { $gt: '' } }],
        notes: { $set: { familyId: UNKNOWN_ID } },
      }),
      'bloodGroup',
      'allergies',
      'medications.0',
      'doctorName',
      'doctorPhone',
      'insurancePolicyNumber',
      'emergencyContacts.0.name',
      'emergencyContacts.0.phone',
      'notes',
    );
    assert.equal(Object.keys(details).length, 9);
    assert.equal(await EmergencyCard.countDocuments(), 0);
  });

  it('operator-shaped ids and query strings cannot widen the family scope', async () => {
    const { admin, otherAdmin } = await twoFamilies();
    assertOk(await put(otherAdmin.auth, otherAdmin.member.id, fullCard()));
    const operatorId = encodeURIComponent('{"$ne":null}');
    assertError(await request.get(`${API}/family/members/${operatorId}/emergency-card`).set(admin.auth), 400, 'BAD_REQUEST');
    assertError(await request.put(`${API}/family/members/${operatorId}/emergency-card`).set(admin.auth).send({}), 400, 'BAD_REQUEST');
    // Query parameters are ignored: the caller's own family always scopes the lookup.
    const sneaky = `?familyId=${otherAdmin.family.id}&memberId[$ne]=x&familyId[$ne]=x`;
    assertError(await request.get(`${cardUrl(otherAdmin.member.id)}${sneaky}`).set(admin.auth), 404, 'NOT_FOUND');
    assertError(await request.put(`${cardUrl(otherAdmin.member.id)}${sneaky}`).set(admin.auth).send({}), 404, 'NOT_FOUND');
    assertEmptyCard(assertOk(await request.get(`${cardUrl(admin.member.id)}${sneaky}`).set(admin.auth)), admin.member.id);
    assert.deepEqual(await storedFields(otherAdmin.auth, otherAdmin.member.id), fullCard());
  });

  it('__proto__ / constructor keys neither pollute prototypes nor reach the card', async () => {
    const { admin, otherAdmin } = await twoFamilies();
    const raw = JSON.stringify({ bloodGroup: 'A+' }).replace(
      /^\{/,
      `{"__proto__":{"polluted":true,"allergies":["Injected"],"familyId":"${otherAdmin.family.id}","role":"admin"},` +
        '"constructor":{"prototype":{"polluted":true}},',
    );
    const card = assertOk(await putRaw(admin.auth, admin.member.id, raw));
    assert.equal(card.bloodGroup, 'A+');
    assert.deepEqual(card.allergies, []);
    assert.equal({}.polluted, undefined);
    assert.equal(Object.prototype.polluted, undefined);
    const stored = await rawCard(admin.member.id);
    assert.equal(String(stored.familyId), admin.family.id);
    assert.ok(!('polluted' in stored) && !('role' in stored));
    assert.ok(!Object.keys(stored).includes('constructor') && !Object.keys(stored).includes('__proto__'));
  });

  it('extra keys inside emergency contacts are stripped (response and raw document)', async () => {
    const { admin } = await twoFamilies();
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        emergencyContacts: [
          { name: 'Ravi', phone: '+919812345678', relation: 'Uncle', _id: UNKNOWN_ID, familyId: UNKNOWN_ID, isAdmin: true, email: 'r@x.io' },
        ],
      }),
    );
    assert.deepEqual(card.emergencyContacts, [{ name: 'Ravi', phone: '+919812345678', relation: 'Uncle' }]);
    const stored = await rawCard(admin.member.id);
    assert.deepEqual(Object.keys(stored.emergencyContacts[0]).sort(), ['name', 'phone', 'relation']);
  });

  it('non-string scalars are rejected, never coerced (0, negative, 1e13, 0.1+0.2, booleans, objects)', async () => {
    const { admin } = await twoFamilies();
    for (const value of [0, -1, 1e13, 0.1 + 0.2, true, false, {}]) {
      assertValidation(
        await put(admin.auth, admin.member.id, {
          bloodGroup: value,
          allergies: [value],
          medications: value,
          doctorName: value,
          doctorPhone: value,
          insuranceProvider: value,
          insurancePolicyNumber: value,
          emergencyContacts: [{ name: value, phone: value, relation: value }],
          notes: value,
        }),
        'bloodGroup',
        'allergies.0',
        'medications',
        'doctorName',
        'doctorPhone',
        'insuranceProvider',
        'insurancePolicyNumber',
        'emergencyContacts.0.name',
        'emergencyContacts.0.phone',
        'emergencyContacts.0.relation',
        'notes',
      );
    }
    for (const doctorPhone of ['NaN', 'Infinity', '-1', '1e13', '0.30000000000000004']) {
      assertValidation(await put(admin.auth, admin.member.id, { doctorPhone }), 'doctorPhone');
    }
    assert.equal(await EmergencyCard.countDocuments(), 0);
  });

  // ---- payload size

  it('huge lists are rejected before each item is validated (bounded 422 details)', async () => {
    const { admin } = await twoFamilies();
    const tooLong = Array(1000).fill('y'.repeat(81));
    const details = assertValidation(
      await put(admin.auth, admin.member.id, {
        allergies: tooLong,
        medications: Array(1000).fill(7),
        emergencyContacts: Array(500).fill({ name: '' }),
      }),
      'allergies',
      'medications',
      'emergencyContacts',
    );
    assert.deepEqual(Object.keys(details).sort(), ['allergies', 'emergencyContacts', 'medications']);
    // 30 000 blank items used to be accepted and silently dropped; now they are too many.
    assertValidation(await put(admin.auth, admin.member.id, { conditions: Array(30000).fill('') }), 'conditions');
    // Within the raw bound, blank / duplicate items are still cleaned up before the 20-item limit.
    const card = assertOk(await put(admin.auth, admin.member.id, { allergies: [...Array(80).fill('Dust'), 'Pollen'] }));
    assert.deepEqual(card.allergies, ['Dust', 'Pollen']);
    assert.equal(await EmergencyCard.countDocuments(), 1);
  });

  it('a body over the 100 kb limit → 413 PAYLOAD_TOO_LARGE, card untouched', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    assertError(await put(admin.auth, admin.member.id, { ...fullCard(), notes: 'n'.repeat(101 * 1024) }), 413, 'PAYLOAD_TOO_LARGE');
    assert.deepEqual(await storedFields(admin.auth, admin.member.id), fullCard());
  });

  it('deeply nested junk under an unknown key is ignored without crashing', async () => {
    const { admin } = await twoFamilies();
    const deep = `${'['.repeat(20000)}${']'.repeat(20000)}`;
    const card = assertOk(await putRaw(admin.auth, admin.member.id, `{"bloodGroup":"O+","junk":${deep}}`));
    assert.equal(card.bloodGroup, 'O+');
    assert.ok(!('junk' in (await rawCard(admin.member.id))));
  });

  // ---- unicode

  it('rejects malformed UTF-16 (lone surrogates) instead of storing U+FFFD', async () => {
    const { admin } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    assertValidation(
      await put(admin.auth, admin.member.id, {
        doctorName: 'Dr \ud800 Rao',
        allergies: ['Pea\udc00nuts'],
        emergencyContacts: [{ name: 'Ravi \ud83d' }],
        notes: 'broken \udfff',
      }),
      'doctorName',
      'allergies.0',
      'emergencyContacts.0.name',
      'notes',
    );
    assert.deepEqual(await storedFields(admin.auth, admin.member.id), fullCard());
  });

  it('strips control and bidi-override characters; line breaks become spaces except in notes', async () => {
    const { admin } = await twoFamilies();
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        doctorName: 'Dr.\nRao\tSr\u0000',
        insuranceProvider: 'Star\u202E Health\u202C',
        insurancePolicyNumber: '\u2066P-123\u2069',
        allergies: ['Metformin\r\n500mg', 'Pea\u0007nuts'],
        emergencyContacts: [{ name: 'Ravi\u001b[31m', relation: 'Un\u0085cle' }],
        notes: 'Line 1\r\nLine 2\rLine 3\u2028Line 4\u0000\tindented\u202E',
      }),
    );
    assert.equal(card.doctorName, 'Dr. Rao Sr');
    assert.equal(card.insuranceProvider, 'Star Health');
    assert.equal(card.insurancePolicyNumber, 'P-123');
    assert.deepEqual(card.allergies, ['Metformin 500mg', 'Peanuts']);
    assert.deepEqual(card.emergencyContacts, [{ name: 'Ravi[31m', phone: null, relation: 'Un cle' }]);
    assert.equal(card.notes, 'Line 1\nLine 2\nLine 3\nLine 4\tindented');
    // What was stored is what was returned.
    const { memberId: _m, updatedAt: _u, updatedById: _b, ...returned } = card;
    assert.deepEqual(await storedFields(admin.auth, admin.member.id), returned);
  });

  it('text that only looks blank (zero-width / filler characters) counts as blank', async () => {
    const { admin } = await twoFamilies();
    const card = assertOk(
      await put(admin.auth, admin.member.id, {
        allergies: ['\u200B', '\u2060\uFEFF', ' \u200B\u200C ', '\u3164', '\u2800', 'Dust'],
        doctorName: '\u200B\u200B',
        insuranceProvider: '\u115F\u1160',
        notes: '\u200D\n\u200B',
      }),
    );
    assert.deepEqual(card.allergies, ['Dust']);
    assert.equal(card.doctorName, null);
    assert.equal(card.insuranceProvider, null);
    assert.equal(card.notes, null);
    assertValidation(await put(admin.auth, admin.member.id, { emergencyContacts: [{ name: '\u200B\u2060' }] }), 'emergencyContacts.0.name');
  });

  it('keeps ZWJ / ZWNJ and RTL marks inside real text (emoji sequences, Indic and Persian scripts)', async () => {
    const { admin } = await twoFamilies();
    const body = {
      allergies: ['👨\u200D👩\u200D👧 family pack', 'क्\u200Dष', 'می\u200Cخواهم', '\u200Fحساسية\u200F'],
      notes: 'يحمل جهاز استنشاق \u2014 नीले बैग में 🫁',
      emergencyContacts: [{ name: 'רבקה', relation: 'אמא' }],
    };
    const card = assertOk(await put(admin.auth, admin.member.id, body));
    assert.deepEqual(card.allergies, body.allergies);
    assert.equal(card.notes, body.notes);
    assert.deepEqual(await storedFields(admin.auth, admin.member.id), asStored({ ...body, emergencyContacts: [{ name: 'רבקה', phone: null, relation: 'אמא' }] }));
  });

  it('stores text in NFC so the same word typed on different keyboards is equal', async () => {
    const { admin } = await twoFamilies();
    const decomposed = 'Cafe\u0301 au lait';
    const card = assertOk(await put(admin.auth, admin.member.id, { allergies: [decomposed, 'Caf\u00E9 au lait'], doctorName: 'Dr. Mu\u0308ller' }));
    assert.deepEqual(card.allergies, ['Caf\u00E9 au lait']);
    assert.equal(card.doctorName, 'Dr. M\u00FCller');
    assert.deepEqual(decryptField((await rawCard(admin.member.id)).allergiesEnc), ['Caf\u00E9 au lait']);
  });

  it('lengths are UTF-16 code units like the app (40 emoji = 80 fits, 41 does not)', async () => {
    const { admin } = await twoFamilies();
    assert.deepEqual(assertOk(await put(admin.auth, admin.member.id, { allergies: ['🥜'.repeat(40)] })).allergies, ['🥜'.repeat(40)]);
    assertValidation(await put(admin.auth, admin.member.id, { allergies: ['🥜'.repeat(41)] }), 'allergies.0');
  });

  it('plaintext fields use the same unit as the model backstop (no Mongoose error echoing the value)', async () => {
    const { admin } = await twoFamilies();
    // 51 emoji = 51 code points (zod's own count) but 102 UTF-16 units (Mongoose `maxlength`).
    const emoji = '🩺'.repeat(51);
    const details = assertValidation(
      await put(admin.auth, admin.member.id, {
        doctorName: emoji,
        insuranceProvider: emoji,
        emergencyContacts: [{ name: emoji, relation: '👪'.repeat(31) }],
      }),
      'doctorName',
      'insuranceProvider',
      'emergencyContacts.0.name',
      'emergencyContacts.0.relation',
    );
    for (const message of Object.values(details)) {
      assert.match(message, /^At most \d+ characters$/);
      assert.ok(!message.includes('🩺') && !message.includes('👪'), 'the value is never echoed');
    }
    const card = assertOk(await put(admin.auth, admin.member.id, { doctorName: '🩺'.repeat(50) }));
    assert.equal(card.doctorName, '🩺'.repeat(50));
  });

  it('blood group accepts typographic minus / dashes and full-width characters', async () => {
    const { admin } = await twoFamilies();
    for (const [input, expected] of [
      ['ab\u2212', 'AB-'],
      ['B\u2013', 'B-'],
      ['\uFF2F\uFF0B', 'O+'],
      ['a \u2010', 'A-'],
    ]) {
      assert.equal(assertOk(await put(admin.auth, admin.member.id, { bloodGroup: input })).bloodGroup, expected, input);
    }
    for (const bloodGroup of ['A\u2212\u2212', 'O\u200B+x']) {
      assertValidation(await put(admin.auth, admin.member.id, { bloodGroup }), 'bloodGroup');
    }
  });

  // ---- deleted members referenced

  it('a card last edited by a member who was later removed still reads fine', async () => {
    const { admin, member, child } = await twoFamilies();
    await Member.updateOne({ _id: member.member.id }, { role: 'admin' });
    assertOk(await put(member.auth, child.id, fullCard()));
    await Member.deleteOne({ _id: member.member.id });
    const card = assertOk(await get(admin.auth, child.id));
    assert.equal(card.updatedById, member.member.id);
    assert.deepEqual(card.allergies, fullCard().allergies);
    // The removed member's token no longer grants access.
    assertError(await get(member.auth, child.id), 403, 'NO_FAMILY');
    assertError(await put(member.auth, child.id, fullCard()), 403, 'NO_FAMILY');
  });

  it('responses never contain ciphertext, internal ids or other families\' data', async () => {
    const { admin, otherAdmin } = await twoFamilies();
    assertOk(await put(otherAdmin.auth, otherAdmin.member.id, { ...fullCard(), notes: 'Other family secret' }));
    const res = await put(admin.auth, admin.member.id, fullCard());
    const body = JSON.stringify(res.body) + JSON.stringify((await get(admin.auth, admin.member.id)).body);
    for (const leak of ['enc:v1:', 'Enc"', '"_id"', '"__v"', '"familyId"', otherAdmin.family.id, 'Other family secret']) {
      assert.ok(!body.includes(leak), `${leak} leaked`);
    }
  });
});

// ---------------------------------------------------------------- helpers for other modules

describe('emergencyCards.service helpers', () => {
  it('plainCardFor returns the decrypted card or the empty card', async () => {
    const { admin } = await twoFamilies();
    assertEmptyCard(await plainCardFor(admin.family.id, admin.member.id), admin.member.id);
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    const card = await plainCardFor(admin.family.id, admin.member.id);
    assert.deepEqual(card.allergies, ['Peanuts', 'Penicillin']);
    assert.match(card.updatedAt, ISO);
    assert.match(card.updatedById, OBJECT_ID);
    // Family scoping: the same member id under another family id yields the empty card.
    assertEmptyCard(await plainCardFor(UNKNOWN_ID, admin.member.id), admin.member.id);
    await assert.rejects(plainCardFor('bad', admin.member.id), { code: 'NOT_FOUND' });
  });

  it('deleteCardForMember removes only that member\'s card and is idempotent', async () => {
    const { admin, member } = await twoFamilies();
    assertOk(await put(admin.auth, admin.member.id, fullCard()));
    assertOk(await put(member.auth, member.member.id, fullCard()));
    assert.equal(await deleteCardForMember(admin.family.id, member.member.id), 1);
    assert.equal(await deleteCardForMember(admin.family.id, member.member.id), 0);
    assert.equal(await deleteCardForMember('bad', member.member.id), 0);
    assert.equal(await EmergencyCard.countDocuments(), 1);
    assertEmptyCard(assertOk(await get(member.auth, member.member.id)), member.member.id);
  });
});
