import { connectDb, disconnectDb } from '../src/config/db.js';
import { env } from '../src/config/env.js';
import {
  User,
  Family,
  Member,
  Task,
  LedgerEntry,
  Goal,
  Notice,
  initModels,
} from '../src/models/index.js';
import { hashPassword } from '../src/modules/auth/auth.passwords.js';

export async function seed({ mongoUri } = {}) {
  const uri = mongoUri || env.MONGODB_URI;
  console.log(`[seed] Connecting to database: ${uri.replace(/\/\/([^:]+):([^@]+)@/, '//$1:****@')}`);
  await connectDb(uri);
  await initModels();

  console.log('[seed] Clearing existing demo data...');
  await Promise.all([
    User.deleteMany({}),
    Family.deleteMany({}),
    Member.deleteMany({}),
    Task.deleteMany({}),
    LedgerEntry.deleteMany({}),
    Goal.deleteMany({}),
    Notice.deleteMany({}),
  ]);

  console.log('[seed] Creating Users...');
  const passHash = await hashPassword('Password123!');

  const adminUser = await User.create({
    email: 'admin@familyhub.app',
    passwordHash: passHash,
    name: 'Rajesh Sharma',
    locale: 'en',
    emailVerified: true,
  });

  const memberUser = await User.create({
    email: 'alex@familyhub.app',
    passwordHash: passHash,
    name: 'Alex Sharma',
    locale: 'en',
    emailVerified: true,
  });

  console.log('[seed] Creating Family & Members...');
  const family = await Family.create({
    name: 'Sharma Family',
    country: 'IN',
    currency: 'INR',
    timezone: 'Asia/Kolkata',
    ownerId: adminUser._id,
  });

  const adminMember = await Member.create({
    familyId: family._id,
    userId: adminUser._id,
    name: 'Rajesh Sharma',
    role: 'admin',
    dateOfBirth: new Date('1985-06-15'),
    locationSharing: 'always',
  });

  const alexMember = await Member.create({
    familyId: family._id,
    userId: memberUser._id,
    name: 'Alex Sharma',
    role: 'member',
    dateOfBirth: new Date('2010-04-20'),
    locationSharing: 'sos_only',
  });

  const grandmaMember = await Member.create({
    familyId: family._id,
    name: 'Grandma Priya',
    role: 'member',
    dateOfBirth: new Date('1955-09-10'),
    locationSharing: 'never',
  });

  await User.updateOne({ _id: adminUser._id }, { familyId: family._id, memberId: adminMember._id });
  await User.updateOne({ _id: memberUser._id }, { familyId: family._id, memberId: alexMember._id });

  console.log('[seed] Creating Tasks...');
  const now = new Date();
  const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const nextWeek = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

  await Task.create([
    {
      familyId: family._id,
      title: 'Buy fresh vegetables and fruits',
      description: 'Get tomatoes, spinach, and apples from the market',
      assigneeId: alexMember._id,
      createdById: adminMember._id,
      dueDate: tomorrow,
      status: 'pending',
    },
    {
      familyId: family._id,
      title: 'Complete Math Homework Chapter 5',
      description: 'Algebra practice problems 1 to 20',
      assigneeId: alexMember._id,
      createdById: adminMember._id,
      dueDate: nextWeek,
      status: 'pending',
    },
    {
      familyId: family._id,
      title: 'Water the plants on the balcony',
      assigneeId: alexMember._id,
      createdById: adminMember._id,
      dueDate: now,
      status: 'done',
      completedAt: now,
      completedById: alexMember._id,
    },
  ]);

  console.log('[seed] Creating Ledger Entries...');
  await LedgerEntry.create([
    {
      familyId: family._id,
      createdById: adminMember._id,
      memberId: adminMember._id,
      memberName: adminMember.name,
      type: 'income',
      amountMinor: 8500000,
      category: 'salary',
      note: 'Monthly Salary',
      date: new Date(now.getFullYear(), now.getMonth(), 1),
    },
    {
      familyId: family._id,
      createdById: adminMember._id,
      memberId: adminMember._id,
      memberName: adminMember.name,
      type: 'expense',
      amountMinor: 450000,
      category: 'groceries',
      note: 'Supermarket Groceries',
      date: new Date(now.getFullYear(), now.getMonth(), 5),
    },
    {
      familyId: family._id,
      createdById: adminMember._id,
      memberId: adminMember._id,
      memberName: adminMember.name,
      type: 'expense',
      amountMinor: 210000,
      category: 'utilities',
      note: 'Electricity Bill',
      date: new Date(now.getFullYear(), now.getMonth(), 10),
    },
  ]);

  console.log('[seed] Creating Goals...');
  await Goal.create([
    {
      familyId: family._id,
      createdById: adminMember._id,
      title: 'Family Summer Vacation',
      targetMinor: 15000000,
      savedMinor: 6000000,
      targetDate: new Date('2027-06-01'),
    },
    {
      familyId: family._id,
      createdById: adminMember._id,
      title: 'Emergency Savings Fund',
      targetMinor: 50000000,
      savedMinor: 25000000,
    },
  ]);

  console.log('[seed] Creating Notices...');
  await Notice.create([
    {
      familyId: family._id,
      authorId: adminMember._id,
      title: 'Family Sunday Dinner',
      body: 'We are hosting a family dinner this Sunday at 7:00 PM. Everyone please be home!',
      pinned: true,
    },
    {
      familyId: family._id,
      authorId: adminMember._id,
      title: 'Wi-Fi Password Updated',
      body: 'The new home Wi-Fi password is available on the router notice board.',
      pinned: false,
    },
  ]);

  console.log('✅ [seed] Database successfully seeded!');
  console.log('\n--- Demo Accounts Created ---');
  console.log('1. Admin User:   admin@familyhub.app / Password123!');
  console.log('2. Member User:  alex@familyhub.app  / Password123!');
  console.log('-----------------------------\n');
}

// Allow direct execution: `node scripts/seed.js`
if (process.argv[1] && process.argv[1].endsWith('seed.js')) {
  seed()
    .then(async () => {
      await disconnectDb();
      process.exit(0);
    })
    .catch(async (err) => {
      console.error('❌ [seed] Failed:', err);
      await disconnectDb();
      process.exit(1);
    });
}
