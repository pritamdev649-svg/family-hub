import { connectDb, disconnectDb } from '../src/config/db.js';
import { env } from '../src/config/env.js';
import { User, Family, Member, initModels } from '../src/models/index.js';
import { hashPassword } from '../src/modules/auth/auth.passwords.js';

async function createPlayConsoleAccount() {
  const uri = env.MONGODB_URI;
  console.log(`Connecting to database...`);
  await connectDb(uri);
  await initModels();

  const email = 'googleplay@familyhub.com';
  const password = 'TestPassword123!';

  console.log(`Checking if user ${email} exists...`);
  let user = await User.findOne({ email });
  if (user) {
    console.log(`User ${email} already exists! Replacing password...`);
    user.passwordHash = await hashPassword(password);
    await user.save();
    console.log(`Updated password for ${email}.`);
  } else {
    console.log(`Creating user ${email}...`);
    const passHash = await hashPassword(password);
    user = await User.create({
      email,
      passwordHash: passHash,
      name: 'Google Play Reviewer',
      locale: 'en',
      emailVerified: true,
    });
    
    console.log(`Creating Family & Member for the reviewer...`);
    const family = await Family.create({
      name: 'Reviewer Family',
      country: 'US',
      currency: 'USD',
      timezone: 'America/New_York',
      ownerId: user._id,
    });

    const member = await Member.create({
      familyId: family._id,
      userId: user._id,
      name: 'Google Play Reviewer',
      role: 'admin',
      dateOfBirth: new Date('1990-01-01'),
      locationSharing: 'always',
    });

    await User.updateOne({ _id: user._id }, { familyId: family._id, memberId: member._id });
    console.log(`Successfully set up Family and Member records!`);
  }
  
  console.log(`\nAccount ready: ${email} / ${password}\n`);
}

createPlayConsoleAccount()
  .then(async () => {
    await disconnectDb();
    process.exit(0);
  })
  .catch(async (err) => {
    console.error('Failed:', err);
    await disconnectDb();
    process.exit(1);
  });
