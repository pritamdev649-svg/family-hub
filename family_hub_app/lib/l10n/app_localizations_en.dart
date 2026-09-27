// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get authLanguageLabel => 'Language';

  @override
  String get authLanguageSheetTitle => 'Choose your language';

  @override
  String get authWelcomeCreateFamily => 'Create a family';

  @override
  String get authWelcomeJoinFamily => 'Join with invite code';

  @override
  String get authWelcomeHaveAccount => 'I already have an account';

  @override
  String get authWelcomeFeatureTasks => 'Roles and tasks for everyone';

  @override
  String get authWelcomeFeatureMoney => 'A shared ledger and savings goals';

  @override
  String get authWelcomeFeatureSafety => 'SOS alerts and emergency cards';

  @override
  String get authSessionExpiredNotice =>
      'You were signed out. Please log in again.';

  @override
  String get authLoginTitle => 'Log in';

  @override
  String get authLoginSubtitle => 'Welcome back! Sign in to see your family.';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authForgotPasswordLink => 'Forgot password?';

  @override
  String get authLoginButton => 'Log in';

  @override
  String get authLoginNoAccount => 'New to FamilyHub?';

  @override
  String get authCreateAccountLink => 'Create an account';

  @override
  String authLoginLockedOut(String time) {
    return 'Too many failed attempts. Try again in $time.';
  }

  @override
  String authCooldownSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String authCooldownMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get authDemoTitle => 'Demo mode';

  @override
  String authDemoLoginHint(String email, String password) {
    return 'Try the demo family: $email / $password';
  }

  @override
  String get authDemoFill => 'Fill in';

  @override
  String authDemoOtpHint(String code) {
    return 'Demo mode: the code is always $code.';
  }

  @override
  String get authRegisterCreateTitle => 'Create your family';

  @override
  String get authRegisterJoinTitle => 'Join your family';

  @override
  String get authRegisterCreateSubtitle =>
      'Set up your account and your family. You will be its admin.';

  @override
  String get authRegisterJoinSubtitle =>
      'Create your account and join with the invite code a family admin gave you.';

  @override
  String get authModeCreate => 'Create';

  @override
  String get authModeJoin => 'Join';

  @override
  String get authSectionAboutYou => 'About you';

  @override
  String get authSectionFamily => 'Your family';

  @override
  String get authNameLabel => 'Your name';

  @override
  String get authConfirmPasswordLabel => 'Confirm password';

  @override
  String get authPasswordHint =>
      'At least 8 characters with a letter and a number';

  @override
  String get authDateOfBirthLabel => 'Date of birth (optional)';

  @override
  String get authRegisterButton => 'Create account';

  @override
  String get authHaveAccount => 'Already have an account?';

  @override
  String get authLoginLink => 'Log in';

  @override
  String authSignupTooYoung(int age) {
    String _temp0 = intl.Intl.pluralLogic(
      age,
      locale: localeName,
      other:
          'You must be at least $age years old to create your own account in this country. Ask a parent or guardian to add you to the family instead.',
      one:
          'You must be at least 1 year old to create your own account in this country.',
    );
    return '$_temp0';
  }

  @override
  String get authPasswordTooLong =>
      'This password is too long. Please use a shorter one.';

  @override
  String get authNameInvalidCharacters =>
      'Remove line breaks and hidden formatting characters from the name.';

  @override
  String get authNameNeedsLetter =>
      'Enter a name with at least one letter or number.';

  @override
  String get authFieldRejected =>
      'This entry wasn\'t accepted. Please check it and try again.';

  @override
  String authTooManyAttemptsWait(String time) {
    return 'Too many attempts. Try again in $time.';
  }

  @override
  String authConsentAgree(String privacyPolicy, String terms) {
    return 'I have read and agree to the $privacyPolicy and the $terms.';
  }

  @override
  String get authPrivacyPolicy => 'Privacy Policy';

  @override
  String get authTermsOfService => 'Terms of Service';

  @override
  String get authConsentRequired =>
      'Please accept the Privacy Policy and the Terms of Service to continue.';

  @override
  String get authLinkOpenFailed =>
      'Couldn\'t open the link. Please try again later.';

  @override
  String get authFamilyNameLabel => 'Family name';

  @override
  String get authFamilyNameHint => 'e.g. The Sharma Family';

  @override
  String get authCountryLabel => 'Country';

  @override
  String get authCountryPickerTitle => 'Select your country';

  @override
  String get authCountrySearchHint => 'Search by name or code';

  @override
  String get authCountryNoResults => 'No country matches your search.';

  @override
  String get authCurrencyLabel => 'Currency';

  @override
  String get authTimezoneLabel => 'Time zone';

  @override
  String get authFamilyFormHelp =>
      'The currency and time zone are used for the family ledger and due dates. Admins can change them later.';

  @override
  String authSuggestLanguage(String language) {
    return 'Use $language in FamilyHub?';
  }

  @override
  String get authSuggestLanguageAction => 'Switch';

  @override
  String get authInviteCodeLabel => 'Invite code';

  @override
  String get authInviteCodeHint => '8 letters and numbers';

  @override
  String get authInviteCodeHelp =>
      'Ask a family admin for the code. Admins find it in the family settings.';

  @override
  String get authVerifyTitle => 'Verify your email';

  @override
  String authVerifyMessage(String email) {
    return 'We sent a 6-digit code to $email. Enter it below to confirm your email address.';
  }

  @override
  String get authOtpLabel => '6-digit code';

  @override
  String get authVerifyButton => 'Verify email';

  @override
  String get authResendCode => 'Resend code';

  @override
  String authResendCodeIn(String time) {
    return 'Resend code in $time';
  }

  @override
  String get authCodeSent =>
      'A new code is on its way. Check your inbox and spam folder.';

  @override
  String get authEmailVerified => 'Email verified. Welcome to FamilyHub!';

  @override
  String get authUseAnotherAccount => 'Use another account';

  @override
  String get authForgotTitle => 'Reset password';

  @override
  String get authForgotEmailMessage =>
      'Enter the email of your account. We\'ll send you a 6-digit code to set a new password.';

  @override
  String get authSendCode => 'Send code';

  @override
  String authForgotCodeMessage(String email) {
    return 'If an account exists for $email, we sent it a 6-digit code. Enter the code and your new password.';
  }

  @override
  String get authChangeEmail => 'Use a different email';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authConfirmNewPasswordLabel => 'Confirm new password';

  @override
  String get authResetButton => 'Set new password';

  @override
  String get authPasswordResetSuccess =>
      'Your password was changed. Log in with your new password.';

  @override
  String get authFamilySetupTitle => 'Set up your family';

  @override
  String authFamilySetupGreeting(String name) {
    return 'Hi $name! Create a new family or join one with an invite code.';
  }

  @override
  String authSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get authCreateFamilyButton => 'Create family';

  @override
  String get authJoinFamilyButton => 'Join family';

  @override
  String get authLogout => 'Log out';

  @override
  String get authFamilyCreated => 'Your family is ready!';

  @override
  String authFamilyJoined(String family) {
    return 'Welcome to $family!';
  }

  @override
  String get appName => 'FamilyHub';

  @override
  String get appTagline => 'Your family, organised like a great team';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonNext => 'Next';

  @override
  String get commonBack => 'Back';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonNone => 'None';

  @override
  String get commonOptional => 'Optional';

  @override
  String get commonCall => 'Call';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonShare => 'Share';

  @override
  String get commonCamera => 'Camera';

  @override
  String get commonGallery => 'Gallery';

  @override
  String get commonUploading => 'Uploading…';

  @override
  String get commonRemovePhoto => 'Remove photo';

  @override
  String get commonChoosePhoto => 'Choose photo';

  @override
  String get commonOffline => 'You\'re offline. Showing the last saved data.';

  @override
  String get commonToday => 'Today';

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String get commonTomorrow => 'Tomorrow';

  @override
  String get commonSomethingWentWrong => 'Something went wrong';

  @override
  String get commonNothingHere => 'Nothing here yet';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonSelectDate => 'Select date';

  @override
  String get commonAll => 'All';

  @override
  String get commonJustNow => 'Just now';

  @override
  String commonMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String commonHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String commonDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get commonAdminOnly => 'Only family admins can do this';

  @override
  String get commonSaved => 'Saved';

  @override
  String get commonDeleted => 'Deleted';

  @override
  String get commonAreYouSure => 'Are you sure?';

  @override
  String get commonMe => 'Me';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonSend => 'Send';

  @override
  String get commonSubmit => 'Submit';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonView => 'View';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonNotSet => 'Not set';

  @override
  String get commonShowPassword => 'Show password';

  @override
  String get commonHidePassword => 'Hide password';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get commonDiscardChangesTitle => 'Discard changes?';

  @override
  String get commonDiscardChangesMessage =>
      'Your unsaved changes will be lost.';

  @override
  String get commonTryAgainLater => 'Please try again in a moment.';

  @override
  String dashboardGreeting(String period, String name) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'morning': 'Good morning, $name',
      'afternoon': 'Good afternoon, $name',
      'evening': 'Good evening, $name',
      'other': 'Hello, $name',
    });
    return '$_temp0';
  }

  @override
  String dashboardGreetingNoName(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'morning': 'Good morning',
      'afternoon': 'Good afternoon',
      'evening': 'Good evening',
      'other': 'Hello',
    });
    return '$_temp0';
  }

  @override
  String dashboardFamilyAndTitle(String family, String title) {
    return '$family · $title';
  }

  @override
  String get dashboardLoading => 'Loading your family dashboard…';

  @override
  String get dashboardOfflineTitle => 'Showing saved data';

  @override
  String dashboardOfflineUpdated(String time) {
    return 'Last updated $time. Pull down to refresh.';
  }

  @override
  String get dashboardSosTitle => 'Needs help now';

  @override
  String get dashboardQuickActionsTitle => 'Quick actions';

  @override
  String get dashboardActionAddTask => 'Add task';

  @override
  String get dashboardActionAddExpense => 'Add expense';

  @override
  String get dashboardActionPostNotice => 'Post notice';

  @override
  String get dashboardActionEmergencyCards => 'Emergency cards';

  @override
  String get dashboardGettingStartedTitle => 'Get your family started';

  @override
  String get dashboardGettingStartedMessage =>
      'A few steps and everyone knows who does what.';

  @override
  String get dashboardStepAddMembers => 'Add your family members';

  @override
  String get dashboardStepFirstTask => 'Create the first task';

  @override
  String get dashboardStepFirstGoal => 'Set a savings goal';

  @override
  String get dashboardStepFirstNotice => 'Post the first notice';

  @override
  String dashboardStepDone(String step) {
    return '$step (done)';
  }

  @override
  String get dashboardMyTasksTitle => 'My tasks';

  @override
  String get dashboardMyTasksEmptyTitle => 'You\'re all caught up';

  @override
  String get dashboardMyTasksEmptyMessage =>
      'Nothing pending for you right now.';

  @override
  String dashboardMyTasksMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more pending tasks',
      one: '1 more pending task',
    );
    return '$_temp0';
  }

  @override
  String get dashboardFamilyBoardTitle => 'Family board';

  @override
  String get dashboardMemberYou => 'You';

  @override
  String get dashboardMemberAllClear => 'All clear';

  @override
  String dashboardMemberPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending',
      one: '1 pending',
    );
    return '$_temp0';
  }

  @override
  String dashboardMemberOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overdue',
      one: '1 overdue',
    );
    return '$_temp0';
  }

  @override
  String dashboardMemberDoneThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count done this week',
      one: '1 done this week',
    );
    return '$_temp0';
  }

  @override
  String get dashboardGoalsTitle => 'Savings goals';

  @override
  String get dashboardGoalsEmptyTitle => 'No active goals';

  @override
  String get dashboardGoalsEmptyAdmin =>
      'Save together for a holiday, a new phone or a rainy day.';

  @override
  String get dashboardGoalsEmptyMember =>
      'When a family admin sets a savings goal, it shows up here.';

  @override
  String get dashboardNewGoal => 'New goal';

  @override
  String get dashboardMonthTitle => 'This month';

  @override
  String get dashboardNoticesTitle => 'Latest notices';

  @override
  String get dashboardNoticesEmptyTitle => 'No notices yet';

  @override
  String get dashboardNoticesEmptyMessage =>
      'Share plans, news and reminders with everyone.';

  @override
  String get dashboardHeroMyTasks => 'Pending';

  @override
  String get dashboardHeroMembers => 'Members';

  @override
  String get dashboardHeroGoals => 'Goals';

  @override
  String dashboardHeroAtLeast(String count) {
    return '$count+';
  }

  @override
  String get emergencyCardListTitle => 'Emergency cards';

  @override
  String get emergencyCardListIntro =>
      'Health details and contacts for each family member. Open a card to show it to a doctor or first responder.';

  @override
  String emergencyCardCallEmergencyNumber(String number) {
    return 'In danger? Call $number';
  }

  @override
  String get emergencyCardTitle => 'Emergency card';

  @override
  String get emergencyCardEditTitle => 'Edit emergency card';

  @override
  String get emergencyCardEditAction => 'Edit card';

  @override
  String get emergencyCardFillIn => 'Fill in card';

  @override
  String get emergencyCardBloodGroup => 'Blood group';

  @override
  String get emergencyCardBloodGroupUnknown => 'Unknown';

  @override
  String emergencyCardBloodGroupSemantics(String group) {
    return 'Blood group $group';
  }

  @override
  String get emergencyCardAllergies => 'Allergies';

  @override
  String get emergencyCardMedications => 'Medications';

  @override
  String get emergencyCardConditions => 'Medical conditions';

  @override
  String emergencyCardAllergySemantics(String item) {
    return 'Allergy: $item';
  }

  @override
  String get emergencyCardDoctor => 'Doctor';

  @override
  String get emergencyCardDoctorName => 'Doctor\'s name';

  @override
  String get emergencyCardDoctorPhone => 'Doctor\'s phone';

  @override
  String get emergencyCardInsurance => 'Health insurance';

  @override
  String get emergencyCardInsuranceProvider => 'Insurance provider';

  @override
  String get emergencyCardPolicyNumber => 'Policy number';

  @override
  String get emergencyCardCopyPolicyNumber => 'Copy policy number';

  @override
  String get emergencyCardPolicyNumberCopied => 'Policy number copied';

  @override
  String get emergencyCardContacts => 'Emergency contacts';

  @override
  String get emergencyCardContactName => 'Name';

  @override
  String get emergencyCardContactPhone => 'Phone';

  @override
  String get emergencyCardContactRelation => 'Relation';

  @override
  String get emergencyCardContactRelationHint => 'e.g. Uncle, Neighbour';

  @override
  String emergencyCardContactNumber(int number) {
    return 'Contact $number';
  }

  @override
  String get emergencyCardAddContact => 'Add contact';

  @override
  String emergencyCardRemoveContact(int number) {
    return 'Remove contact $number';
  }

  @override
  String emergencyCardContactsLimit(int max) {
    return 'You can add up to $max contacts.';
  }

  @override
  String get emergencyCardContactsNotice =>
      'Let the people you add know that they are your emergency contacts.';

  @override
  String get emergencyCardNoPhone => 'No phone number';

  @override
  String emergencyCardCallPerson(String name) {
    return 'Call $name';
  }

  @override
  String emergencyCardCallFailed(String phone) {
    return 'Couldn\'t start a call on this device. The number is $phone.';
  }

  @override
  String get emergencyCardNotes => 'Notes';

  @override
  String get emergencyCardNotesHint => 'Anything else a responder should know';

  @override
  String get emergencyCardNotRecorded => 'Not recorded';

  @override
  String emergencyCardLastUpdated(String date) {
    return 'Last updated $date';
  }

  @override
  String get emergencyCardEmptyTitle => 'No emergency details yet';

  @override
  String get emergencyCardEmptyMessage =>
      'Add the blood group, allergies and emergency contacts so your family can help quickly.';

  @override
  String get emergencyCardEmptyReadOnly =>
      'Only this member or a family admin can fill in this card.';

  @override
  String get emergencyCardNoEditPermission =>
      'Only this member or a family admin can edit this card.';

  @override
  String get emergencyCardShowToResponder => 'Show to responder';

  @override
  String get emergencyCardResponderHint => 'Emergency medical information';

  @override
  String get emergencyCardResponderClose => 'Close responder view';

  @override
  String emergencyCardOfflineCopy(String time) {
    return 'Offline copy from $time. It may be out of date.';
  }

  @override
  String get emergencyCardOfflineCopyShort => 'Offline copy';

  @override
  String get emergencyCardOfflineEditWarning =>
      'You\'re editing an offline copy. Saving needs an internet connection.';

  @override
  String emergencyCardCompleteness(int filled, int total) {
    return '$filled of $total key details';
  }

  @override
  String get emergencyCardComplete => 'All key details added';

  @override
  String get emergencyCardNotStarted => 'Not filled in yet';

  @override
  String emergencyCardMissing(String sections) {
    return 'Missing: $sections';
  }

  @override
  String get emergencyCardLoadFailed => 'Couldn\'t load this card';

  @override
  String get emergencyCardSectionContacts => 'Emergency contact';

  @override
  String get emergencyCardDisclaimer =>
      'This card is for emergencies and is not medical advice. Keep it up to date and confirm details with a doctor.';

  @override
  String get emergencyCardPrivacyNote =>
      'Everyone in your family can see this card. Health details are stored encrypted.';

  @override
  String get emergencyCardFixErrors => 'Please check the highlighted fields.';

  @override
  String get emergencyCardSaved => 'Emergency card saved';

  @override
  String get emergencyCardAllergyLabel => 'Add an allergy';

  @override
  String get emergencyCardAllergyHint => 'e.g. Peanuts, Penicillin';

  @override
  String get emergencyCardMedicationLabel => 'Add a medication';

  @override
  String get emergencyCardMedicationHint => 'e.g. Metformin 500 mg twice a day';

  @override
  String get emergencyCardConditionLabel => 'Add a condition';

  @override
  String get emergencyCardConditionHint => 'e.g. Asthma, Type 2 diabetes';

  @override
  String emergencyCardAddItem(String item) {
    return 'Add $item';
  }

  @override
  String emergencyCardRemoveItem(String item) {
    return 'Remove $item';
  }

  @override
  String emergencyCardItemCount(int count, int max) {
    return '$count of $max';
  }

  @override
  String emergencyCardListFull(int max) {
    return 'You can add up to $max entries.';
  }

  @override
  String get emergencyCardDuplicateItem => 'Already in the list';

  @override
  String get emergencyCardNotFoundTitle => 'This card is not available';

  @override
  String get emergencyCardNotFoundMessage =>
      'The member may have been removed from your family, or the link is out of date.';

  @override
  String get emergencyCardBackToList => 'All emergency cards';

  @override
  String get emergencyCardChangedWhileEditing =>
      'This card was updated while you were editing. Saving replaces that version with yours.';

  @override
  String get emergencyCardListSeparator => ', ';

  @override
  String emergencyCardPersonWithRelation(String name, String relation) {
    return '$name · $relation';
  }

  @override
  String get emergencyCardStatMembers => 'Family members';

  @override
  String get emergencyCardStatComplete => 'Cards complete';

  @override
  String get errorNetwork =>
      'No internet connection. Check your connection and try again.';

  @override
  String get errorTimeout =>
      'The server is taking too long to respond. Please try again.';

  @override
  String get errorUnknown => 'Something went wrong. Please try again.';

  @override
  String get errorServer =>
      'Our server ran into a problem. Please try again in a moment.';

  @override
  String get errorUnauthorized => 'Please sign in to continue.';

  @override
  String get errorSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get errorForbidden => 'You don\'t have permission to do that.';

  @override
  String get errorNotFound =>
      'We couldn\'t find that. It may have been deleted.';

  @override
  String get errorValidation =>
      'Some details are missing or invalid. Please check and try again.';

  @override
  String get errorInvalidCredentials => 'Incorrect email or password.';

  @override
  String get errorEmailTaken =>
      'An account with this email already exists. Try signing in instead.';

  @override
  String get errorInvalidOtp =>
      'That code is incorrect. Please check and try again.';

  @override
  String get errorOtpExpired =>
      'This code has expired or was tried too many times. Request a new one.';

  @override
  String get errorInvalidInviteCode =>
      'This invite code isn\'t valid. Ask your family admin for the current code.';

  @override
  String get errorAlreadyInFamily => 'You\'re already a member of a family.';

  @override
  String get errorNoFamily =>
      'You\'re not part of a family yet. Create one or join with an invite code.';

  @override
  String get errorMemberEmailExists =>
      'A family member with this email already exists.';

  @override
  String get errorLastAdmin =>
      'Your family needs at least one admin. Make someone else an admin first.';

  @override
  String get errorSosNotActive => 'This SOS alert has already ended.';

  @override
  String get errorGuardianConsentRequired =>
      'A parent or guardian must give consent to add a member of this age.';

  @override
  String errorTooManyRequests(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Too many attempts. Please try again in $seconds seconds.',
      one: 'Too many attempts. Please try again in 1 second.',
      zero: 'Too many attempts. Please wait a moment and try again.',
    );
    return '$_temp0';
  }

  @override
  String get errorLocationSharingDisabled =>
      'Location sharing is turned off. Change it in Settings > Location to share your location.';

  @override
  String get errorBadRequest =>
      'The request couldn\'t be processed. Please try again.';

  @override
  String get familyMembersTitle => 'Family members';

  @override
  String familyMembersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
      zero: 'No members',
    );
    return '$_temp0';
  }

  @override
  String get familyAddMember => 'Add member';

  @override
  String get familyMembersEmptyTitle => 'No members yet';

  @override
  String get familyMembersEmptyMessage =>
      'Add the people in your family, including children and elders who don\'t use a phone.';

  @override
  String get familyYouBadge => 'You';

  @override
  String get familyNoAccountBadge => 'No account';

  @override
  String get familyInvitedBadge => 'Invited';

  @override
  String familyAgeGroupWithAge(String group, String age) {
    return '$group · $age';
  }

  @override
  String get familySettingsTooltip => 'Family settings';

  @override
  String get familyOpenMemberHint => 'Open details';

  @override
  String get familyEmailAction => 'Email';

  @override
  String get familyCannotOpenPhone => 'Couldn\'t open the phone app.';

  @override
  String get familyCannotOpenEmail => 'Couldn\'t open an email app.';

  @override
  String get familyCannotOpenMap => 'Couldn\'t open the map.';

  @override
  String get familyDetailsSection => 'Details';

  @override
  String get familyActionsSection => 'Actions';

  @override
  String get familyInfoAge => 'Age';

  @override
  String get familyInfoDateOfBirth => 'Date of birth';

  @override
  String get familyInfoGender => 'Gender';

  @override
  String get familyInfoRole => 'Role';

  @override
  String get familyInfoDesignation => 'Designation';

  @override
  String get familyInfoPhone => 'Phone';

  @override
  String get familyInfoEmail => 'Email';

  @override
  String get familyInfoLocationSharing => 'Location sharing';

  @override
  String get familyInfoAccount => 'Account';

  @override
  String get familyInfoGuardianConsent => 'Guardian consent';

  @override
  String get familyInfoLastLocation => 'Last known location';

  @override
  String familyLastLocationUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String get familyAccountActive => 'Has their own account';

  @override
  String get familyAccountInvited => 'Invited by email, hasn\'t joined yet';

  @override
  String get familyAccountManaged => 'Managed profile, no account';

  @override
  String get familyGuardianConsentGiven => 'Given';

  @override
  String get familyGuardianConsentMissing => 'Not recorded';

  @override
  String get familyOpenMap => 'Open map';

  @override
  String get familyChangeAction => 'Change';

  @override
  String get familyEmergencyCard => 'Emergency card';

  @override
  String get familyAssignTask => 'Assign a task';

  @override
  String get familyEditDetails => 'Edit details';

  @override
  String get familyRemoveMember => 'Remove from family';

  @override
  String familyRemoveConfirmTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String familyRemoveConfirmMessage(String name) {
    return '$name will lose access to the family. Their open tasks and emergency card will be deleted and any active SOS alert will be closed. Money entries stay in the ledger.';
  }

  @override
  String familyMemberRemoved(String name) {
    return '$name was removed from the family';
  }

  @override
  String get familyEditMemberTitle => 'Edit member';

  @override
  String get familyEditMyDetailsTitle => 'Edit my details';

  @override
  String get familyPhotoLabel => 'Photo';

  @override
  String get familyNameLabel => 'Name';

  @override
  String get familyEmailLabel => 'Email (optional)';

  @override
  String get familyEmailInviteHint =>
      'We\'ll email them an invitation with your family code so they can join with their own account.';

  @override
  String get familyEmailManagedHint =>
      'Add an email so they can join with their own account.';

  @override
  String get familyEmailLinkedHint => 'This is the email of their account.';

  @override
  String get familyEmailLinkedSelfHint => 'This is the email of your account.';

  @override
  String get familyNoEmailHint =>
      'Leave empty for children or elders who won\'t use the app.';

  @override
  String get familyPhoneLabel => 'Phone (optional)';

  @override
  String familyPhoneHint(String dialCode) {
    return 'Include the country code, e.g. $dialCode';
  }

  @override
  String get familyDesignationHint =>
      'Their title in the family, e.g. Finance Head';

  @override
  String get familyDesignationSuggestions => 'Suggestions';

  @override
  String get familyRoleChangeSelfNote =>
      'You can\'t change your own role. Ask another admin.';

  @override
  String get familyGuardianConsentTitle => 'Guardian consent';

  @override
  String familyGuardianConsentLaw(String law, int age) {
    return 'Under $law, a parent or guardian must agree before we store details of anyone under $age.';
  }

  @override
  String get familyGuardianConsentCheckbox =>
      'I am this member\'s parent or legal guardian and I agree that FamilyHub may store and use their details for our family.';

  @override
  String get familyGuardianConsentRequired =>
      'Please confirm guardian consent to continue.';

  @override
  String familyMemberAdded(String name) {
    return '$name was added to the family';
  }

  @override
  String familyMemberAddedInvited(String name, String email) {
    return '$name was added. We sent an invitation to $email.';
  }

  @override
  String familyPhotoNotSaved(String name) {
    return '$name was added, but the photo couldn\'t be saved. You can add it by editing their details.';
  }

  @override
  String get familyCannotEditTitle => 'You can\'t edit this member';

  @override
  String get familyCannotEditMessage =>
      'Only family admins can change other members\' details.';

  @override
  String get familyDesignationHeadOfFamily => 'Head of Family';

  @override
  String get familyDesignationFinanceHead => 'Finance Head (CFO)';

  @override
  String get familyDesignationOperationsHead => 'Operations Head (COO)';

  @override
  String get familyDesignationHealthOfficer => 'Chief Health Officer';

  @override
  String get familyDesignationTechHead => 'Tech Head (CTO)';

  @override
  String get familyDesignationChiefStudyOfficer => 'Chief Study Officer';

  @override
  String get familyDesignationSkillBuilder => 'Skill Builder';

  @override
  String get familyDesignationChiefFunOfficer => 'Chief Fun Officer';

  @override
  String get familyDesignationJuniorExplorer => 'Junior Explorer';

  @override
  String get familyDesignationFamilyAdvisor => 'Family Advisor';

  @override
  String get familyDesignationChiefMentor => 'Chief Mentor';

  @override
  String get familySettingsTitle => 'Family settings';

  @override
  String get familyNameFieldLabel => 'Family name';

  @override
  String get familyCountryLabel => 'Country';

  @override
  String familyCountryDetails(String number, int age) {
    return 'Emergency number $number · Guardian consent under $age';
  }

  @override
  String get familyCurrencyLabel => 'Currency';

  @override
  String get familyTimezoneLabel => 'Time zone';

  @override
  String get familyTimezoneHint =>
      'Used for due dates, \"today\" and monthly money summaries.';

  @override
  String get familySettingsSaved => 'Family settings saved';

  @override
  String get familySettingsReadOnly =>
      'Only family admins can change these settings.';

  @override
  String get familyNotFoundTitle => 'No family yet';

  @override
  String get familyInviteCodeTitle => 'Invite code';

  @override
  String get familyInviteCodeMessage =>
      'Share this code with your family. They enter it in the app to join.';

  @override
  String familyInviteCodeSemantics(String code) {
    return 'Invite code: $code';
  }

  @override
  String get familyCopyInviteCode => 'Copy code';

  @override
  String get familyInviteCodeCopied => 'Invite code copied';

  @override
  String get familyNewInviteCode => 'New code';

  @override
  String get familyNewInviteCodeConfirmTitle => 'Create a new invite code?';

  @override
  String get familyNewInviteCodeConfirmMessage =>
      'The current code stops working right away. Anyone who hasn\'t joined yet will need the new code.';

  @override
  String get familyNewInviteCodeConfirm => 'Create new code';

  @override
  String get familyNewInviteCodeCreated => 'New invite code created';

  @override
  String get familyInviteCodeAdminOnly =>
      'Ask a family admin for the invite code.';

  @override
  String get familyViewMembers => 'View members';

  @override
  String get familyMemberGoneTitle => 'This person is no longer in the family';

  @override
  String get familyMemberGoneMessage => 'A family admin may have removed them.';

  @override
  String familyMemberAlreadyRemoved(String name) {
    return '$name had already been removed from the family';
  }

  @override
  String familyDuplicateNameTitle(String name) {
    return '$name is already in the family';
  }

  @override
  String get familyDuplicateNameMessage =>
      'Add another member with the same name? If an earlier try looked like it failed, check the member list first.';

  @override
  String get familyDuplicateNameConfirm => 'Add anyway';

  @override
  String get familyStatAdmins => 'Admins';

  @override
  String get familyStatAppUsers => 'On the app';

  @override
  String get familyStatKids => 'Kids & teens';

  @override
  String get familyContactSection => 'Contact';

  @override
  String get familyLocationSection => 'Location';

  @override
  String get familyRoleSection => 'Role in the family';

  @override
  String get familyProfileSection => 'Family profile';

  @override
  String get navHome => 'Home';

  @override
  String get navTasks => 'Tasks';

  @override
  String get navSos => 'SOS';

  @override
  String get navSosTooltip => 'SOS - alert your family';

  @override
  String get navMoney => 'Money';

  @override
  String get navMore => 'More';

  @override
  String get homeSplashLoading => 'Getting your family ready…';

  @override
  String get homeRouteNotFoundTitle => 'Page not found';

  @override
  String get homeRouteNotFoundMessage =>
      'This link doesn\'t exist or is no longer available.';

  @override
  String get homeGoHome => 'Go to home';

  @override
  String get homePlaceholderTitle => 'Coming soon';

  @override
  String get homePlaceholderMessage =>
      'This part of FamilyHub is still being built.';

  @override
  String get homePlaceholderDemoSignIn => 'Try the demo family';

  @override
  String get homePlaceholderSignOut => 'Sign out';

  @override
  String get ledgerTitle => 'Money';

  @override
  String get ledgerRecordsOnlyNote => 'Records only – no real money is moved.';

  @override
  String get ledgerTypeIncome => 'Income';

  @override
  String get ledgerTypeExpense => 'Expense';

  @override
  String get ledgerAddIncome => 'Add income';

  @override
  String get ledgerAddExpense => 'Add expense';

  @override
  String get ledgerAddEntry => 'Add entry';

  @override
  String get ledgerAddEntryChooseType => 'What would you like to record?';

  @override
  String get ledgerAddIncomeHint => 'Salary, pocket money, gifts, interest…';

  @override
  String get ledgerAddExpenseHint =>
      'Groceries, bills, school fees, household help…';

  @override
  String get ledgerCategorySalary => 'Salary';

  @override
  String get ledgerCategoryBusiness => 'Business';

  @override
  String get ledgerCategoryAllowance => 'Allowance';

  @override
  String get ledgerCategoryGift => 'Gift';

  @override
  String get ledgerCategoryInterest => 'Interest';

  @override
  String get ledgerCategoryOtherIncome => 'Other income';

  @override
  String get ledgerCategoryGroceries => 'Groceries';

  @override
  String get ledgerCategoryUtilities => 'Bills & utilities';

  @override
  String get ledgerCategoryRent => 'Rent';

  @override
  String get ledgerCategoryEducation => 'Education';

  @override
  String get ledgerCategoryHealth => 'Health';

  @override
  String get ledgerCategoryTransport => 'Transport';

  @override
  String get ledgerCategoryDining => 'Eating out';

  @override
  String get ledgerCategoryShopping => 'Shopping';

  @override
  String get ledgerCategoryEntertainment => 'Entertainment';

  @override
  String get ledgerCategoryHouseholdHelp => 'Household help';

  @override
  String get ledgerCategorySavings => 'Savings';

  @override
  String get ledgerCategoryOtherExpense => 'Other expense';

  @override
  String get ledgerScopeFamily => 'Family';

  @override
  String get ledgerScopePersonal => 'Personal';

  @override
  String get ledgerScopeFamilyHint => 'Totals for the whole family';

  @override
  String get ledgerScopePersonalHint => 'Totals for your own entries';

  @override
  String get ledgerSummaryIncome => 'Income';

  @override
  String get ledgerSummaryExpense => 'Expenses';

  @override
  String get ledgerSummaryNet => 'Balance';

  @override
  String ledgerSummaryEmpty(String month) {
    return 'Nothing recorded for $month yet.';
  }

  @override
  String get ledgerMonthPrevious => 'Previous month';

  @override
  String get ledgerMonthNext => 'Next month';

  @override
  String get ledgerMonthPick => 'Choose a month';

  @override
  String get ledgerAllMonths => 'All months';

  @override
  String get ledgerThisMonth => 'This month';

  @override
  String get ledgerBreakdownTitle => 'By category';

  @override
  String get ledgerBreakdownOther => 'Other';

  @override
  String get ledgerBreakdownEmptyExpense => 'No expenses recorded this month.';

  @override
  String get ledgerBreakdownEmptyIncome => 'No income recorded this month.';

  @override
  String ledgerBreakdownItemSemantics(
    String category,
    String amount,
    String percent,
  ) {
    return '$category: $amount, $percent';
  }

  @override
  String get ledgerGoalsTitle => 'Savings goals';

  @override
  String get ledgerNewGoal => 'New goal';

  @override
  String get ledgerGoalsEmpty => 'No savings goals yet';

  @override
  String get ledgerGoalsEmptyAdmin =>
      'Save together for a trip, school fees or a rainy-day fund.';

  @override
  String get ledgerGoalsEmptyMember =>
      'Your family admins can create goals that everyone contributes to.';

  @override
  String ledgerShowArchivedGoals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Show $count archived goals',
      one: 'Show 1 archived goal',
    );
    return '$_temp0';
  }

  @override
  String get ledgerHideArchivedGoals => 'Hide archived goals';

  @override
  String get ledgerRecentTitle => 'Recent entries';

  @override
  String get ledgerRecentEmpty => 'No entries this month';

  @override
  String get ledgerRecentEmptyMessage =>
      'Record income or an expense with “Add entry”.';

  @override
  String ledgerEntryTileSubtitle(String date, String member) {
    return '$date · $member';
  }

  @override
  String get ledgerEntryGoalBadge => 'Goal';

  @override
  String get ledgerEntriesTitle => 'All entries';

  @override
  String get ledgerEntriesEmpty => 'No entries found';

  @override
  String get ledgerEntriesEmptyFiltered =>
      'Try another month or clear the filters.';

  @override
  String get ledgerEntriesEmptyMessage =>
      'Entries you record will show up here.';

  @override
  String get ledgerClearFilters => 'Clear filters';

  @override
  String get ledgerFilterAllTypes => 'All';

  @override
  String get ledgerFilterMember => 'Member';

  @override
  String get ledgerFilterAllMembers => 'Everyone';

  @override
  String get ledgerEntriesVisibleToMember =>
      'You see the entries that are yours or that you added.';

  @override
  String get ledgerNewEntryTitle => 'New entry';

  @override
  String get ledgerEditEntryTitle => 'Edit entry';

  @override
  String ledgerFieldAmount(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String get ledgerFieldCategory => 'Category';

  @override
  String get ledgerFieldDate => 'Date';

  @override
  String get ledgerFieldNote => 'Note (optional)';

  @override
  String get ledgerFieldNoteHint => 'e.g. Weekly vegetables';

  @override
  String get ledgerFieldMember => 'Whose money';

  @override
  String get ledgerFieldMemberLocked =>
      'Members record entries for themselves.';

  @override
  String ledgerMemberYou(String name) {
    return '$name (you)';
  }

  @override
  String get ledgerCategoryRequired => 'Choose a category';

  @override
  String get ledgerDateInFuture => 'The date can\'t be in the future';

  @override
  String get ledgerGoalLinkedLocked =>
      'This entry is a goal contribution, so its amount and category can\'t be changed. Delete it and contribute again instead.';

  @override
  String get ledgerEntryAdded => 'Entry added';

  @override
  String get ledgerEntrySaved => 'Entry updated';

  @override
  String get ledgerEntryDeleted => 'Entry deleted';

  @override
  String get ledgerEntryDetailTitle => 'Entry details';

  @override
  String get ledgerDetailMember => 'Belongs to';

  @override
  String get ledgerDetailCreatedBy => 'Added by';

  @override
  String get ledgerDetailCategory => 'Category';

  @override
  String get ledgerDetailDate => 'Date';

  @override
  String get ledgerDetailNote => 'Note';

  @override
  String get ledgerDetailGoal => 'Savings goal contribution';

  @override
  String get ledgerDetailOpenGoal => 'View goal';

  @override
  String get ledgerDeleteEntryTitle => 'Delete this entry?';

  @override
  String get ledgerDeleteEntryMessage => 'This can\'t be undone.';

  @override
  String get ledgerDeleteContributionMessage =>
      'The amount will also be taken off the goal\'s saved total. This can\'t be undone.';

  @override
  String get ledgerGoalNewTitle => 'New savings goal';

  @override
  String get ledgerGoalEditTitle => 'Edit goal';

  @override
  String get ledgerGoalFieldTitle => 'Goal name';

  @override
  String get ledgerGoalFieldTitleHint => 'e.g. Goa vacation';

  @override
  String get ledgerGoalFieldDescription => 'Description (optional)';

  @override
  String ledgerGoalFieldTarget(String currency) {
    return 'Target amount ($currency)';
  }

  @override
  String get ledgerGoalFieldTargetDate => 'Target date (optional)';

  @override
  String get ledgerGoalCreated => 'Goal created';

  @override
  String get ledgerGoalUpdated => 'Goal updated';

  @override
  String get ledgerGoalAdminOnly =>
      'Only family admins can create or change savings goals.';

  @override
  String get ledgerGoalStatusActive => 'Active';

  @override
  String get ledgerGoalStatusAchieved => 'Achieved';

  @override
  String get ledgerGoalStatusArchived => 'Archived';

  @override
  String get ledgerGoalSavedLabel => 'Saved';

  @override
  String get ledgerGoalTargetLabel => 'Target';

  @override
  String get ledgerGoalRemainingLabel => 'Still to go';

  @override
  String ledgerGoalSavedOfTarget(String saved, String target) {
    return '$saved of $target';
  }

  @override
  String ledgerGoalPercentSaved(String percent) {
    return '$percent saved';
  }

  @override
  String ledgerGoalRemainingHint(String amount) {
    return '$amount still to go';
  }

  @override
  String ledgerGoalDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get ledgerGoalDueToday => 'Due today';

  @override
  String ledgerGoalOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days past target date',
      one: '1 day past target date',
    );
    return '$_temp0';
  }

  @override
  String ledgerGoalTargetDate(String date) {
    return 'Target date: $date';
  }

  @override
  String get ledgerGoalNoTargetDate => 'No target date';

  @override
  String get ledgerGoalReachedMessage => 'Target reached – well done, team!';

  @override
  String get ledgerGoalContribute => 'Contribute';

  @override
  String ledgerGoalContributeTitle(String title) {
    return 'Contribute to $title';
  }

  @override
  String get ledgerGoalContributeExplainer =>
      'The amount is recorded as a savings expense in your name.';

  @override
  String get ledgerGoalContributionNoteHint => 'e.g. Diwali bonus';

  @override
  String get ledgerGoalContributed => 'Contribution recorded';

  @override
  String get ledgerGoalAchievedTitle => 'Goal achieved!';

  @override
  String ledgerGoalAchievedMessage(String title, String target) {
    return '“$title” has reached its target of $target. Well done, team!';
  }

  @override
  String get ledgerGoalCelebrate => 'Hooray!';

  @override
  String get ledgerGoalContributionsTitle => 'Contributions';

  @override
  String get ledgerGoalContributionsEmpty => 'No contributions yet';

  @override
  String get ledgerGoalContributionsEmptyMessage =>
      'Be the first to put something aside.';

  @override
  String get ledgerGoalContributionsMineOnly =>
      'You see your own contributions here.';

  @override
  String get ledgerGoalArchivedNotice =>
      'This goal is archived and doesn\'t take contributions.';

  @override
  String get ledgerGoalArchivedError =>
      'This goal is archived, so it can\'t take contributions.';

  @override
  String get ledgerGoalActions => 'Goal actions';

  @override
  String get ledgerGoalArchive => 'Archive';

  @override
  String get ledgerGoalRestore => 'Restore';

  @override
  String get ledgerGoalArchiveTitle => 'Archive this goal?';

  @override
  String get ledgerGoalArchiveMessage =>
      'Archived goals stop taking contributions. You can restore it later.';

  @override
  String get ledgerGoalArchivedDone => 'Goal archived';

  @override
  String get ledgerGoalRestoredDone => 'Goal restored';

  @override
  String get ledgerGoalDelete => 'Delete goal';

  @override
  String get ledgerGoalDeleteTitle => 'Delete this goal?';

  @override
  String get ledgerGoalDeleteMessage =>
      'Its contributions stay in the ledger as savings entries.';

  @override
  String get ledgerGoalDeleted => 'Goal deleted';

  @override
  String get ledgerErrorEntryGone =>
      'This entry no longer exists – someone may have deleted it.';

  @override
  String get ledgerErrorGoalGone =>
      'This goal no longer exists – an admin may have deleted it.';

  @override
  String get ledgerErrorForbidden =>
      'You can\'t do this any more. Your role in the family may have changed.';

  @override
  String get ledgerErrorTimeout =>
      'The server took too long to answer. Check the list before trying again – it may already be saved.';

  @override
  String get ledgerErrorMemberGone =>
      'That person is no longer in the family. Choose someone else.';

  @override
  String get ledgerErrorDate =>
      'That date is too far ahead for your family\'s time zone. Choose today or an earlier day.';

  @override
  String get ledgerErrorAmount => 'Check the amount and try again.';

  @override
  String get ledgerErrorCategory =>
      'This category doesn\'t fit the entry type. Choose another one.';

  @override
  String get ledgerEntryAlreadyDeleted => 'This entry was already deleted.';

  @override
  String get ledgerGoalAlreadyDeleted => 'This goal was already deleted.';

  @override
  String get ledgerGoalNotFoundTitle => 'Goal not found';

  @override
  String get ledgerGoalNotFoundMessage =>
      'It may have been deleted by a family admin.';

  @override
  String get ledgerBackToMoney => 'Back to Money';

  @override
  String get ledgerFormerMember => 'Former member';

  @override
  String ledgerMemberNoLongerInFamily(String name) {
    return 'Recorded for $name, who is no longer in the family.';
  }

  @override
  String ledgerHeaderSpentShare(String percent) {
    return '$percent of income spent';
  }

  @override
  String get ledgerHeaderOnTrack => 'On track';

  @override
  String get ledgerHeaderOverBudget => 'Over budget';

  @override
  String get ledgerHeaderNoIncome => 'No income recorded yet';

  @override
  String get ledgerFormDetailsTitle => 'Details';

  @override
  String get noticesTitle => 'Notice board';

  @override
  String get noticesNew => 'New notice';

  @override
  String get noticesEditTitle => 'Edit notice';

  @override
  String get noticesEmptyTitle => 'No notices yet';

  @override
  String get noticesEmptyMessage =>
      'Share news, plans and reminders with the whole family.';

  @override
  String get noticesPinned => 'Pinned';

  @override
  String get noticesPin => 'Pin to top';

  @override
  String get noticesUnpin => 'Unpin';

  @override
  String get noticesPinnedSuccess => 'Notice pinned to the top';

  @override
  String get noticesUnpinnedSuccess => 'Notice unpinned';

  @override
  String get noticesDeleteTitle => 'Delete this notice?';

  @override
  String noticesDeleteMessage(String title) {
    return '\"$title\" will be removed for everyone in the family. This can\'t be undone.';
  }

  @override
  String get noticesDeleted => 'Notice deleted';

  @override
  String get noticesPosted => 'Notice posted';

  @override
  String get noticesUpdated => 'Notice updated';

  @override
  String get noticesReadMore => 'Read more';

  @override
  String get noticesShowLess => 'Show less';

  @override
  String get noticesActions => 'Notice options';

  @override
  String get noticesCopyText => 'Copy text';

  @override
  String get noticesOpenImage => 'Open photo';

  @override
  String noticesImageLabel(String title) {
    return 'Photo: $title';
  }

  @override
  String noticesPostedBy(String name) {
    return 'Posted by $name';
  }

  @override
  String get noticesFormerMember => 'Former member';

  @override
  String get noticesFieldTitle => 'Title';

  @override
  String get noticesFieldTitleHint => 'e.g. Family meeting Sunday 7pm';

  @override
  String get noticesFieldBody => 'Message';

  @override
  String get noticesFieldBodyHint => 'What would you like to tell the family?';

  @override
  String get noticesFieldImage => 'Photo (optional)';

  @override
  String get noticesFieldPinned => 'Pin to top';

  @override
  String get noticesFieldPinnedHint => 'Pinned notices stay above all others.';

  @override
  String get noticesPost => 'Post notice';

  @override
  String get noticesVisibleToFamily =>
      'Everyone in your family can see this notice.';

  @override
  String get noticesEditNotAllowed => 'You can\'t edit this notice';

  @override
  String get noticesEditNotAllowedMessage =>
      'Only the person who posted it or a family admin can change it.';

  @override
  String get noticesPhotoUploading =>
      'Please wait until the photo has finished uploading.';

  @override
  String get noticesGone => 'This notice was deleted in the meantime.';

  @override
  String get noticesNotFoundTitle => 'This notice is no longer available';

  @override
  String get noticesNotFoundMessage =>
      'It may have been deleted by the person who posted it or by a family admin.';

  @override
  String get noticesSubtitle =>
      'News, plans and reminders for the whole family.';

  @override
  String get noticesStatTotal => 'On the board';

  @override
  String get noticesSectionMessage => 'What\'s new?';

  @override
  String get noticesPhotoHint => 'Tap to add or change the photo';

  @override
  String get servicesPushChannelSosName => 'SOS alerts';

  @override
  String get servicesPushChannelSosDescription =>
      'Emergency alerts from your family. These are loud and appear on the lock screen.';

  @override
  String get servicesPushChannelGeneralName => 'Family updates';

  @override
  String get servicesPushChannelGeneralDescription =>
      'Tasks, notices, savings goals and new family members.';

  @override
  String get servicesLocationChannelName => 'Live location sharing';

  @override
  String get servicesLocationSharingTitle => 'Sharing your live location';

  @override
  String get servicesLocationSharingText =>
      'Your family can see where you are until you stop sharing.';

  @override
  String get servicesLocationDenied =>
      'FamilyHub needs location permission to share where you are.';

  @override
  String get servicesLocationDeniedForever =>
      'Location permission is turned off for FamilyHub. Allow it in Settings to share where you are.';

  @override
  String get servicesLocationServiceDisabled =>
      'Location services are turned off on this device. Turn them on to share where you are.';

  @override
  String get servicesLocationAllow => 'Allow location';

  @override
  String get servicesOpenSettings => 'Open settings';

  @override
  String get servicesErrorUploadFailed =>
      'The image couldn\'t be uploaded. Please try again.';

  @override
  String get servicesErrorFileTooLarge =>
      'This image is too large. Please choose a smaller one.';

  @override
  String get servicesErrorUploadCancelled => 'The upload was cancelled.';

  @override
  String get settingsProfileHeaderHint => 'Opens your profile';

  @override
  String get settingsSectionFamily => 'Family';

  @override
  String get settingsMembers => 'Members';

  @override
  String get settingsFamilySettings => 'Family settings';

  @override
  String get settingsNoticeBoard => 'Notice board';

  @override
  String get settingsEmergencyCards => 'Emergency cards';

  @override
  String get settingsSosHistory => 'SOS history';

  @override
  String get settingsSectionPreferences => 'Preferences';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsLocationSharing => 'Location sharing';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsEnabled => 'On';

  @override
  String get settingsNotificationsDisabled =>
      'Off. Turn them on in your phone settings to get SOS alerts.';

  @override
  String get settingsNotificationsNotAsked => 'Not turned on yet';

  @override
  String get settingsNotificationsUnavailable =>
      'Not available in this version of the app';

  @override
  String get settingsNotificationsOpenSettings => 'Open phone settings';

  @override
  String get settingsOpenSettingsFailed =>
      'Couldn\'t open the phone settings. Open them from your phone\'s Settings app.';

  @override
  String get settingsLinkOpenFailed =>
      'Couldn\'t open the link. Please try again.';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsPrivacy => 'Privacy & data';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLogout => 'Log out';

  @override
  String get settingsLogoutConfirmTitle => 'Log out of FamilyHub?';

  @override
  String get settingsLogoutConfirmMessage =>
      'SOS alerts and family updates will no longer reach this phone until you sign in again.';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsThemeSystem => 'Same as phone';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsProfileTitle => 'My profile';

  @override
  String get settingsProfilePhoto => 'Profile photo';

  @override
  String get settingsProfileName => 'Name';

  @override
  String get settingsProfilePhone => 'Phone number';

  @override
  String get settingsProfilePhoneHint => 'Include the country code, e.g. +91';

  @override
  String get settingsProfileDateOfBirth => 'Date of birth';

  @override
  String get settingsProfileGender => 'Gender';

  @override
  String get settingsProfileEmail => 'Email';

  @override
  String get settingsProfileDesignation => 'Title in the family';

  @override
  String get settingsProfileRole => 'Role';

  @override
  String get settingsProfileManagedByAdmin =>
      'Your title and role are set by a family admin.';

  @override
  String get settingsProfileSaved => 'Profile updated';

  @override
  String settingsProfileNameInvalid(int max) {
    return 'Enter a name with 1 to $max characters.';
  }

  @override
  String get settingsProfileDateOfBirthInvalid =>
      'Enter a real date of birth. It cannot be in the future.';

  @override
  String settingsProfileGuardianConsentNeeded(int age) {
    return 'Members younger than $age need a parent or guardian to set this. Ask a family admin to change your date of birth.';
  }

  @override
  String get settingsProfilePhotoRejected =>
      'This photo couldn\'t be saved. Please choose it again.';

  @override
  String get settingsNoFamilyTitle => 'You\'re not in a family yet';

  @override
  String get settingsNoFamilyMessage => 'Create or join a family to use this.';

  @override
  String get settingsLanguageDevice => 'Phone language';

  @override
  String settingsLanguageDeviceCurrent(String language) {
    return 'Currently $language';
  }

  @override
  String get settingsLanguageHint =>
      'Changes the language on this phone. Your notifications and emails will use it too.';

  @override
  String get settingsAppearanceTheme => 'Theme';

  @override
  String get settingsAppearanceTextSize => 'Text size';

  @override
  String get settingsAppearanceLargeText => 'Large text';

  @override
  String get settingsAppearanceLargeTextDescription =>
      'Makes all text bigger and easier to read. Your phone\'s text size setting is also respected.';

  @override
  String get settingsAppearancePreview => 'Preview';

  @override
  String get settingsAppearancePreviewTitle => 'Family meeting on Sunday';

  @override
  String get settingsAppearancePreviewBody =>
      'This is how text looks in FamilyHub with your current settings.';

  @override
  String get settingsLocationIntro =>
      'Choose when your family can see where you are. Only members of your family can see it, and only you can change this.';

  @override
  String get settingsLocationSharedNow => 'Your family can see your location';

  @override
  String settingsLocationLastShared(String time) {
    return 'Last shared $time';
  }

  @override
  String get settingsLocationNotSharedYet =>
      'Your location will be shared the next time you open the app.';

  @override
  String get settingsLocationShareNow => 'Share now';

  @override
  String get settingsLocationUpdated => 'Location shared with your family';

  @override
  String get settingsLocationSaved => 'Location sharing updated';

  @override
  String get settingsLocationFixUnavailable =>
      'We couldn\'t get your location right now. It will be shared the next time you open the app.';

  @override
  String get settingsLocationHowItWorks => 'How it works';

  @override
  String get settingsLocationAlwaysNote =>
      'With “Always share”, your location is updated when you open the app, at most every 10 minutes. The app does not follow you in the background.';

  @override
  String get settingsLocationSosNote =>
      'During an SOS your phone shows a notification for as long as your live location is being shared.';

  @override
  String get settingsLocationNeverNote =>
      'With “Never share”, an SOS still alerts your family, but without your location.';

  @override
  String get settingsPrivacyConsent =>
      'When you signed up, you agreed to the Privacy Policy and the Terms of Service. You can read them at any time.';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsTerms => 'Terms of Service';

  @override
  String get settingsPrivacyYourData => 'Your data';

  @override
  String get settingsPrivacyMembership => 'Family membership';

  @override
  String get settingsExportData => 'Export my data';

  @override
  String get settingsExportDataDescription =>
      'See a copy of everything FamilyHub stores about you.';

  @override
  String get settingsExportTitle => 'My data';

  @override
  String get settingsExportCopy => 'Copy all';

  @override
  String settingsExportGeneratedAt(String date) {
    return 'Exported $date';
  }

  @override
  String get settingsExportRawData => 'Full data (JSON)';

  @override
  String get settingsExportEmpty => 'There is no personal data to show.';

  @override
  String get settingsExportSectionUser => 'Account';

  @override
  String get settingsExportSectionMember => 'Family profile';

  @override
  String get settingsExportSectionFamily => 'Family';

  @override
  String get settingsExportSectionTasks => 'Tasks';

  @override
  String get settingsExportSectionLedger => 'Money entries';

  @override
  String get settingsExportSectionNotices => 'Notices';

  @override
  String get settingsExportSectionEmergencyCard => 'Emergency card';

  @override
  String get settingsExportSectionSos => 'SOS alerts';

  @override
  String get settingsExportSectionDevices => 'Phones for notifications';

  @override
  String get settingsExportSectionSessions => 'Sign-ins';

  @override
  String settingsExportItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportIncluded => 'Included';

  @override
  String get settingsLeaveFamily => 'Leave family';

  @override
  String settingsLeaveFamilyDescription(String family) {
    return 'Stop being part of $family. Your account stays.';
  }

  @override
  String settingsLeaveFamilyConfirmTitle(String family) {
    return 'Leave $family?';
  }

  @override
  String get settingsLeaveFamilyConfirmMessage =>
      'You will lose access to the family\'s tasks, money, notices and SOS alerts, and your profile is removed from the family. You can join again later with an invite code.';

  @override
  String get settingsLeaveFamilyOnlyMemberMessage =>
      'You are the only member, so leaving deletes the family and all of its tasks, money records, notices, emergency cards and SOS history. This cannot be undone. Your account stays.';

  @override
  String get settingsLeaveFamilyDone => 'You left the family';

  @override
  String get settingsLastAdminTitle => 'You\'re the last admin';

  @override
  String get settingsLastAdminLeaveMessage =>
      'A family always needs an admin. Make another member an admin first, then leave the family.';

  @override
  String get settingsLastAdminDeleteMessage =>
      'A family always needs an admin. Make another member an admin first, then delete your account.';

  @override
  String get settingsLastAdminOpenMembers => 'Go to members';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsDeleteAccountDescription =>
      'Permanently delete your account and personal data.';

  @override
  String get settingsDeleteAccountTitle => 'Delete your account?';

  @override
  String get settingsDeleteAccountMessage =>
      'This permanently deletes your account, your family profile, your emergency card and your registered devices. Money entries you recorded stay in the family ledger. If you are the only member, the whole family is deleted. This cannot be undone.';

  @override
  String get settingsDeleteAccountPassword => 'Your password';

  @override
  String get settingsDeleteAccountConfirm => 'Delete forever';

  @override
  String get settingsDeleteAccountWrongPassword =>
      'That password is not correct.';

  @override
  String get settingsDeleteAccountDone => 'Your account has been deleted.';

  @override
  String get settingsPasswordCurrent => 'Current password';

  @override
  String get settingsPasswordNew => 'New password';

  @override
  String get settingsPasswordConfirm => 'Confirm new password';

  @override
  String get settingsPasswordRules =>
      'At least 8 characters, with at least one letter and one number.';

  @override
  String get settingsPasswordSameAsCurrent =>
      'Choose a password that is different from your current one.';

  @override
  String get settingsPasswordWrongCurrent =>
      'Your current password is not correct.';

  @override
  String get settingsPasswordChanged => 'Password changed';

  @override
  String get settingsAboutMission =>
      'FamilyHub helps your family work together like a great team: clear roles, shared tasks, open money records and help when it matters.';

  @override
  String get settingsAboutSosTitle => 'SOS alerts your family only';

  @override
  String settingsAboutSosDisclaimer(String number) {
    return 'SOS sends an alert to your family members. It does not contact the police, an ambulance or any emergency service. If you are in danger, call $number.';
  }

  @override
  String settingsAboutCallEmergency(String number) {
    return 'Call $number';
  }

  @override
  String get settingsAboutMedicalTitle => 'Not medical advice';

  @override
  String get settingsAboutMedicalDisclaimer =>
      'FamilyHub is not a medical service and does not give medical advice. Emergency cards only show what your family has written down.';

  @override
  String get settingsAboutLedgerTitle => 'Records money, never moves it';

  @override
  String get settingsAboutLedgerNote =>
      'The family ledger only records income, expenses and savings. FamilyHub never sends or receives money and never asks for bank, card or UPI details.';

  @override
  String get settingsAboutPrivacyContact => 'Privacy questions';

  @override
  String get settingsAboutLicenses => 'Open-source licences';

  @override
  String get settingsEditProfile => 'Edit profile';

  @override
  String get settingsProfileSectionPersonal => 'About you';

  @override
  String get settingsPasswordSectionCurrent => 'Confirm it\'s you';

  @override
  String get settingsPasswordSectionNew => 'Choose a new password';

  @override
  String get settingsAboutGoodToKnow => 'Good to know';

  @override
  String get settingsAboutLegal => 'Legal & contact';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleMember => 'Member';

  @override
  String get roleAdminDescription =>
      'Can manage members, tasks, money and family settings';

  @override
  String get roleMemberDescription =>
      'Can view the family, do their tasks and post notices';

  @override
  String get genderMale => 'Male';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderOther => 'Other';

  @override
  String get genderUnspecified => 'Prefer not to say';

  @override
  String get ageGroupChild => 'Child';

  @override
  String get ageGroupTeen => 'Teen';

  @override
  String get ageGroupAdult => 'Adult';

  @override
  String get ageGroupSenior => 'Senior';

  @override
  String ageYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years',
      one: '1 year',
      zero: 'Under 1 year',
    );
    return '$_temp0';
  }

  @override
  String get locationSharingNever => 'Never share';

  @override
  String get locationSharingSosOnly => 'Only during SOS';

  @override
  String get locationSharingAlways => 'Always share';

  @override
  String get locationSharingNeverDescription =>
      'Your location is never shared, not even during an SOS.';

  @override
  String get locationSharingSosOnlyDescription =>
      'Your family sees your live location only while your SOS is active.';

  @override
  String get locationSharingAlwaysDescription =>
      'Your family can always see your last known location.';

  @override
  String get sosTitle => 'SOS';

  @override
  String get sosHistoryTooltip => 'SOS history';

  @override
  String get sosButtonLabel => 'SOS';

  @override
  String get sosButtonSemantics => 'Send an SOS alert to your family';

  @override
  String sosButtonHint(int seconds) {
    return 'Tap to alert your family. You can cancel within $seconds seconds.';
  }

  @override
  String sosSendingIn(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Sending in $seconds seconds',
      one: 'Sending in 1 second',
    );
    return '$_temp0';
  }

  @override
  String get sosCancelAlert => 'Cancel SOS';

  @override
  String get sosCancelled => 'SOS cancelled. Nobody was alerted.';

  @override
  String get sosSending => 'Alerting your family…';

  @override
  String get sosSent => 'Your family has been alerted.';

  @override
  String get sosSentWithoutLocation =>
      'Your family has been alerted, without your location.';

  @override
  String sosSentPermissionMissing(String reason) {
    return 'Your family has been alerted, but without your location: $reason';
  }

  @override
  String get sosSentSharingUpdateFailed =>
      'Your family has been alerted, but location sharing could not be turned on.';

  @override
  String get sosSendFailedTitle => 'The SOS was not sent';

  @override
  String sosSendFailedMessage(String number) {
    return 'Check your internet connection and try again. If you are in danger, call $number now.';
  }

  @override
  String get sosTryAgain => 'Send again';

  @override
  String get sosDisclaimerTitle => 'Alerts your family only';

  @override
  String get sosDisclaimer =>
      'SOS notifies the members of your family in FamilyHub. It does not contact the police, an ambulance or any other emergency service.';

  @override
  String sosCallEmergency(String number) {
    return 'Call emergency services $number';
  }

  @override
  String sosCallFailed(String number) {
    return 'Couldn\'t open the phone app. Please dial $number yourself.';
  }

  @override
  String get sosLocationModeTitle => 'Your location during SOS';

  @override
  String get sosActiveTitle => 'Your SOS is active';

  @override
  String get sosSharingLive => 'Sharing your live location with family';

  @override
  String get sosNotSharingLocation => 'Your location is not being shared';

  @override
  String get sosLocationOffHint =>
      'Your location sharing is set to Never, so your family can\'t see where you are.';

  @override
  String get sosChangeSharing => 'Change location sharing';

  @override
  String get sosViewAlert => 'View alert details';

  @override
  String sosTimeRemaining(String time) {
    return 'Ends in $time';
  }

  @override
  String sosLastSent(String time) {
    return 'Location sent $time';
  }

  @override
  String get sosWaitingForLocation => 'Waiting for your location…';

  @override
  String sosSecondsAgo(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds ago',
      one: '1 second ago',
      zero: 'just now',
    );
    return '$_temp0';
  }

  @override
  String get sosImOkay => 'I am okay';

  @override
  String get sosFalseAlarm => 'False alarm';

  @override
  String get sosResolvedSafe => 'Glad you are okay. Your family has been told.';

  @override
  String get sosResolvedFalseAlarm =>
      'SOS ended as a false alarm. Your family has been told.';

  @override
  String get sosOthersTitle => 'Family alerts';

  @override
  String get sosOthersEmpty => 'No one in your family needs help right now.';

  @override
  String get sosHistoryLink => 'Past alerts';

  @override
  String get sosLocationDialogTitle => 'Share your location?';

  @override
  String get sosLocationDialogMessage =>
      'Your location sharing is set to Never. Your family can find you faster if they see your live location while this SOS is active.';

  @override
  String get sosLocationDialogShare => 'Share location for SOS only';

  @override
  String get sosLocationDialogWithout => 'Send without location';

  @override
  String sosLocationDialogAutoSend(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other:
          'If you don\'t choose, it is sent without your location in $seconds seconds.',
      one:
          'If you don\'t choose, it is sent without your location in 1 second.',
    );
    return '$_temp0';
  }

  @override
  String get sosBannerSharing => 'Your SOS is active – sharing live location';

  @override
  String get sosBannerActive => 'Your SOS is active';

  @override
  String sosNeedsHelp(String name) {
    return '$name needs help';
  }

  @override
  String sosManyNeedHelp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count family members need help',
      one: '1 family member needs help',
    );
    return '$_temp0';
  }

  @override
  String get sosBannerOpen => 'Open';

  @override
  String get sosFormerMember => 'Former member';

  @override
  String get sosStatusActive => 'Active';

  @override
  String get sosStatusResolved => 'Resolved';

  @override
  String get sosStatusExpired => 'Ended';

  @override
  String get sosResolutionSafe => 'Safe';

  @override
  String get sosResolutionFalseAlarm => 'False alarm';

  @override
  String get sosResolutionHelped => 'Helped';

  @override
  String sosStarted(String time) {
    return 'Started $time';
  }

  @override
  String sosEnded(String time) {
    return 'Ended $time';
  }

  @override
  String get sosLiveLocation => 'Live location';

  @override
  String get sosNoLocation => 'No location shared';

  @override
  String get sosAlertTitle => 'SOS alert';

  @override
  String get sosYourAlert => 'Your SOS';

  @override
  String get sosMessageLabel => 'Message';

  @override
  String get sosLastLocationTitle => 'Last location';

  @override
  String sosAccuracy(String meters) {
    return 'Accurate to about $meters m';
  }

  @override
  String sosUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String sosCoordinates(String lat, String lng) {
    return '$lat, $lng';
  }

  @override
  String get sosOpenInMaps => 'Open in Maps';

  @override
  String get sosMapsFailed => 'Couldn\'t open the maps app.';

  @override
  String sosNoLocationShared(String name) {
    return '$name is not sharing their location.';
  }

  @override
  String get sosWaitingForMemberLocation => 'Waiting for the first location…';

  @override
  String get sosTrailTitle => 'Recent locations';

  @override
  String sosCallMember(String name) {
    return 'Call $name';
  }

  @override
  String get sosMarkHelped => 'Mark as helped';

  @override
  String get sosMarkHelpedConfirmTitle => 'End this SOS?';

  @override
  String sosMarkHelpedConfirmMessage(String name) {
    return '$name\'s alert ends for everyone and live location sharing stops. Only do this when $name is safe.';
  }

  @override
  String get sosMarkedHelped => 'The SOS was marked as helped.';

  @override
  String sosResolvedBy(String resolution, String name) {
    return '$resolution · by $name';
  }

  @override
  String get sosAlertGoneTitle => 'Alert not available';

  @override
  String get sosAlertGoneMessage =>
      'This SOS alert no longer exists or belongs to another family.';

  @override
  String get sosBackToSos => 'Go to SOS';

  @override
  String get sosEmergencyCardTitle => 'Emergency card';

  @override
  String get sosHistoryTitle => 'SOS history';

  @override
  String get sosHistoryEmptyTitle => 'No past alerts';

  @override
  String get sosHistoryEmptyMessage =>
      'Alerts that were resolved or ended appear here.';

  @override
  String get tasksTitle => 'Tasks';

  @override
  String get tasksNewTask => 'New task';

  @override
  String get tasksViewMine => 'My tasks';

  @override
  String get tasksViewFamily => 'Family';

  @override
  String get tasksViewDone => 'Done';

  @override
  String get tasksDueOverdue => 'Overdue';

  @override
  String get tasksDueToday => 'Today';

  @override
  String get tasksDueWeek => 'This week';

  @override
  String get tasksFilterDueLabel => 'Filter by due date';

  @override
  String get tasksFilterMemberLabel => 'Filter by family member';

  @override
  String get tasksFilterEveryone => 'Everyone';

  @override
  String get tasksSectionOverdue => 'Overdue';

  @override
  String get tasksSectionToday => 'Due today';

  @override
  String get tasksSectionUpcoming => 'Upcoming';

  @override
  String get tasksSectionNoDueDate => 'No due date';

  @override
  String tasksPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending tasks',
      one: '1 pending task',
      zero: 'No pending tasks',
    );
    return '$_temp0';
  }

  @override
  String tasksDoneCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count completed tasks',
      one: '1 completed task',
      zero: 'No completed tasks',
    );
    return '$_temp0';
  }

  @override
  String get tasksEmptyMineTitle => 'You\'re all caught up!';

  @override
  String get tasksEmptyMineMessage =>
      'No pending tasks for you. Enjoy the free time or add something new.';

  @override
  String get tasksEmptyFamilyTitle => 'No pending family tasks';

  @override
  String get tasksEmptyFamilyMessage => 'Assign a task to get everyone moving.';

  @override
  String tasksEmptyMemberTitle(String name) {
    return '$name has no pending tasks';
  }

  @override
  String get tasksEmptyOverdueTitle => 'Nothing overdue';

  @override
  String get tasksEmptyOverdueMessage => 'Great job staying on top of things.';

  @override
  String get tasksEmptyTodayTitle => 'Nothing due today';

  @override
  String get tasksEmptyTodayMessage =>
      'The day is clear. Plan ahead or take a break.';

  @override
  String get tasksEmptyWeekTitle => 'Nothing due this week';

  @override
  String get tasksEmptyWeekMessage =>
      'Add a due date to tasks to see them here.';

  @override
  String get tasksEmptyDoneTitle => 'No completed tasks yet';

  @override
  String tasksEmptyDoneMemberTitle(String name) {
    return '$name hasn\'t completed any tasks yet';
  }

  @override
  String get tasksEmptyDoneMessage => 'Completed tasks will show up here.';

  @override
  String get tasksStatusPending => 'Pending';

  @override
  String get tasksStatusDone => 'Done';

  @override
  String get tasksStatusOverdue => 'Overdue';

  @override
  String get tasksCategoryStudy => 'Study';

  @override
  String get tasksCategoryChore => 'Chore';

  @override
  String get tasksCategorySkill => 'Skill';

  @override
  String get tasksCategoryHealth => 'Health';

  @override
  String get tasksCategoryErrand => 'Errand';

  @override
  String get tasksCategoryOther => 'Other';

  @override
  String get tasksPriorityLow => 'Low';

  @override
  String get tasksPriorityMedium => 'Medium';

  @override
  String get tasksPriorityHigh => 'High';

  @override
  String tasksPrioritySemantics(String priority) {
    return '$priority priority';
  }

  @override
  String get tasksMarkDone => 'Mark as done';

  @override
  String get tasksMarkNotDone => 'Mark as not done';

  @override
  String get tasksReopen => 'Reopen task';

  @override
  String get tasksMarkedDone => 'Nice work! Task completed.';

  @override
  String get tasksReopened => 'Task reopened';

  @override
  String tasksDueSemantics(String date) {
    return 'Due $date';
  }

  @override
  String tasksOverdueSemantics(String date) {
    return 'Overdue, was due $date';
  }

  @override
  String tasksDueInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in $count days',
      one: 'in 1 day',
    );
    return '$_temp0';
  }

  @override
  String tasksAssignedToSemantics(String name) {
    return 'Assigned to $name';
  }

  @override
  String get tasksDetailTitle => 'Task';

  @override
  String get tasksInfoAssignee => 'Assigned to';

  @override
  String get tasksInfoDue => 'Due date';

  @override
  String get tasksInfoNoDueDate => 'No due date';

  @override
  String get tasksInfoCreatedBy => 'Created by';

  @override
  String get tasksInfoCompletedBy => 'Completed by';

  @override
  String get tasksInfoUpdated => 'Last updated';

  @override
  String tasksPersonAtTime(String name, String time) {
    return '$name · $time';
  }

  @override
  String tasksAssigneeMe(String name) {
    return '$name (you)';
  }

  @override
  String tasksCompleteNotAllowed(String name) {
    return 'Only $name or an admin can change the status of this task.';
  }

  @override
  String get tasksDeleteTitle => 'Delete this task?';

  @override
  String tasksDeleteMessage(String title) {
    return '\"$title\" will be removed for the whole family. This can\'t be undone.';
  }

  @override
  String get tasksDeleted => 'Task deleted';

  @override
  String get tasksFormNewTitle => 'New task';

  @override
  String get tasksFormEditTitle => 'Edit task';

  @override
  String get tasksFieldAssignee => 'Assign to';

  @override
  String get tasksFieldAssigneeRequired => 'Choose who should do this task';

  @override
  String get tasksAssigneeSelfOnly =>
      'Only admins can assign tasks to other family members.';

  @override
  String get tasksFieldTitle => 'Title';

  @override
  String get tasksFieldTitleHint => 'e.g. Finish maths homework';

  @override
  String get tasksFieldDescription => 'Details (optional)';

  @override
  String get tasksFieldDescriptionHint => 'Anything that helps to get it done';

  @override
  String get tasksFieldDueDate => 'Due date (optional)';

  @override
  String get tasksFieldCategory => 'Category';

  @override
  String get tasksFieldPriority => 'Priority';

  @override
  String get tasksCreate => 'Create task';

  @override
  String get tasksSaveChanges => 'Save changes';

  @override
  String get tasksCreated => 'Task created';

  @override
  String get tasksUpdated => 'Task updated';

  @override
  String get tasksEditNotAllowedTitle => 'You can\'t edit this task';

  @override
  String get tasksEditNotAllowedMessage =>
      'Only an admin or the person who created it can make changes.';

  @override
  String get tasksTemplatesTitle => 'Quick ideas';

  @override
  String tasksTemplatesFor(String name) {
    return 'Quick ideas for $name';
  }

  @override
  String get tasksTemplateHomeworkTitle => 'Finish homework';

  @override
  String get tasksTemplateHomeworkDescription =>
      'Complete today\'s homework and pack the school bag for tomorrow.';

  @override
  String get tasksTemplateTidyRoomTitle => 'Tidy your room';

  @override
  String get tasksTemplateTidyRoomDescription =>
      'Put toys and clothes away and make the bed.';

  @override
  String get tasksTemplateReadTitle => 'Read for 20 minutes';

  @override
  String get tasksTemplateReadDescription =>
      'Pick a favourite book and read for 20 minutes.';

  @override
  String get tasksTemplateLearnSkillTitle => 'Learn a new skill';

  @override
  String get tasksTemplateLearnSkillDescription =>
      'Spend 30 minutes on something new: coding, music, a language or a craft.';

  @override
  String get tasksTemplateHelpCookTitle => 'Help cook a family meal';

  @override
  String get tasksTemplateHelpCookDescription =>
      'Help plan, cook and clean up after one family meal.';

  @override
  String get tasksTemplateBudgetTitle => 'Budget practice';

  @override
  String get tasksTemplateBudgetDescription =>
      'Plan this week\'s pocket money: what to save and what to spend.';

  @override
  String get tasksTemplatePayBillsTitle => 'Pay the bills';

  @override
  String get tasksTemplatePayBillsDescription =>
      'Check and pay this month\'s electricity, water, phone and internet bills.';

  @override
  String get tasksTemplateCheckInTitle => 'Family check-in';

  @override
  String get tasksTemplateCheckInDescription =>
      'Call or sit with a family member and ask how they are doing.';

  @override
  String get tasksTemplateMedicineTitle => 'Take medicines on time';

  @override
  String get tasksTemplateMedicineDescription =>
      'Take the prescribed medicines at the right time, with water.';

  @override
  String get tasksTemplateWalkTitle => 'Take a gentle walk';

  @override
  String get tasksTemplateWalkDescription =>
      'Go for a 20-minute walk, ideally with someone from the family.';

  @override
  String get tasksFormerMember => 'Former member';

  @override
  String get tasksGoneTitle => 'This task is no longer available';

  @override
  String get tasksGoneMessage =>
      'It may have been deleted by someone in your family.';

  @override
  String get tasksBackToTasks => 'Back to tasks';

  @override
  String get tasksErrorGone => 'This task was deleted by someone else.';

  @override
  String get tasksErrorEditNotAllowed =>
      'Only an admin or the person who created this task can change or delete it.';

  @override
  String get tasksErrorCompleteNotAllowed =>
      'Only the person the task is assigned to or an admin can complete or reopen it.';

  @override
  String get tasksErrorAssignSelfOnly =>
      'You can only assign tasks to yourself. Ask an admin to assign tasks to others.';

  @override
  String get tasksErrorAssigneeNotInFamily =>
      'That person is no longer in your family. Please choose someone else.';

  @override
  String get tasksErrorAssigneeRemoved =>
      'The person this task was assigned to is no longer in your family. Assign it to someone else first.';

  @override
  String get tasksReopenAssigneeGone =>
      'This task can\'t be reopened because the person it was assigned to is no longer in your family. An admin or the task\'s creator can assign it to someone else first.';

  @override
  String get tasksAssigneeFormer =>
      'The person this task was assigned to is no longer in your family. You can keep it as it is or choose someone else.';

  @override
  String get tasksCreateNotAllowedTitle => 'You can\'t create tasks right now';

  @override
  String get tasksCreateNotAllowedMessage =>
      'Only members of a family can create tasks.';

  @override
  String get tasksHeaderSubtitleMine => 'Here\'s what\'s on your list';

  @override
  String get tasksHeaderSubtitleFamily =>
      'Everything your family is working on';

  @override
  String tasksHeaderSubtitleMember(String name) {
    return 'What $name is working on';
  }

  @override
  String get tasksHeaderDoneThisWeek => 'Done this week';

  @override
  String get tasksHeaderProgress => 'Weekly progress';

  @override
  String tasksHeaderCountAtLeast(String count) {
    return '$count+';
  }

  @override
  String get tasksFormSectionTask => 'What needs doing';

  @override
  String get validationRequired => 'This field is required';

  @override
  String get validationEmail => 'Enter a valid email address';

  @override
  String get validationPasswordLength =>
      'Password must be at least 8 characters';

  @override
  String get validationPasswordComplexity =>
      'Password must contain at least one letter and one number';

  @override
  String get validationPasswordMismatch => 'Passwords don\'t match';

  @override
  String validationMinLength(int min) {
    String _temp0 = intl.Intl.pluralLogic(
      min,
      locale: localeName,
      other: 'Enter at least $min characters',
      one: 'Enter at least 1 character',
    );
    return '$_temp0';
  }

  @override
  String validationMaxLength(int max) {
    String _temp0 = intl.Intl.pluralLogic(
      max,
      locale: localeName,
      other: 'Use at most $max characters',
      one: 'Use at most 1 character',
    );
    return '$_temp0';
  }

  @override
  String get validationAmount => 'Enter an amount greater than zero';

  @override
  String get validationAmountTooLarge => 'This amount is too large';

  @override
  String get validationAmountDecimals => 'Use at most 2 decimal places';

  @override
  String get validationPhone =>
      'Enter a valid phone number (6 to 15 digits, optional +country code)';

  @override
  String get validationOtp => 'Enter the 6-digit code';

  @override
  String get validationInviteCode => 'Invite codes have 8 letters and numbers';

  @override
  String get widgetPhotoPermissionDenied =>
      'FamilyHub can\'t open your camera or photos. Please allow access in your phone\'s Settings and try again.';

  @override
  String get widgetPhotoSourceUnavailable =>
      'This option isn\'t available on this device.';

  @override
  String get widgetStaleDataNotice =>
      'Couldn\'t refresh. Showing the last loaded information.';

  @override
  String widgetProgressLabel(String percent) {
    return '$percent complete';
  }

  @override
  String get widgetPhotoLabel => 'Photo';

  @override
  String get widgetClearDate => 'Clear date';
}
