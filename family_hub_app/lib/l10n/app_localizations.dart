import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Welcome screen: label / tooltip of the button that changes the app language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get authLanguageLabel;

  /// Title of the bottom sheet that lists the app languages (shown in their own script).
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get authLanguageSheetTitle;

  /// Welcome screen: main button to sign up and start a new family.
  ///
  /// In en, this message translates to:
  /// **'Create a family'**
  String get authWelcomeCreateFamily;

  /// Welcome screen: button to sign up and join an existing family with its 8-character invite code.
  ///
  /// In en, this message translates to:
  /// **'Join with invite code'**
  String get authWelcomeJoinFamily;

  /// Welcome screen: button that opens the log-in screen.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get authWelcomeHaveAccount;

  /// Welcome screen: short benefit line about family roles and task assignment.
  ///
  /// In en, this message translates to:
  /// **'Roles and tasks for everyone'**
  String get authWelcomeFeatureTasks;

  /// Welcome screen: short benefit line about the family money ledger.
  ///
  /// In en, this message translates to:
  /// **'A shared ledger and savings goals'**
  String get authWelcomeFeatureMoney;

  /// Welcome screen: short benefit line about SOS and medical emergency cards.
  ///
  /// In en, this message translates to:
  /// **'SOS alerts and emergency cards'**
  String get authWelcomeFeatureSafety;

  /// Shown on the welcome / log-in screen after the session expired on this device.
  ///
  /// In en, this message translates to:
  /// **'You were signed out. Please log in again.'**
  String get authSessionExpiredNotice;

  /// Title of the log-in screen.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLoginTitle;

  /// Subtitle under the log-in screen title.
  ///
  /// In en, this message translates to:
  /// **'Welcome back! Sign in to see your family.'**
  String get authLoginSubtitle;

  /// Label of the email field (log in, sign up, reset password).
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// Label of the password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// Link on the log-in screen to reset a forgotten password.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPasswordLink;

  /// Submit button of the log-in screen.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLoginButton;

  /// Log-in screen: text before the 'create an account' link.
  ///
  /// In en, this message translates to:
  /// **'New to FamilyHub?'**
  String get authLoginNoAccount;

  /// Link to the sign-up screen.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get authCreateAccountLink;

  /// Log-in screen: shown while the account is temporarily locked after 5 wrong passwords. time is a duration such as '14 minutes' or '30 seconds'.
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts. Try again in {time}.'**
  String authLoginLockedOut(String time);

  /// A remaining waiting time in seconds, inserted into other messages (e.g. 'Resend code in 42 seconds').
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String authCooldownSeconds(int count);

  /// A remaining waiting time in minutes, inserted into other messages (e.g. 'Try again in 14 minutes').
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String authCooldownMinutes(int count);

  /// Title of a hint card shown only when the app runs without a server (built-in demo data).
  ///
  /// In en, this message translates to:
  /// **'Demo mode'**
  String get authDemoTitle;

  /// Demo mode only: shows the demo account email and password.
  ///
  /// In en, this message translates to:
  /// **'Try the demo family: {email} / {password}'**
  String authDemoLoginHint(String email, String password);

  /// Demo mode only: button that fills the demo email and password into the log-in form.
  ///
  /// In en, this message translates to:
  /// **'Fill in'**
  String get authDemoFill;

  /// Demo mode only: tells testers which one-time code works.
  ///
  /// In en, this message translates to:
  /// **'Demo mode: the code is always {code}.'**
  String authDemoOtpHint(String code);

  /// Title of the sign-up screen in 'create a new family' mode.
  ///
  /// In en, this message translates to:
  /// **'Create your family'**
  String get authRegisterCreateTitle;

  /// Title of the sign-up screen in 'join with invite code' mode.
  ///
  /// In en, this message translates to:
  /// **'Join your family'**
  String get authRegisterJoinTitle;

  /// Sign-up screen subtitle in create mode.
  ///
  /// In en, this message translates to:
  /// **'Set up your account and your family. You will be its admin.'**
  String get authRegisterCreateSubtitle;

  /// Sign-up screen subtitle in join mode.
  ///
  /// In en, this message translates to:
  /// **'Create your account and join with the invite code a family admin gave you.'**
  String get authRegisterJoinSubtitle;

  /// Segmented switch option: create a new family. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get authModeCreate;

  /// Segmented switch option: join an existing family with an invite code. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get authModeJoin;

  /// Sign-up form section with the user's own details.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get authSectionAboutYou;

  /// Form section with the family details (name, country, currency, time zone) or the invite code.
  ///
  /// In en, this message translates to:
  /// **'Your family'**
  String get authSectionFamily;

  /// Label of the user's name field.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get authNameLabel;

  /// Label of the field where the password is typed a second time.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPasswordLabel;

  /// Hint under / inside a new-password field describing the password rules.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters with a letter and a number'**
  String get authPasswordHint;

  /// Label of the optional date-of-birth field on sign-up.
  ///
  /// In en, this message translates to:
  /// **'Date of birth (optional)'**
  String get authDateOfBirthLabel;

  /// Submit button of the sign-up screen.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegisterButton;

  /// Text before the 'Log in' link on the sign-up screen.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authHaveAccount;

  /// Link to the log-in screen.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLoginLink;

  /// Sign-up: the date of birth is below the country's age of digital consent. age is that minimum age (e.g. 13, 16, 18).
  ///
  /// In en, this message translates to:
  /// **'{age, plural, =1{You must be at least 1 year old to create your own account in this country.} other{You must be at least {age} years old to create your own account in this country. Ask a parent or guardian to add you to the family instead.}}'**
  String authSignupTooYoung(int age);

  /// Validation: a new password is longer than the server accepts (72 bytes; letters of many scripts count as 2-3 bytes each).
  ///
  /// In en, this message translates to:
  /// **'This password is too long. Please use a shorter one.'**
  String get authPasswordTooLong;

  /// Validation: a person or family name contains control or text-direction override characters (usually pasted from elsewhere).
  ///
  /// In en, this message translates to:
  /// **'Remove line breaks and hidden formatting characters from the name.'**
  String get authNameInvalidCharacters;

  /// Validation: a person or family name consists only of invisible characters.
  ///
  /// In en, this message translates to:
  /// **'Enter a name with at least one letter or number.'**
  String get authNameNeedsLetter;

  /// Shown under a form field that the server rejected for a reason the app did not check itself.
  ///
  /// In en, this message translates to:
  /// **'This entry wasn\'t accepted. Please check it and try again.'**
  String get authFieldRejected;

  /// Shown when the server asks to wait before trying again (codes, sign-up, password reset). time is a duration such as '14 minutes' or '30 seconds'.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {time}.'**
  String authTooManyAttemptsWait(String time);

  /// Consent checkbox text on sign-up. privacyPolicy and terms are replaced by tappable links (authPrivacyPolicy / authTermsOfService). Keep both placeholders.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to the {privacyPolicy} and the {terms}.'**
  String authConsentAgree(String privacyPolicy, String terms);

  /// Link text: the privacy policy document.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get authPrivacyPolicy;

  /// Link text: the terms of service document.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get authTermsOfService;

  /// Shown under the unticked consent checkbox.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Privacy Policy and the Terms of Service to continue.'**
  String get authConsentRequired;

  /// Error when a web link (privacy policy, terms) cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link. Please try again later.'**
  String get authLinkOpenFailed;

  /// Label of the family name field.
  ///
  /// In en, this message translates to:
  /// **'Family name'**
  String get authFamilyNameLabel;

  /// Example family name shown in the empty field. Use a family name that is common in the language.
  ///
  /// In en, this message translates to:
  /// **'e.g. The Sharma Family'**
  String get authFamilyNameHint;

  /// Label of the country picker of the family.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get authCountryLabel;

  /// Title of the searchable country list.
  ///
  /// In en, this message translates to:
  /// **'Select your country'**
  String get authCountryPickerTitle;

  /// Hint of the search field in the country list.
  ///
  /// In en, this message translates to:
  /// **'Search by name or code'**
  String get authCountrySearchHint;

  /// Empty state of the country search.
  ///
  /// In en, this message translates to:
  /// **'No country matches your search.'**
  String get authCountryNoResults;

  /// Label of the family currency picker.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get authCurrencyLabel;

  /// Label of the family time zone picker.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get authTimezoneLabel;

  /// Help text under the family form.
  ///
  /// In en, this message translates to:
  /// **'The currency and time zone are used for the family ledger and due dates. Admins can change them later.'**
  String get authFamilyFormHelp;

  /// Snackbar after choosing a country whose main language differs from the app language. language is the language name in its own script.
  ///
  /// In en, this message translates to:
  /// **'Use {language} in FamilyHub?'**
  String authSuggestLanguage(String language);

  /// Snackbar action: switch the app to the suggested language.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get authSuggestLanguageAction;

  /// Label of the family invite code field.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get authInviteCodeLabel;

  /// Hint inside the invite code field.
  ///
  /// In en, this message translates to:
  /// **'8 letters and numbers'**
  String get authInviteCodeHint;

  /// Help text under the invite code field.
  ///
  /// In en, this message translates to:
  /// **'Ask a family admin for the code. Admins find it in the family settings.'**
  String get authInviteCodeHelp;

  /// Title of the email verification screen.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get authVerifyTitle;

  /// Email verification screen explanation.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}. Enter it below to confirm your email address.'**
  String authVerifyMessage(String email);

  /// Label of the one-time code field.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get authOtpLabel;

  /// Submit button of the email verification screen.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get authVerifyButton;

  /// Button that sends a new one-time code by email.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get authResendCode;

  /// Disabled resend button while the cooldown runs. time is a duration such as '42 seconds'.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {time}'**
  String authResendCodeIn(String time);

  /// Snackbar after a new one-time code was sent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way. Check your inbox and spam folder.'**
  String get authCodeSent;

  /// Snackbar after the email was verified.
  ///
  /// In en, this message translates to:
  /// **'Email verified. Welcome to FamilyHub!'**
  String get authEmailVerified;

  /// Button that signs out so the user can sign in with a different account.
  ///
  /// In en, this message translates to:
  /// **'Use another account'**
  String get authUseAnotherAccount;

  /// Title of the forgot / reset password screen.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get authForgotTitle;

  /// Reset password step 1 explanation.
  ///
  /// In en, this message translates to:
  /// **'Enter the email of your account. We\'ll send you a 6-digit code to set a new password.'**
  String get authForgotEmailMessage;

  /// Reset password step 1 submit button.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// Reset password step 2 explanation. Deliberately does not confirm that the account exists.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for {email}, we sent it a 6-digit code. Enter the code and your new password.'**
  String authForgotCodeMessage(String email);

  /// Reset password step 2: go back and type another email.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get authChangeEmail;

  /// Label of the new password field.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPasswordLabel;

  /// Label of the field repeating the new password.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get authConfirmNewPasswordLabel;

  /// Reset password step 2 submit button.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get authResetButton;

  /// Snackbar after a successful password reset.
  ///
  /// In en, this message translates to:
  /// **'Your password was changed. Log in with your new password.'**
  String get authPasswordResetSuccess;

  /// Title of the screen for signed-in users who are not in a family yet.
  ///
  /// In en, this message translates to:
  /// **'Set up your family'**
  String get authFamilySetupTitle;

  /// Family setup screen greeting.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}! Create a new family or join one with an invite code.'**
  String authFamilySetupGreeting(String name);

  /// Shows which account is signed in.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String authSignedInAs(String email);

  /// Submit button: create the family.
  ///
  /// In en, this message translates to:
  /// **'Create family'**
  String get authCreateFamilyButton;

  /// Submit button: join the family with the invite code.
  ///
  /// In en, this message translates to:
  /// **'Join family'**
  String get authJoinFamilyButton;

  /// Button / tooltip that signs out of this device.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get authLogout;

  /// Snackbar after the family was created.
  ///
  /// In en, this message translates to:
  /// **'Your family is ready!'**
  String get authFamilyCreated;

  /// Snackbar after joining a family.
  ///
  /// In en, this message translates to:
  /// **'Welcome to {family}!'**
  String authFamilyJoined(String family);

  /// Product name. Usually NOT translated (keep the brand), transliterate only if your market requires it.
  ///
  /// In en, this message translates to:
  /// **'FamilyHub'**
  String get appName;

  /// Short marketing line shown under the app name on splash / welcome screens.
  ///
  /// In en, this message translates to:
  /// **'Your family, organised like a great team'**
  String get appTagline;

  /// Generic acknowledgement button.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Cancel button / action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Save button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Delete button / action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Edit button / action.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Button to retry a failed request.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Close a dialog, sheet or screen.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Finish a flow or dismiss after completion.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Go to the next step.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// Go to the previous step / screen.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// Add button (verb).
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// Remove button (verb).
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Confirm button in dialogs.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// Shown while content is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Link on a section header that opens the full list.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get commonSeeAll;

  /// Button at the end of a paginated list.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get commonLoadMore;

  /// Placeholder when a value is not set / empty selection.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// Hint on optional form fields.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// Place a phone call (verb).
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get commonCall;

  /// Copy to clipboard (verb).
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// Confirmation after copying to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// Share (verb).
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// Pick a photo with the camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get commonCamera;

  /// Pick a photo from the device's photo library.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get commonGallery;

  /// Shown while a photo is uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get commonUploading;

  /// No description provided for @commonRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get commonRemovePhoto;

  /// No description provided for @commonChoosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose photo'**
  String get commonChoosePhoto;

  /// Banner shown when the last request failed because there is no connection.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing the last saved data.'**
  String get commonOffline;

  /// No description provided for @commonToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// No description provided for @commonYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get commonYesterday;

  /// No description provided for @commonTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get commonTomorrow;

  /// Generic error title.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonSomethingWentWrong;

  /// Generic empty-state title.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonNothingHere;

  /// Clear a field / selection (verb).
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get commonSelectDate;

  /// Filter option meaning 'everything'.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// Relative time for less than a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get commonJustNow;

  /// Relative time in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String commonMinutesAgo(int count);

  /// Relative time in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String commonHoursAgo(int count);

  /// Relative time in days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String commonDaysAgo(int count);

  /// Shown when a non-admin member tries an admin-only action.
  ///
  /// In en, this message translates to:
  /// **'Only family admins can do this'**
  String get commonAdminOnly;

  /// Snackbar after a successful save.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get commonSaved;

  /// Snackbar after a successful delete.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get commonDeleted;

  /// Generic confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get commonAreYouSure;

  /// Refers to the signed-in member, e.g. in an assignee picker ('Me').
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get commonMe;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get commonSend;

  /// No description provided for @commonSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get commonSubmit;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get commonView;

  /// Value that is not known (e.g. unknown member).
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// Profile / card field that has no value yet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get commonNotSet;

  /// No description provided for @commonShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get commonShowPassword;

  /// No description provided for @commonHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get commonHidePassword;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @commonDiscardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get commonDiscardChangesTitle;

  /// No description provided for @commonDiscardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'Your unsaved changes will be lost.'**
  String get commonDiscardChangesMessage;

  /// Secondary line under a generic error.
  ///
  /// In en, this message translates to:
  /// **'Please try again in a moment.'**
  String get commonTryAgainLater;

  /// Dashboard greeting with the member's first name. 'period' is the time of day: morning (5-12 h), afternoon (12-17 h), evening (17-22 h) or night (other). At night we greet with a neutral 'Hello' (in many languages 'Good night' means goodbye).
  ///
  /// In en, this message translates to:
  /// **'{period, select, morning{Good morning, {name}} afternoon{Good afternoon, {name}} evening{Good evening, {name}} other{Hello, {name}}}'**
  String dashboardGreeting(String period, String name);

  /// Dashboard greeting when the member's name is unknown. 'period' as in dashboardGreeting.
  ///
  /// In en, this message translates to:
  /// **'{period, select, morning{Good morning} afternoon{Good afternoon} evening{Good evening} other{Hello}}'**
  String dashboardGreetingNoName(String period);

  /// Line under the greeting: the family name and the member's designation (company-style title, e.g. 'Head of Family') or role.
  ///
  /// In en, this message translates to:
  /// **'{family} · {title}'**
  String dashboardFamilyAndTitle(String family, String title);

  /// Screen-reader label of the dashboard's loading placeholder.
  ///
  /// In en, this message translates to:
  /// **'Loading your family dashboard…'**
  String get dashboardLoading;

  /// Title of the notice shown when the dashboard is the copy saved on the phone (the server could not be reached).
  ///
  /// In en, this message translates to:
  /// **'Showing saved data'**
  String get dashboardOfflineTitle;

  /// Second line of the saved-data notice. 'time' is a relative time such as '5 minutes ago' or a date.
  ///
  /// In en, this message translates to:
  /// **'Last updated {time}. Pull down to refresh.'**
  String dashboardOfflineUpdated(String time);

  /// Section title above the active SOS alerts of the family (shown only while there are any).
  ///
  /// In en, this message translates to:
  /// **'Needs help now'**
  String get dashboardSosTitle;

  /// Section title (screen readers) of the row of shortcut buttons.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get dashboardQuickActionsTitle;

  /// Quick action button: create a task.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get dashboardActionAddTask;

  /// Quick action button: record an expense in the family ledger.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get dashboardActionAddExpense;

  /// Quick action button: post a notice on the family notice board.
  ///
  /// In en, this message translates to:
  /// **'Post notice'**
  String get dashboardActionPostNotice;

  /// Quick action button: open the family's emergency (medical) cards.
  ///
  /// In en, this message translates to:
  /// **'Emergency cards'**
  String get dashboardActionEmergencyCards;

  /// Title of the checklist card shown to new families.
  ///
  /// In en, this message translates to:
  /// **'Get your family started'**
  String get dashboardGettingStartedTitle;

  /// Subtitle of the getting-started checklist.
  ///
  /// In en, this message translates to:
  /// **'A few steps and everyone knows who does what.'**
  String get dashboardGettingStartedMessage;

  /// Getting-started step: add family members (admins only).
  ///
  /// In en, this message translates to:
  /// **'Add your family members'**
  String get dashboardStepAddMembers;

  /// Getting-started step: create a task.
  ///
  /// In en, this message translates to:
  /// **'Create the first task'**
  String get dashboardStepFirstTask;

  /// Getting-started step: create a savings goal (admins only).
  ///
  /// In en, this message translates to:
  /// **'Set a savings goal'**
  String get dashboardStepFirstGoal;

  /// Getting-started step: post a notice on the notice board.
  ///
  /// In en, this message translates to:
  /// **'Post the first notice'**
  String get dashboardStepFirstNotice;

  /// Screen-reader label of a completed getting-started step.
  ///
  /// In en, this message translates to:
  /// **'{step} (done)'**
  String dashboardStepDone(String step);

  /// Section title: the signed-in member's pending tasks.
  ///
  /// In en, this message translates to:
  /// **'My tasks'**
  String get dashboardMyTasksTitle;

  /// Shown when the member has no pending tasks.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get dashboardMyTasksEmptyTitle;

  /// Second line when the member has no pending tasks.
  ///
  /// In en, this message translates to:
  /// **'Nothing pending for you right now.'**
  String get dashboardMyTasksEmptyMessage;

  /// Link under the task preview when the member has more pending tasks than shown; opens the Tasks tab.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more pending task} other{{count} more pending tasks}}'**
  String dashboardMyTasksMore(int count);

  /// Section title: every member with their task progress (like a team board).
  ///
  /// In en, this message translates to:
  /// **'Family board'**
  String get dashboardFamilyBoardTitle;

  /// Badge on the signed-in member's own card on the family board.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get dashboardMemberYou;

  /// Chip on a member's card when they have no pending tasks.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get dashboardMemberAllClear;

  /// Chip on a member's card: number of their pending tasks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pending} other{{count} pending}}'**
  String dashboardMemberPending(int count);

  /// Chip on a member's card: number of their overdue tasks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 overdue} other{{count} overdue}}'**
  String dashboardMemberOverdue(int count);

  /// Chip on a member's card: tasks they completed since Monday.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 done this week} other{{count} done this week}}'**
  String dashboardMemberDoneThisWeek(int count);

  /// Section title: active family savings goals.
  ///
  /// In en, this message translates to:
  /// **'Savings goals'**
  String get dashboardGoalsTitle;

  /// Shown when the family has no active savings goal.
  ///
  /// In en, this message translates to:
  /// **'No active goals'**
  String get dashboardGoalsEmptyTitle;

  /// Empty goals hint for admins (who can create goals).
  ///
  /// In en, this message translates to:
  /// **'Save together for a holiday, a new phone or a rainy day.'**
  String get dashboardGoalsEmptyAdmin;

  /// Empty goals hint for members (who cannot create goals).
  ///
  /// In en, this message translates to:
  /// **'When a family admin sets a savings goal, it shows up here.'**
  String get dashboardGoalsEmptyMember;

  /// Button: create a savings goal.
  ///
  /// In en, this message translates to:
  /// **'New goal'**
  String get dashboardNewGoal;

  /// Section title: income, expenses and balance of the current month.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get dashboardMonthTitle;

  /// Section title: newest notices of the family notice board.
  ///
  /// In en, this message translates to:
  /// **'Latest notices'**
  String get dashboardNoticesTitle;

  /// Shown when the notice board is empty.
  ///
  /// In en, this message translates to:
  /// **'No notices yet'**
  String get dashboardNoticesEmptyTitle;

  /// Second line when the notice board is empty.
  ///
  /// In en, this message translates to:
  /// **'Share plans, news and reminders with everyone.'**
  String get dashboardNoticesEmptyMessage;

  /// Label under the number of the signed-in member's pending tasks in the colourful header card (short).
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get dashboardHeroMyTasks;

  /// Label under the number of family members in the colourful header card.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get dashboardHeroMembers;

  /// Label under the number of active savings goals in the colourful header card.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get dashboardHeroGoals;

  /// Header stat value meaning 'this many or more' (the dashboard only receives the first few active goals). 'count' is an already formatted number.
  ///
  /// In en, this message translates to:
  /// **'{count}+'**
  String dashboardHeroAtLeast(String count);

  /// Title of the screen that lists every family member's emergency card.
  ///
  /// In en, this message translates to:
  /// **'Emergency cards'**
  String get emergencyCardListTitle;

  /// Short explanation at the top of the emergency cards list.
  ///
  /// In en, this message translates to:
  /// **'Health details and contacts for each family member. Open a card to show it to a doctor or first responder.'**
  String get emergencyCardListIntro;

  /// Button on the emergency cards list that dials the country's emergency number (e.g. 112). FamilyHub itself never contacts emergency services.
  ///
  /// In en, this message translates to:
  /// **'In danger? Call {number}'**
  String emergencyCardCallEmergencyNumber(String number);

  /// Title of one member's emergency card screen.
  ///
  /// In en, this message translates to:
  /// **'Emergency card'**
  String get emergencyCardTitle;

  /// Title of the emergency card edit form.
  ///
  /// In en, this message translates to:
  /// **'Edit emergency card'**
  String get emergencyCardEditTitle;

  /// Button / tooltip that opens the emergency card edit form.
  ///
  /// In en, this message translates to:
  /// **'Edit card'**
  String get emergencyCardEditAction;

  /// Button on an empty emergency card that opens the edit form.
  ///
  /// In en, this message translates to:
  /// **'Fill in card'**
  String get emergencyCardFillIn;

  /// Label of the blood group (e.g. A+, O-).
  ///
  /// In en, this message translates to:
  /// **'Blood group'**
  String get emergencyCardBloodGroup;

  /// Blood group option / label when the blood group is not known.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get emergencyCardBloodGroupUnknown;

  /// Screen-reader label of the blood group badge.
  ///
  /// In en, this message translates to:
  /// **'Blood group {group}'**
  String emergencyCardBloodGroupSemantics(String group);

  /// Section title: things the member is allergic to.
  ///
  /// In en, this message translates to:
  /// **'Allergies'**
  String get emergencyCardAllergies;

  /// Section title: medicines the member takes regularly.
  ///
  /// In en, this message translates to:
  /// **'Medications'**
  String get emergencyCardMedications;

  /// Section title: long-term illnesses or conditions (e.g. asthma, diabetes).
  ///
  /// In en, this message translates to:
  /// **'Medical conditions'**
  String get emergencyCardConditions;

  /// Screen-reader label of an allergy warning chip.
  ///
  /// In en, this message translates to:
  /// **'Allergy: {item}'**
  String emergencyCardAllergySemantics(String item);

  /// Section title: the member's regular doctor.
  ///
  /// In en, this message translates to:
  /// **'Doctor'**
  String get emergencyCardDoctor;

  /// Form field label.
  ///
  /// In en, this message translates to:
  /// **'Doctor\'s name'**
  String get emergencyCardDoctorName;

  /// Form field label.
  ///
  /// In en, this message translates to:
  /// **'Doctor\'s phone'**
  String get emergencyCardDoctorPhone;

  /// Section title: health insurance details.
  ///
  /// In en, this message translates to:
  /// **'Health insurance'**
  String get emergencyCardInsurance;

  /// Form field label: name of the health insurance company.
  ///
  /// In en, this message translates to:
  /// **'Insurance provider'**
  String get emergencyCardInsuranceProvider;

  /// Form field label: health insurance policy number.
  ///
  /// In en, this message translates to:
  /// **'Policy number'**
  String get emergencyCardPolicyNumber;

  /// Tooltip of the button that copies the insurance policy number.
  ///
  /// In en, this message translates to:
  /// **'Copy policy number'**
  String get emergencyCardCopyPolicyNumber;

  /// Snackbar after copying the policy number.
  ///
  /// In en, this message translates to:
  /// **'Policy number copied'**
  String get emergencyCardPolicyNumberCopied;

  /// Section title: people to call in an emergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency contacts'**
  String get emergencyCardContacts;

  /// Form field label: emergency contact's name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get emergencyCardContactName;

  /// Form field label: emergency contact's phone number.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get emergencyCardContactPhone;

  /// Form field label: how the contact is related (e.g. uncle, neighbour).
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get emergencyCardContactRelation;

  /// Hint of the relation field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Uncle, Neighbour'**
  String get emergencyCardContactRelationHint;

  /// Heading of one emergency contact in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Contact {number}'**
  String emergencyCardContactNumber(int number);

  /// Button that adds another emergency contact to the form.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get emergencyCardAddContact;

  /// Tooltip / screen-reader label of the button that removes one emergency contact from the form.
  ///
  /// In en, this message translates to:
  /// **'Remove contact {number}'**
  String emergencyCardRemoveContact(int number);

  /// Shown when the maximum number of emergency contacts is reached.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {max} contacts.'**
  String emergencyCardContactsLimit(int max);

  /// Hint in the contacts section of the edit form (privacy: contacts are third parties).
  ///
  /// In en, this message translates to:
  /// **'Let the people you add know that they are your emergency contacts.'**
  String get emergencyCardContactsNotice;

  /// Shown for an emergency contact that has no phone number.
  ///
  /// In en, this message translates to:
  /// **'No phone number'**
  String get emergencyCardNoPhone;

  /// Screen-reader label / tooltip of a call button.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String emergencyCardCallPerson(String name);

  /// Snackbar when the phone app cannot be opened; shows the number so it can be dialled manually.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start a call on this device. The number is {phone}.'**
  String emergencyCardCallFailed(String phone);

  /// Section title / form field: free-text notes for responders.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get emergencyCardNotes;

  /// Hint of the notes field.
  ///
  /// In en, this message translates to:
  /// **'Anything else a responder should know'**
  String get emergencyCardNotesHint;

  /// Shown for a card section that has no entries (it may be unknown, not necessarily 'none').
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get emergencyCardNotRecorded;

  /// When the card was last saved.
  ///
  /// In en, this message translates to:
  /// **'Last updated {date}'**
  String emergencyCardLastUpdated(String date);

  /// Shown on a card that was never filled in.
  ///
  /// In en, this message translates to:
  /// **'No emergency details yet'**
  String get emergencyCardEmptyTitle;

  /// Shown on an empty card for someone who can edit it.
  ///
  /// In en, this message translates to:
  /// **'Add the blood group, allergies and emergency contacts so your family can help quickly.'**
  String get emergencyCardEmptyMessage;

  /// Shown on an empty card for someone who cannot edit it.
  ///
  /// In en, this message translates to:
  /// **'Only this member or a family admin can fill in this card.'**
  String get emergencyCardEmptyReadOnly;

  /// Shown when opening the edit form without permission.
  ///
  /// In en, this message translates to:
  /// **'Only this member or a family admin can edit this card.'**
  String get emergencyCardNoEditPermission;

  /// Button that opens a full-screen, large-text version of the card to hand the phone to a doctor or paramedic.
  ///
  /// In en, this message translates to:
  /// **'Show to responder'**
  String get emergencyCardShowToResponder;

  /// Heading of the full-screen responder view.
  ///
  /// In en, this message translates to:
  /// **'Emergency medical information'**
  String get emergencyCardResponderHint;

  /// Tooltip of the close button of the full-screen responder view.
  ///
  /// In en, this message translates to:
  /// **'Close responder view'**
  String get emergencyCardResponderClose;

  /// Hint when the card is shown from the copy saved on this phone because there is no connection.
  ///
  /// In en, this message translates to:
  /// **'Offline copy from {time}. It may be out of date.'**
  String emergencyCardOfflineCopy(String time);

  /// Short badge for a card shown from the copy saved on this phone.
  ///
  /// In en, this message translates to:
  /// **'Offline copy'**
  String get emergencyCardOfflineCopyShort;

  /// Warning at the top of the edit form when the card was loaded from the offline copy.
  ///
  /// In en, this message translates to:
  /// **'You\'re editing an offline copy. Saving needs an internet connection.'**
  String get emergencyCardOfflineEditWarning;

  /// Completeness of a card in the list (key details: blood group, contact, doctor, insurance).
  ///
  /// In en, this message translates to:
  /// **'{filled} of {total} key details'**
  String emergencyCardCompleteness(int filled, int total);

  /// Completeness label of a fully filled-in card.
  ///
  /// In en, this message translates to:
  /// **'All key details added'**
  String get emergencyCardComplete;

  /// Completeness label of a card that was never saved.
  ///
  /// In en, this message translates to:
  /// **'Not filled in yet'**
  String get emergencyCardNotStarted;

  /// Lists the key details that are still missing, e.g. 'Missing: Doctor, Health insurance'.
  ///
  /// In en, this message translates to:
  /// **'Missing: {sections}'**
  String emergencyCardMissing(String sections);

  /// Shown in the list when one member's card could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this card'**
  String get emergencyCardLoadFailed;

  /// Name of the 'emergency contact' key detail in the 'Missing: …' list.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get emergencyCardSectionContacts;

  /// Health-data disclaimer shown on the edit form and the card.
  ///
  /// In en, this message translates to:
  /// **'This card is for emergencies and is not medical advice. Keep it up to date and confirm details with a doctor.'**
  String get emergencyCardDisclaimer;

  /// Privacy note on the edit form.
  ///
  /// In en, this message translates to:
  /// **'Everyone in your family can see this card. Health details are stored encrypted.'**
  String get emergencyCardPrivacyNote;

  /// Snackbar when the edit form has invalid fields.
  ///
  /// In en, this message translates to:
  /// **'Please check the highlighted fields.'**
  String get emergencyCardFixErrors;

  /// Snackbar after saving the card.
  ///
  /// In en, this message translates to:
  /// **'Emergency card saved'**
  String get emergencyCardSaved;

  /// Label of the input that adds an allergy.
  ///
  /// In en, this message translates to:
  /// **'Add an allergy'**
  String get emergencyCardAllergyLabel;

  /// Hint of the allergy input.
  ///
  /// In en, this message translates to:
  /// **'e.g. Peanuts, Penicillin'**
  String get emergencyCardAllergyHint;

  /// Label of the input that adds a medication.
  ///
  /// In en, this message translates to:
  /// **'Add a medication'**
  String get emergencyCardMedicationLabel;

  /// Hint of the medication input.
  ///
  /// In en, this message translates to:
  /// **'e.g. Metformin 500 mg twice a day'**
  String get emergencyCardMedicationHint;

  /// Label of the input that adds a medical condition.
  ///
  /// In en, this message translates to:
  /// **'Add a condition'**
  String get emergencyCardConditionLabel;

  /// Hint of the medical condition input.
  ///
  /// In en, this message translates to:
  /// **'e.g. Asthma, Type 2 diabetes'**
  String get emergencyCardConditionHint;

  /// Tooltip / screen-reader label of the button next to a list input that adds the typed entry.
  ///
  /// In en, this message translates to:
  /// **'Add {item}'**
  String emergencyCardAddItem(String item);

  /// Tooltip / screen-reader label of the delete button on a list entry chip.
  ///
  /// In en, this message translates to:
  /// **'Remove {item}'**
  String emergencyCardRemoveItem(String item);

  /// Counter under a list input, e.g. '3 of 20'.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max}'**
  String emergencyCardItemCount(int count, int max);

  /// Shown when a list (allergies, medications, conditions) is full.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {max} entries.'**
  String emergencyCardListFull(int max);

  /// Shown when the typed entry is already in the list.
  ///
  /// In en, this message translates to:
  /// **'Already in the list'**
  String get emergencyCardDuplicateItem;

  /// Title shown instead of an emergency card when the member no longer exists (removed from the family) or the link is wrong.
  ///
  /// In en, this message translates to:
  /// **'This card is not available'**
  String get emergencyCardNotFoundTitle;

  /// Explanation below emergencyCardNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'The member may have been removed from your family, or the link is out of date.'**
  String get emergencyCardNotFoundMessage;

  /// Button that opens the list of every family member's emergency card.
  ///
  /// In en, this message translates to:
  /// **'All emergency cards'**
  String get emergencyCardBackToList;

  /// Warning in the edit form when someone else saved the same card after the form was opened.
  ///
  /// In en, this message translates to:
  /// **'This card was updated while you were editing. Saving replaces that version with yours.'**
  String get emergencyCardChangedWhileEditing;

  /// Separator placed between the items of a short inline list, e.g. 'Missing: Doctor, Health insurance'. Use the language's list separator (Arabic: '، '). Keep any trailing space.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get emergencyCardListSeparator;

  /// An emergency contact with their relation in the responder view, e.g. 'Ravi · Uncle'.
  ///
  /// In en, this message translates to:
  /// **'{name} · {relation}'**
  String emergencyCardPersonWithRelation(String name, String relation);

  /// Label under a count in the emergency cards header, e.g. '4 Family members'.
  ///
  /// In en, this message translates to:
  /// **'Family members'**
  String get emergencyCardStatMembers;

  /// Label under a count in the emergency cards header: how many cards have every key detail, e.g. '2 Cards complete'.
  ///
  /// In en, this message translates to:
  /// **'Cards complete'**
  String get emergencyCardStatComplete;

  /// Request failed because the device is offline or the server is unreachable.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check your connection and try again.'**
  String get errorNetwork;

  /// Request timed out.
  ///
  /// In en, this message translates to:
  /// **'The server is taking too long to respond. Please try again.'**
  String get errorTimeout;

  /// Fallback for any unexpected error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorUnknown;

  /// HTTP 5xx / INTERNAL_ERROR.
  ///
  /// In en, this message translates to:
  /// **'Our server ran into a problem. Please try again in a moment.'**
  String get errorServer;

  /// UNAUTHORIZED: missing or invalid access token.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to continue.'**
  String get errorUnauthorized;

  /// Token refresh failed; the user was signed out.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get errorSessionExpired;

  /// FORBIDDEN: e.g. a non-admin tried an admin-only action.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get errorForbidden;

  /// NOT_FOUND: resource missing or belongs to another family.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that. It may have been deleted.'**
  String get errorNotFound;

  /// VALIDATION_ERROR returned by the server.
  ///
  /// In en, this message translates to:
  /// **'Some details are missing or invalid. Please check and try again.'**
  String get errorValidation;

  /// INVALID_CREDENTIALS on login / password confirmation. Never say which one is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get errorInvalidCredentials;

  /// EMAIL_TAKEN on registration.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Try signing in instead.'**
  String get errorEmailTaken;

  /// INVALID_OTP: wrong 6-digit verification code.
  ///
  /// In en, this message translates to:
  /// **'That code is incorrect. Please check and try again.'**
  String get errorInvalidOtp;

  /// OTP_EXPIRED: code expired or too many attempts.
  ///
  /// In en, this message translates to:
  /// **'This code has expired or was tried too many times. Request a new one.'**
  String get errorOtpExpired;

  /// INVALID_INVITE_CODE when joining a family.
  ///
  /// In en, this message translates to:
  /// **'This invite code isn\'t valid. Ask your family admin for the current code.'**
  String get errorInvalidInviteCode;

  /// ALREADY_IN_FAMILY when creating or joining a family.
  ///
  /// In en, this message translates to:
  /// **'You\'re already a member of a family.'**
  String get errorAlreadyInFamily;

  /// NO_FAMILY: the user has no family (removed or never joined).
  ///
  /// In en, this message translates to:
  /// **'You\'re not part of a family yet. Create one or join with an invite code.'**
  String get errorNoFamily;

  /// MEMBER_EMAIL_EXISTS when adding a member.
  ///
  /// In en, this message translates to:
  /// **'A family member with this email already exists.'**
  String get errorMemberEmailExists;

  /// LAST_ADMIN: action would leave the family without an admin.
  ///
  /// In en, this message translates to:
  /// **'Your family needs at least one admin. Make someone else an admin first.'**
  String get errorLastAdmin;

  /// SOS_NOT_ACTIVE: the alert is resolved or expired.
  ///
  /// In en, this message translates to:
  /// **'This SOS alert has already ended.'**
  String get errorSosNotActive;

  /// GUARDIAN_CONSENT_REQUIRED when adding a minor without consent.
  ///
  /// In en, this message translates to:
  /// **'A parent or guardian must give consent to add a member of this age.'**
  String get errorGuardianConsentRequired;

  /// TOO_MANY_REQUESTS (rate limit, login lockout, OTP resend cooldown). seconds = details.retryAfterSeconds, 0 when unknown.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =0{Too many attempts. Please wait a moment and try again.} =1{Too many attempts. Please try again in 1 second.} other{Too many attempts. Please try again in {seconds} seconds.}}'**
  String errorTooManyRequests(int seconds);

  /// LOCATION_SHARING_DISABLED: the member's sharing mode forbids this update.
  ///
  /// In en, this message translates to:
  /// **'Location sharing is turned off. Change it in Settings > Location to share your location.'**
  String get errorLocationSharingDisabled;

  /// BAD_REQUEST: malformed request or invalid id.
  ///
  /// In en, this message translates to:
  /// **'The request couldn\'t be processed. Please try again.'**
  String get errorBadRequest;

  /// Title of the screen that lists everyone in the family.
  ///
  /// In en, this message translates to:
  /// **'Family members'**
  String get familyMembersTitle;

  /// Number of people in the family, e.g. above the member list or in family settings.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No members} =1{1 member} other{{count} members}}'**
  String familyMembersCount(int count);

  /// Button / screen title to add a person to the family (verb).
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get familyAddMember;

  /// Empty state title of the member list.
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get familyMembersEmptyTitle;

  /// Empty state message of the member list.
  ///
  /// In en, this message translates to:
  /// **'Add the people in your family, including children and elders who don\'t use a phone.'**
  String get familyMembersEmptyMessage;

  /// Small badge next to the signed-in person in member lists.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get familyYouBadge;

  /// Badge for a member who has no app account (managed by an admin).
  ///
  /// In en, this message translates to:
  /// **'No account'**
  String get familyNoAccountBadge;

  /// Badge for a member who was invited by email but has not joined yet.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get familyInvitedBadge;

  /// Age badge: age group label and age, e.g. 'Child · 10 years'.
  ///
  /// In en, this message translates to:
  /// **'{group} · {age}'**
  String familyAgeGroupWithAge(String group, String age);

  /// Tooltip of the icon button that opens the family settings.
  ///
  /// In en, this message translates to:
  /// **'Family settings'**
  String get familySettingsTooltip;

  /// Screen-reader hint on a member row that opens the member's details.
  ///
  /// In en, this message translates to:
  /// **'Open details'**
  String get familyOpenMemberHint;

  /// Button that opens the email app to write to the member (verb).
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get familyEmailAction;

  /// Error when the dialer can't be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the phone app.'**
  String get familyCannotOpenPhone;

  /// Error when no email app can be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open an email app.'**
  String get familyCannotOpenEmail;

  /// Error when no maps app / browser can be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the map.'**
  String get familyCannotOpenMap;

  /// Section title for the member's information rows.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get familyDetailsSection;

  /// Section title for the buttons at the end of the member screen.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get familyActionsSection;

  /// Label of the age row.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get familyInfoAge;

  /// Label of the date-of-birth row / field.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get familyInfoDateOfBirth;

  /// Label of the gender row / field.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get familyInfoGender;

  /// Label of the role (admin / member) row / field.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get familyInfoRole;

  /// Label of the member's family title, like a job title in a company (e.g. 'Finance Head').
  ///
  /// In en, this message translates to:
  /// **'Designation'**
  String get familyInfoDesignation;

  /// Label of the phone number row.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get familyInfoPhone;

  /// Label of the email address row.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get familyInfoEmail;

  /// Label of the row showing the member's location sharing mode.
  ///
  /// In en, this message translates to:
  /// **'Location sharing'**
  String get familyInfoLocationSharing;

  /// Label of the row showing whether the member has an app account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get familyInfoAccount;

  /// Label of the row showing whether a parent / guardian consented for a minor.
  ///
  /// In en, this message translates to:
  /// **'Guardian consent'**
  String get familyInfoGuardianConsent;

  /// Label of the row with the member's last shared location.
  ///
  /// In en, this message translates to:
  /// **'Last known location'**
  String get familyInfoLastLocation;

  /// When the last location was recorded, e.g. 'Updated 12 minutes ago'.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String familyLastLocationUpdated(String time);

  /// Account status: the member can sign in to the app.
  ///
  /// In en, this message translates to:
  /// **'Has their own account'**
  String get familyAccountActive;

  /// Account status: invited but no account yet.
  ///
  /// In en, this message translates to:
  /// **'Invited by email, hasn\'t joined yet'**
  String get familyAccountInvited;

  /// Account status: profile managed by admins (e.g. a young child) without an app account.
  ///
  /// In en, this message translates to:
  /// **'Managed profile, no account'**
  String get familyAccountManaged;

  /// Guardian consent status: consent was recorded.
  ///
  /// In en, this message translates to:
  /// **'Given'**
  String get familyGuardianConsentGiven;

  /// Guardian consent status: no consent recorded yet.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get familyGuardianConsentMissing;

  /// Button that opens the member's last location in a maps app (verb).
  ///
  /// In en, this message translates to:
  /// **'Open map'**
  String get familyOpenMap;

  /// Button that opens the screen to change a setting (verb).
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get familyChangeAction;

  /// Button that opens the member's medical emergency card.
  ///
  /// In en, this message translates to:
  /// **'Emergency card'**
  String get familyEmergencyCard;

  /// Button that creates a task for this member (verb).
  ///
  /// In en, this message translates to:
  /// **'Assign a task'**
  String get familyAssignTask;

  /// Button that opens the edit form of a member (verb).
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get familyEditDetails;

  /// Destructive button that removes a member from the family (verb).
  ///
  /// In en, this message translates to:
  /// **'Remove from family'**
  String get familyRemoveMember;

  /// Title of the confirmation dialog before removing a member.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String familyRemoveConfirmTitle(String name);

  /// Body of the confirmation dialog before removing a member.
  ///
  /// In en, this message translates to:
  /// **'{name} will lose access to the family. Their open tasks and emergency card will be deleted and any active SOS alert will be closed. Money entries stay in the ledger.'**
  String familyRemoveConfirmMessage(String name);

  /// Snackbar after removing a member.
  ///
  /// In en, this message translates to:
  /// **'{name} was removed from the family'**
  String familyMemberRemoved(String name);

  /// Title of the form that edits another member.
  ///
  /// In en, this message translates to:
  /// **'Edit member'**
  String get familyEditMemberTitle;

  /// Title of the form when a member edits their own details.
  ///
  /// In en, this message translates to:
  /// **'Edit my details'**
  String get familyEditMyDetailsTitle;

  /// Label of the profile photo picker.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get familyPhotoLabel;

  /// Label of the member name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get familyNameLabel;

  /// Label of the optional member email field.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get familyEmailLabel;

  /// Helper text under the email field when adding a member.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email them an invitation with your family code so they can join with their own account.'**
  String get familyEmailInviteHint;

  /// Helper text under the email field when editing a member without an account.
  ///
  /// In en, this message translates to:
  /// **'Add an email so they can join with their own account.'**
  String get familyEmailManagedHint;

  /// Helper text under the read-only email field of a member who has an account.
  ///
  /// In en, this message translates to:
  /// **'This is the email of their account.'**
  String get familyEmailLinkedHint;

  /// Helper text under the read-only email field when an admin edits their own details.
  ///
  /// In en, this message translates to:
  /// **'This is the email of your account.'**
  String get familyEmailLinkedSelfHint;

  /// Second helper line under the optional email field.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for children or elders who won\'t use the app.'**
  String get familyNoEmailHint;

  /// Label of the optional phone number field.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get familyPhoneLabel;

  /// Helper text under the phone field.
  ///
  /// In en, this message translates to:
  /// **'Include the country code, e.g. {dialCode}'**
  String familyPhoneHint(String dialCode);

  /// Helper text of the designation field.
  ///
  /// In en, this message translates to:
  /// **'Their title in the family, e.g. Finance Head'**
  String get familyDesignationHint;

  /// Label above the suggested designation chips.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get familyDesignationSuggestions;

  /// Shown instead of the role picker when an admin edits themselves.
  ///
  /// In en, this message translates to:
  /// **'You can\'t change your own role. Ask another admin.'**
  String get familyRoleChangeSelfNote;

  /// Title of the consent section shown for minors.
  ///
  /// In en, this message translates to:
  /// **'Guardian consent'**
  String get familyGuardianConsentTitle;

  /// Explains why consent is needed. law = name of the country's privacy law (not translated), age = consent age.
  ///
  /// In en, this message translates to:
  /// **'Under {law}, a parent or guardian must agree before we store details of anyone under {age}.'**
  String familyGuardianConsentLaw(String law, int age);

  /// Label of the mandatory guardian-consent checkbox.
  ///
  /// In en, this message translates to:
  /// **'I am this member\'s parent or legal guardian and I agree that FamilyHub may store and use their details for our family.'**
  String get familyGuardianConsentCheckbox;

  /// Validation error when the consent checkbox is not ticked.
  ///
  /// In en, this message translates to:
  /// **'Please confirm guardian consent to continue.'**
  String get familyGuardianConsentRequired;

  /// Snackbar after adding a member without email.
  ///
  /// In en, this message translates to:
  /// **'{name} was added to the family'**
  String familyMemberAdded(String name);

  /// Snackbar after adding a member with an email address.
  ///
  /// In en, this message translates to:
  /// **'{name} was added. We sent an invitation to {email}.'**
  String familyMemberAddedInvited(String name, String email);

  /// Info after adding a member when uploading the photo failed.
  ///
  /// In en, this message translates to:
  /// **'{name} was added, but the photo couldn\'t be saved. You can add it by editing their details.'**
  String familyPhotoNotSaved(String name);

  /// Shown when a member opens the edit form of someone else.
  ///
  /// In en, this message translates to:
  /// **'You can\'t edit this member'**
  String get familyCannotEditTitle;

  /// Explanation under familyCannotEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Only family admins can change other members\' details.'**
  String get familyCannotEditMessage;

  /// Suggested family title, like a company CEO.
  ///
  /// In en, this message translates to:
  /// **'Head of Family'**
  String get familyDesignationHeadOfFamily;

  /// Suggested family title for the person managing money.
  ///
  /// In en, this message translates to:
  /// **'Finance Head (CFO)'**
  String get familyDesignationFinanceHead;

  /// Suggested family title for the person running the household.
  ///
  /// In en, this message translates to:
  /// **'Operations Head (COO)'**
  String get familyDesignationOperationsHead;

  /// Suggested family title for the person looking after health and medicines.
  ///
  /// In en, this message translates to:
  /// **'Chief Health Officer'**
  String get familyDesignationHealthOfficer;

  /// Suggested family title for the person handling phones, internet and gadgets.
  ///
  /// In en, this message translates to:
  /// **'Tech Head (CTO)'**
  String get familyDesignationTechHead;

  /// Playful family title for a school or college student.
  ///
  /// In en, this message translates to:
  /// **'Chief Study Officer'**
  String get familyDesignationChiefStudyOfficer;

  /// Playful family title for a child or teen learning new skills.
  ///
  /// In en, this message translates to:
  /// **'Skill Builder'**
  String get familyDesignationSkillBuilder;

  /// Playful family title for a young child.
  ///
  /// In en, this message translates to:
  /// **'Chief Fun Officer'**
  String get familyDesignationChiefFunOfficer;

  /// Playful family title for a young child.
  ///
  /// In en, this message translates to:
  /// **'Junior Explorer'**
  String get familyDesignationJuniorExplorer;

  /// Respectful family title for an elder (grandparent).
  ///
  /// In en, this message translates to:
  /// **'Family Advisor'**
  String get familyDesignationFamilyAdvisor;

  /// Respectful family title for an elder who guides the family.
  ///
  /// In en, this message translates to:
  /// **'Chief Mentor'**
  String get familyDesignationChiefMentor;

  /// Title of the family settings screen.
  ///
  /// In en, this message translates to:
  /// **'Family settings'**
  String get familySettingsTitle;

  /// Label of the family name field, e.g. 'Sharma Family'.
  ///
  /// In en, this message translates to:
  /// **'Family name'**
  String get familyNameFieldLabel;

  /// Label of the country picker.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get familyCountryLabel;

  /// Helper under the country field: what the country changes.
  ///
  /// In en, this message translates to:
  /// **'Emergency number {number} · Guardian consent under {age}'**
  String familyCountryDetails(String number, int age);

  /// Label of the family currency picker.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get familyCurrencyLabel;

  /// Label of the family time zone picker.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get familyTimezoneLabel;

  /// Helper text under the time zone picker.
  ///
  /// In en, this message translates to:
  /// **'Used for due dates, \"today\" and monthly money summaries.'**
  String get familyTimezoneHint;

  /// Snackbar after saving the family settings.
  ///
  /// In en, this message translates to:
  /// **'Family settings saved'**
  String get familySettingsSaved;

  /// Note shown to members who can only view the family settings.
  ///
  /// In en, this message translates to:
  /// **'Only family admins can change these settings.'**
  String get familySettingsReadOnly;

  /// Shown on family screens when the user is not in a family.
  ///
  /// In en, this message translates to:
  /// **'No family yet'**
  String get familyNotFoundTitle;

  /// Title of the card with the code people use to join the family.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get familyInviteCodeTitle;

  /// Explanation on the invite code card.
  ///
  /// In en, this message translates to:
  /// **'Share this code with your family. They enter it in the app to join.'**
  String get familyInviteCodeMessage;

  /// Screen-reader label of the invite code; code is spelled out character by character.
  ///
  /// In en, this message translates to:
  /// **'Invite code: {code}'**
  String familyInviteCodeSemantics(String code);

  /// Button that copies the invite code (verb).
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get familyCopyInviteCode;

  /// Snackbar after copying the invite code.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied'**
  String get familyInviteCodeCopied;

  /// Button that replaces the invite code with a new one (verb).
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get familyNewInviteCode;

  /// Title of the dialog before regenerating the invite code.
  ///
  /// In en, this message translates to:
  /// **'Create a new invite code?'**
  String get familyNewInviteCodeConfirmTitle;

  /// Body of the dialog before regenerating the invite code.
  ///
  /// In en, this message translates to:
  /// **'The current code stops working right away. Anyone who hasn\'t joined yet will need the new code.'**
  String get familyNewInviteCodeConfirmMessage;

  /// Confirm button of the regenerate dialog.
  ///
  /// In en, this message translates to:
  /// **'Create new code'**
  String get familyNewInviteCodeConfirm;

  /// Snackbar after regenerating the invite code.
  ///
  /// In en, this message translates to:
  /// **'New invite code created'**
  String get familyNewInviteCodeCreated;

  /// Shown to members instead of the invite code (only admins can see it).
  ///
  /// In en, this message translates to:
  /// **'Ask a family admin for the invite code.'**
  String get familyInviteCodeAdminOnly;

  /// Button that opens the member list (verb).
  ///
  /// In en, this message translates to:
  /// **'View members'**
  String get familyViewMembers;

  /// Title shown instead of a member's details when the member was removed from the family (or the link is wrong), e.g. after opening an old notification.
  ///
  /// In en, this message translates to:
  /// **'This person is no longer in the family'**
  String get familyMemberGoneTitle;

  /// Explanation under familyMemberGoneTitle.
  ///
  /// In en, this message translates to:
  /// **'A family admin may have removed them.'**
  String get familyMemberGoneMessage;

  /// Snackbar when an admin removes a member that another admin removed a moment earlier.
  ///
  /// In en, this message translates to:
  /// **'{name} had already been removed from the family'**
  String familyMemberAlreadyRemoved(String name);

  /// Title of the dialog asking before adding a second member with exactly the same name.
  ///
  /// In en, this message translates to:
  /// **'{name} is already in the family'**
  String familyDuplicateNameTitle(String name);

  /// Message of the duplicate-name dialog. The earlier try may have succeeded even though the connection dropped.
  ///
  /// In en, this message translates to:
  /// **'Add another member with the same name? If an earlier try looked like it failed, check the member list first.'**
  String get familyDuplicateNameMessage;

  /// Confirm button of the duplicate-name dialog.
  ///
  /// In en, this message translates to:
  /// **'Add anyway'**
  String get familyDuplicateNameConfirm;

  /// Label of the header statistic with the number of family admins (short, shown under a number).
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get familyStatAdmins;

  /// Label of the header statistic with the number of members who have their own account (short, shown under a number).
  ///
  /// In en, this message translates to:
  /// **'On the app'**
  String get familyStatAppUsers;

  /// Label of the header statistic with the number of members under 18 (short, shown under a number).
  ///
  /// In en, this message translates to:
  /// **'Kids & teens'**
  String get familyStatKids;

  /// Section title above a member's phone number and email.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get familyContactSection;

  /// Section title above a member's location sharing setting and last known location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get familyLocationSection;

  /// Section title of the member form above the designation and the admin/member role.
  ///
  /// In en, this message translates to:
  /// **'Role in the family'**
  String get familyRoleSection;

  /// Section title of the family settings above the family name, country, currency and time zone.
  ///
  /// In en, this message translates to:
  /// **'Family profile'**
  String get familyProfileSection;

  /// Bottom navigation tab: family dashboard.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation tab: task board.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get navTasks;

  /// Bottom navigation tab: emergency alert. Keep it very short; 'SOS' is understood in most languages.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get navSos;

  /// Tooltip / screen-reader label of the SOS tab.
  ///
  /// In en, this message translates to:
  /// **'SOS - alert your family'**
  String get navSosTooltip;

  /// Bottom navigation tab: family ledger and savings goals.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get navMoney;

  /// Bottom navigation tab: family, notices, emergency cards and settings.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// Shown on the splash screen while the saved session is restored.
  ///
  /// In en, this message translates to:
  /// **'Getting your family ready…'**
  String get homeSplashLoading;

  /// Title of the screen shown for an unknown or outdated link.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get homeRouteNotFoundTitle;

  /// No description provided for @homeRouteNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This link doesn\'t exist or is no longer available.'**
  String get homeRouteNotFoundMessage;

  /// Button on the 'page not found' screen.
  ///
  /// In en, this message translates to:
  /// **'Go to home'**
  String get homeGoHome;

  /// Temporary: title on a screen whose feature is not built yet.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get homePlaceholderTitle;

  /// Temporary: message on a screen whose feature is not built yet.
  ///
  /// In en, this message translates to:
  /// **'This part of FamilyHub is still being built.'**
  String get homePlaceholderMessage;

  /// Temporary (demo mode only): button that signs in with the built-in demo account.
  ///
  /// In en, this message translates to:
  /// **'Try the demo family'**
  String get homePlaceholderDemoSignIn;

  /// Temporary: sign-out button on a screen whose feature is not built yet.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get homePlaceholderSignOut;

  /// App bar title of the Money tab (family ledger and savings goals).
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get ledgerTitle;

  /// Compliance caption on money screens: the app only records amounts, it never pays or transfers money.
  ///
  /// In en, this message translates to:
  /// **'Records only – no real money is moved.'**
  String get ledgerRecordsOnlyNote;

  /// Ledger entry type: money coming in.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get ledgerTypeIncome;

  /// Ledger entry type: money going out.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get ledgerTypeExpense;

  /// Action that opens the form to record income.
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get ledgerAddIncome;

  /// Action that opens the form to record an expense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get ledgerAddExpense;

  /// Floating button on money screens; opens a choice between income and expense.
  ///
  /// In en, this message translates to:
  /// **'Add entry'**
  String get ledgerAddEntry;

  /// Title of the sheet that asks whether to add income or an expense.
  ///
  /// In en, this message translates to:
  /// **'What would you like to record?'**
  String get ledgerAddEntryChooseType;

  /// Examples under 'Add income' in the choice sheet.
  ///
  /// In en, this message translates to:
  /// **'Salary, pocket money, gifts, interest…'**
  String get ledgerAddIncomeHint;

  /// Examples under 'Add expense' in the choice sheet.
  ///
  /// In en, this message translates to:
  /// **'Groceries, bills, school fees, household help…'**
  String get ledgerAddExpenseHint;

  /// Income category.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get ledgerCategorySalary;

  /// Income category: earnings from own business / self-employment.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get ledgerCategoryBusiness;

  /// Income category: pocket money / allowance (e.g. a child's).
  ///
  /// In en, this message translates to:
  /// **'Allowance'**
  String get ledgerCategoryAllowance;

  /// Income category: money received as a gift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get ledgerCategoryGift;

  /// Income category: bank / deposit interest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get ledgerCategoryInterest;

  /// Income category: anything else.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get ledgerCategoryOtherIncome;

  /// Expense category.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get ledgerCategoryGroceries;

  /// Expense category: electricity, water, gas, phone, internet.
  ///
  /// In en, this message translates to:
  /// **'Bills & utilities'**
  String get ledgerCategoryUtilities;

  /// Expense category: house rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get ledgerCategoryRent;

  /// Expense category: school / tuition fees, books.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get ledgerCategoryEducation;

  /// Expense category: doctor, medicines, insurance.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get ledgerCategoryHealth;

  /// Expense category: fuel, bus, taxi, train.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get ledgerCategoryTransport;

  /// Expense category: restaurants, takeaway.
  ///
  /// In en, this message translates to:
  /// **'Eating out'**
  String get ledgerCategoryDining;

  /// Expense category: clothes, electronics, household items.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get ledgerCategoryShopping;

  /// Expense category: movies, streaming, outings.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get ledgerCategoryEntertainment;

  /// Expense category: wages of a maid, cook, driver or nanny.
  ///
  /// In en, this message translates to:
  /// **'Household help'**
  String get ledgerCategoryHouseholdHelp;

  /// Expense category of goal contributions (money put aside for a savings goal).
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get ledgerCategorySavings;

  /// Expense category: anything else.
  ///
  /// In en, this message translates to:
  /// **'Other expense'**
  String get ledgerCategoryOtherExpense;

  /// Chip on the month summary: totals include every family member.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get ledgerScopeFamily;

  /// Chip on the month summary: totals include only the signed-in member.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get ledgerScopePersonal;

  /// Explanation of the 'Family' summary scope.
  ///
  /// In en, this message translates to:
  /// **'Totals for the whole family'**
  String get ledgerScopeFamilyHint;

  /// Explanation of the 'Personal' summary scope.
  ///
  /// In en, this message translates to:
  /// **'Totals for your own entries'**
  String get ledgerScopePersonalHint;

  /// Month summary: total income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get ledgerSummaryIncome;

  /// Month summary: total expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get ledgerSummaryExpense;

  /// Month summary: income minus expenses.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get ledgerSummaryNet;

  /// Month summary without any entries. {month} is a formatted month, e.g. 'September 2026'.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded for {month} yet.'**
  String ledgerSummaryEmpty(String month);

  /// Tooltip of the month switcher's back arrow.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get ledgerMonthPrevious;

  /// Tooltip of the month switcher's forward arrow.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get ledgerMonthNext;

  /// Title of the month picker; also the screen-reader hint of the month label.
  ///
  /// In en, this message translates to:
  /// **'Choose a month'**
  String get ledgerMonthPick;

  /// Month filter option that shows entries of every month.
  ///
  /// In en, this message translates to:
  /// **'All months'**
  String get ledgerAllMonths;

  /// Shortcut in the month picker to jump to the current month.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get ledgerThisMonth;

  /// Section title of the category bars on the Money tab.
  ///
  /// In en, this message translates to:
  /// **'By category'**
  String get ledgerBreakdownTitle;

  /// Bar that sums up all smaller categories.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get ledgerBreakdownOther;

  /// Shown instead of the expense category bars.
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded this month.'**
  String get ledgerBreakdownEmptyExpense;

  /// Shown instead of the income category bars.
  ///
  /// In en, this message translates to:
  /// **'No income recorded this month.'**
  String get ledgerBreakdownEmptyIncome;

  /// Screen-reader label of one category bar.
  ///
  /// In en, this message translates to:
  /// **'{category}: {amount}, {percent}'**
  String ledgerBreakdownItemSemantics(
    String category,
    String amount,
    String percent,
  );

  /// Section title of the savings goals on the Money tab.
  ///
  /// In en, this message translates to:
  /// **'Savings goals'**
  String get ledgerGoalsTitle;

  /// Action (admins only) that opens the form to create a savings goal.
  ///
  /// In en, this message translates to:
  /// **'New goal'**
  String get ledgerNewGoal;

  /// Empty state title of the goals section.
  ///
  /// In en, this message translates to:
  /// **'No savings goals yet'**
  String get ledgerGoalsEmpty;

  /// Empty goals message for admins, who can create goals.
  ///
  /// In en, this message translates to:
  /// **'Save together for a trip, school fees or a rainy-day fund.'**
  String get ledgerGoalsEmptyAdmin;

  /// Empty goals message for members, who cannot create goals.
  ///
  /// In en, this message translates to:
  /// **'Your family admins can create goals that everyone contributes to.'**
  String get ledgerGoalsEmptyMember;

  /// Button under the goals list that reveals archived goals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show 1 archived goal} other{Show {count} archived goals}}'**
  String ledgerShowArchivedGoals(int count);

  /// Button that hides the archived goals again.
  ///
  /// In en, this message translates to:
  /// **'Hide archived goals'**
  String get ledgerHideArchivedGoals;

  /// Section title of the latest entries of the selected month.
  ///
  /// In en, this message translates to:
  /// **'Recent entries'**
  String get ledgerRecentTitle;

  /// Empty state title of the recent entries section.
  ///
  /// In en, this message translates to:
  /// **'No entries this month'**
  String get ledgerRecentEmpty;

  /// Empty state message of the recent entries section. Keep the button name in sync with ledgerAddEntry.
  ///
  /// In en, this message translates to:
  /// **'Record income or an expense with “Add entry”.'**
  String get ledgerRecentEmptyMessage;

  /// Second line of an entry row: date and the member the money belongs to.
  ///
  /// In en, this message translates to:
  /// **'{date} · {member}'**
  String ledgerEntryTileSubtitle(String date, String member);

  /// Small badge on an entry that was created by a savings-goal contribution.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get ledgerEntryGoalBadge;

  /// Title of the full, filterable list of ledger entries.
  ///
  /// In en, this message translates to:
  /// **'All entries'**
  String get ledgerEntriesTitle;

  /// Empty state title of the entries list.
  ///
  /// In en, this message translates to:
  /// **'No entries found'**
  String get ledgerEntriesEmpty;

  /// Empty state message when filters are active.
  ///
  /// In en, this message translates to:
  /// **'Try another month or clear the filters.'**
  String get ledgerEntriesEmptyFiltered;

  /// Empty state message without filters.
  ///
  /// In en, this message translates to:
  /// **'Entries you record will show up here.'**
  String get ledgerEntriesEmptyMessage;

  /// Button that resets the entry filters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get ledgerClearFilters;

  /// Type filter option: income and expenses.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ledgerFilterAllTypes;

  /// Label of the member filter (admins only).
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get ledgerFilterMember;

  /// Member filter option: entries of every member.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get ledgerFilterAllMembers;

  /// Caption for non-admin members explaining which entries they can see.
  ///
  /// In en, this message translates to:
  /// **'You see the entries that are yours or that you added.'**
  String get ledgerEntriesVisibleToMember;

  /// Title of the form that records a new income or expense.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get ledgerNewEntryTitle;

  /// Title of the form that edits an existing entry.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get ledgerEditEntryTitle;

  /// Label of the amount field. {currency} is the currency symbol, e.g. '₹'.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String ledgerFieldAmount(String currency);

  /// Label above the category chips.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get ledgerFieldCategory;

  /// Label of the entry date field.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get ledgerFieldDate;

  /// Label of the optional note field.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get ledgerFieldNote;

  /// Hint in the note field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Weekly vegetables'**
  String get ledgerFieldNoteHint;

  /// Label of the field choosing the member an entry belongs to.
  ///
  /// In en, this message translates to:
  /// **'Whose money'**
  String get ledgerFieldMember;

  /// Helper under the (locked) member field for non-admin members.
  ///
  /// In en, this message translates to:
  /// **'Members record entries for themselves.'**
  String get ledgerFieldMemberLocked;

  /// A member name marked as the signed-in person.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String ledgerMemberYou(String name);

  /// Validation error when no category is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get ledgerCategoryRequired;

  /// Validation error for an entry date after tomorrow.
  ///
  /// In en, this message translates to:
  /// **'The date can\'t be in the future'**
  String get ledgerDateInFuture;

  /// Notice on the edit form of an entry created by a goal contribution.
  ///
  /// In en, this message translates to:
  /// **'This entry is a goal contribution, so its amount and category can\'t be changed. Delete it and contribute again instead.'**
  String get ledgerGoalLinkedLocked;

  /// Snackbar after recording a new entry.
  ///
  /// In en, this message translates to:
  /// **'Entry added'**
  String get ledgerEntryAdded;

  /// Snackbar after editing an entry.
  ///
  /// In en, this message translates to:
  /// **'Entry updated'**
  String get ledgerEntrySaved;

  /// Snackbar after deleting an entry.
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get ledgerEntryDeleted;

  /// Title of the bottom sheet that shows one entry.
  ///
  /// In en, this message translates to:
  /// **'Entry details'**
  String get ledgerEntryDetailTitle;

  /// Entry details: the member the money belongs to.
  ///
  /// In en, this message translates to:
  /// **'Belongs to'**
  String get ledgerDetailMember;

  /// Entry details: the member who recorded the entry.
  ///
  /// In en, this message translates to:
  /// **'Added by'**
  String get ledgerDetailCreatedBy;

  /// Entry details: category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get ledgerDetailCategory;

  /// Entry details: date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get ledgerDetailDate;

  /// Entry details: note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get ledgerDetailNote;

  /// Entry details: the entry was created by contributing to a savings goal.
  ///
  /// In en, this message translates to:
  /// **'Savings goal contribution'**
  String get ledgerDetailGoal;

  /// Button in entry details that opens the linked savings goal.
  ///
  /// In en, this message translates to:
  /// **'View goal'**
  String get ledgerDetailOpenGoal;

  /// Confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get ledgerDeleteEntryTitle;

  /// Confirmation dialog message for deleting a normal entry.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get ledgerDeleteEntryMessage;

  /// Confirmation dialog message for deleting an entry created by a goal contribution.
  ///
  /// In en, this message translates to:
  /// **'The amount will also be taken off the goal\'s saved total. This can\'t be undone.'**
  String get ledgerDeleteContributionMessage;

  /// Title of the form that creates a savings goal.
  ///
  /// In en, this message translates to:
  /// **'New savings goal'**
  String get ledgerGoalNewTitle;

  /// Title of the form that edits a savings goal.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get ledgerGoalEditTitle;

  /// Label of the goal title field.
  ///
  /// In en, this message translates to:
  /// **'Goal name'**
  String get ledgerGoalFieldTitle;

  /// Hint in the goal title field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Goa vacation'**
  String get ledgerGoalFieldTitleHint;

  /// Label of the optional goal description field.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get ledgerGoalFieldDescription;

  /// Label of the goal target amount field. {currency} is the currency symbol, e.g. '₹'.
  ///
  /// In en, this message translates to:
  /// **'Target amount ({currency})'**
  String ledgerGoalFieldTarget(String currency);

  /// Label of the optional goal deadline field.
  ///
  /// In en, this message translates to:
  /// **'Target date (optional)'**
  String get ledgerGoalFieldTargetDate;

  /// Snackbar after creating a goal.
  ///
  /// In en, this message translates to:
  /// **'Goal created'**
  String get ledgerGoalCreated;

  /// Snackbar after editing a goal.
  ///
  /// In en, this message translates to:
  /// **'Goal updated'**
  String get ledgerGoalUpdated;

  /// Shown when a non-admin opens a goal form.
  ///
  /// In en, this message translates to:
  /// **'Only family admins can create or change savings goals.'**
  String get ledgerGoalAdminOnly;

  /// Savings goal status.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get ledgerGoalStatusActive;

  /// Savings goal status: the target was reached.
  ///
  /// In en, this message translates to:
  /// **'Achieved'**
  String get ledgerGoalStatusAchieved;

  /// Savings goal status: put away, no more contributions.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get ledgerGoalStatusArchived;

  /// Goal details: amount saved so far.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get ledgerGoalSavedLabel;

  /// Goal details: target amount.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get ledgerGoalTargetLabel;

  /// Goal details: amount still needed.
  ///
  /// In en, this message translates to:
  /// **'Still to go'**
  String get ledgerGoalRemainingLabel;

  /// Goal progress line with formatted amounts.
  ///
  /// In en, this message translates to:
  /// **'{saved} of {target}'**
  String ledgerGoalSavedOfTarget(String saved, String target);

  /// Goal progress as a formatted percentage.
  ///
  /// In en, this message translates to:
  /// **'{percent} saved'**
  String ledgerGoalPercentSaved(String percent);

  /// Amount still needed to reach a goal (formatted money).
  ///
  /// In en, this message translates to:
  /// **'{amount} still to go'**
  String ledgerGoalRemainingHint(String amount);

  /// Days until a goal's target date.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day left} other{{count} days left}}'**
  String ledgerGoalDaysLeft(int count);

  /// The goal's target date is today.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get ledgerGoalDueToday;

  /// The goal's target date has passed while it is still active.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day past target date} other{{count} days past target date}}'**
  String ledgerGoalOverdue(int count);

  /// Goal target date (formatted).
  ///
  /// In en, this message translates to:
  /// **'Target date: {date}'**
  String ledgerGoalTargetDate(String date);

  /// Goal without a deadline.
  ///
  /// In en, this message translates to:
  /// **'No target date'**
  String get ledgerGoalNoTargetDate;

  /// Shown on an achieved goal.
  ///
  /// In en, this message translates to:
  /// **'Target reached – well done, team!'**
  String get ledgerGoalReachedMessage;

  /// Button that records a contribution (money set aside) to a goal. Any member may use it.
  ///
  /// In en, this message translates to:
  /// **'Contribute'**
  String get ledgerGoalContribute;

  /// Title of the contribution sheet.
  ///
  /// In en, this message translates to:
  /// **'Contribute to {title}'**
  String ledgerGoalContributeTitle(String title);

  /// Explains what a contribution does in the ledger.
  ///
  /// In en, this message translates to:
  /// **'The amount is recorded as a savings expense in your name.'**
  String get ledgerGoalContributeExplainer;

  /// Hint in the contribution note field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Diwali bonus'**
  String get ledgerGoalContributionNoteHint;

  /// Snackbar after a contribution.
  ///
  /// In en, this message translates to:
  /// **'Contribution recorded'**
  String get ledgerGoalContributed;

  /// Celebration dialog title when a contribution completes a goal.
  ///
  /// In en, this message translates to:
  /// **'Goal achieved!'**
  String get ledgerGoalAchievedTitle;

  /// Celebration dialog message.
  ///
  /// In en, this message translates to:
  /// **'“{title}” has reached its target of {target}. Well done, team!'**
  String ledgerGoalAchievedMessage(String title, String target);

  /// Button that closes the celebration dialog.
  ///
  /// In en, this message translates to:
  /// **'Hooray!'**
  String get ledgerGoalCelebrate;

  /// Section title of a goal's contributions list.
  ///
  /// In en, this message translates to:
  /// **'Contributions'**
  String get ledgerGoalContributionsTitle;

  /// Empty contributions list title.
  ///
  /// In en, this message translates to:
  /// **'No contributions yet'**
  String get ledgerGoalContributionsEmpty;

  /// Empty contributions list message.
  ///
  /// In en, this message translates to:
  /// **'Be the first to put something aside.'**
  String get ledgerGoalContributionsEmptyMessage;

  /// Caption for members: the contributions list only shows their own.
  ///
  /// In en, this message translates to:
  /// **'You see your own contributions here.'**
  String get ledgerGoalContributionsMineOnly;

  /// Notice on an archived goal.
  ///
  /// In en, this message translates to:
  /// **'This goal is archived and doesn\'t take contributions.'**
  String get ledgerGoalArchivedNotice;

  /// Error when contributing to an archived goal.
  ///
  /// In en, this message translates to:
  /// **'This goal is archived, so it can\'t take contributions.'**
  String get ledgerGoalArchivedError;

  /// Tooltip of the goal's overflow menu (edit, archive, delete).
  ///
  /// In en, this message translates to:
  /// **'Goal actions'**
  String get ledgerGoalActions;

  /// Menu action: archive a goal.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get ledgerGoalArchive;

  /// Menu action: bring an archived goal back.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get ledgerGoalRestore;

  /// Confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Archive this goal?'**
  String get ledgerGoalArchiveTitle;

  /// Confirmation dialog message.
  ///
  /// In en, this message translates to:
  /// **'Archived goals stop taking contributions. You can restore it later.'**
  String get ledgerGoalArchiveMessage;

  /// Snackbar after archiving a goal.
  ///
  /// In en, this message translates to:
  /// **'Goal archived'**
  String get ledgerGoalArchivedDone;

  /// Snackbar after restoring a goal.
  ///
  /// In en, this message translates to:
  /// **'Goal restored'**
  String get ledgerGoalRestoredDone;

  /// Menu action: delete a goal.
  ///
  /// In en, this message translates to:
  /// **'Delete goal'**
  String get ledgerGoalDelete;

  /// Confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete this goal?'**
  String get ledgerGoalDeleteTitle;

  /// Confirmation dialog message.
  ///
  /// In en, this message translates to:
  /// **'Its contributions stay in the ledger as savings entries.'**
  String get ledgerGoalDeleteMessage;

  /// Snackbar after deleting a goal.
  ///
  /// In en, this message translates to:
  /// **'Goal deleted'**
  String get ledgerGoalDeleted;

  /// Error when saving or deleting an entry that another family member deleted meanwhile.
  ///
  /// In en, this message translates to:
  /// **'This entry no longer exists – someone may have deleted it.'**
  String get ledgerErrorEntryGone;

  /// Error when changing or contributing to a goal that was deleted meanwhile.
  ///
  /// In en, this message translates to:
  /// **'This goal no longer exists – an admin may have deleted it.'**
  String get ledgerErrorGoalGone;

  /// Error when the server refuses a money action, e.g. because the person is no longer an admin.
  ///
  /// In en, this message translates to:
  /// **'You can\'t do this any more. Your role in the family may have changed.'**
  String get ledgerErrorForbidden;

  /// Error when saving timed out; the save may still have succeeded, so the person should check before retrying.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer. Check the list before trying again – it may already be saved.'**
  String get ledgerErrorTimeout;

  /// Error when the chosen member (whose money it is) was removed from the family.
  ///
  /// In en, this message translates to:
  /// **'That person is no longer in the family. Choose someone else.'**
  String get ledgerErrorMemberGone;

  /// Error when the server rejects an entry date (later than tomorrow in the family time zone).
  ///
  /// In en, this message translates to:
  /// **'That date is too far ahead for your family\'s time zone. Choose today or an earlier day.'**
  String get ledgerErrorDate;

  /// Error when the server rejects an amount.
  ///
  /// In en, this message translates to:
  /// **'Check the amount and try again.'**
  String get ledgerErrorAmount;

  /// Error when the server rejects the category for the income/expense type.
  ///
  /// In en, this message translates to:
  /// **'This category doesn\'t fit the entry type. Choose another one.'**
  String get ledgerErrorCategory;

  /// Info snackbar when deleting an entry that someone else had already deleted.
  ///
  /// In en, this message translates to:
  /// **'This entry was already deleted.'**
  String get ledgerEntryAlreadyDeleted;

  /// Info snackbar when deleting a goal that another admin had already deleted.
  ///
  /// In en, this message translates to:
  /// **'This goal was already deleted.'**
  String get ledgerGoalAlreadyDeleted;

  /// Title shown when a savings goal (e.g. opened from a notification) no longer exists.
  ///
  /// In en, this message translates to:
  /// **'Goal not found'**
  String get ledgerGoalNotFoundTitle;

  /// Explanation below the 'Goal not found' title.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted by a family admin.'**
  String get ledgerGoalNotFoundMessage;

  /// Button that opens the Money tab.
  ///
  /// In en, this message translates to:
  /// **'Back to Money'**
  String get ledgerBackToMoney;

  /// Stands in for a person who is no longer in the family (e.g. in filters and entry details).
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get ledgerFormerMember;

  /// Note under the member field when the entry belongs to someone who left the family.
  ///
  /// In en, this message translates to:
  /// **'Recorded for {name}, who is no longer in the family.'**
  String ledgerMemberNoLongerInFamily(String name);

  /// Line under the spent-vs-income bar in the Money header and month summary: expenses as a share of income.
  ///
  /// In en, this message translates to:
  /// **'{percent} of income spent'**
  String ledgerHeaderSpentShare(String percent);

  /// Money header pill: this month's expenses are lower than its income.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get ledgerHeaderOnTrack;

  /// Money header pill: this month's expenses are higher than its income.
  ///
  /// In en, this message translates to:
  /// **'Over budget'**
  String get ledgerHeaderOverBudget;

  /// Line under the spent-vs-income bar when there are expenses but no income this month.
  ///
  /// In en, this message translates to:
  /// **'No income recorded yet'**
  String get ledgerHeaderNoIncome;

  /// Section title above date, member and note in the entry form.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get ledgerFormDetailsTitle;

  /// Title of the notice board screen (family announcements).
  ///
  /// In en, this message translates to:
  /// **'Notice board'**
  String get noticesTitle;

  /// Floating action button on the notice board and title of the create-notice screen.
  ///
  /// In en, this message translates to:
  /// **'New notice'**
  String get noticesNew;

  /// Title of the screen for editing an existing notice.
  ///
  /// In en, this message translates to:
  /// **'Edit notice'**
  String get noticesEditTitle;

  /// Empty state title when the family notice board has no notices.
  ///
  /// In en, this message translates to:
  /// **'No notices yet'**
  String get noticesEmptyTitle;

  /// Empty state message on the notice board.
  ///
  /// In en, this message translates to:
  /// **'Share news, plans and reminders with the whole family.'**
  String get noticesEmptyMessage;

  /// Small badge on a notice that an admin pinned to the top of the board.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get noticesPinned;

  /// Action (admins only) that pins a notice above all others.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get noticesPin;

  /// Action (admins only) that removes the pin from a notice.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get noticesUnpin;

  /// Confirmation after pinning a notice.
  ///
  /// In en, this message translates to:
  /// **'Notice pinned to the top'**
  String get noticesPinnedSuccess;

  /// Confirmation after unpinning a notice.
  ///
  /// In en, this message translates to:
  /// **'Notice unpinned'**
  String get noticesUnpinnedSuccess;

  /// Title of the confirmation dialog before deleting a notice.
  ///
  /// In en, this message translates to:
  /// **'Delete this notice?'**
  String get noticesDeleteTitle;

  /// Message of the confirmation dialog before deleting a notice. {title} is the notice title.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be removed for everyone in the family. This can\'t be undone.'**
  String noticesDeleteMessage(String title);

  /// Confirmation after deleting a notice.
  ///
  /// In en, this message translates to:
  /// **'Notice deleted'**
  String get noticesDeleted;

  /// Confirmation after posting a new notice.
  ///
  /// In en, this message translates to:
  /// **'Notice posted'**
  String get noticesPosted;

  /// Confirmation after saving changes to a notice.
  ///
  /// In en, this message translates to:
  /// **'Notice updated'**
  String get noticesUpdated;

  /// Button below a long notice text that shows the whole text.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get noticesReadMore;

  /// Button below an expanded notice text that collapses it again.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get noticesShowLess;

  /// Tooltip / screen-reader label of the menu button on a notice (edit, pin, delete, copy).
  ///
  /// In en, this message translates to:
  /// **'Notice options'**
  String get noticesActions;

  /// Action that copies the notice title and text to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get noticesCopyText;

  /// Screen-reader hint on a notice photo; tapping opens it full screen.
  ///
  /// In en, this message translates to:
  /// **'Open photo'**
  String get noticesOpenImage;

  /// Screen-reader label of the photo attached to a notice. {title} is the notice title.
  ///
  /// In en, this message translates to:
  /// **'Photo: {title}'**
  String noticesImageLabel(String title);

  /// Screen-reader label of the author line of a notice. {name} is the author's name.
  ///
  /// In en, this message translates to:
  /// **'Posted by {name}'**
  String noticesPostedBy(String name);

  /// Shown as the author of a notice whose author is no longer in the family.
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get noticesFormerMember;

  /// Label of the notice title field.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get noticesFieldTitle;

  /// Hint (example) inside the empty notice title field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Family meeting Sunday 7pm'**
  String get noticesFieldTitleHint;

  /// Label of the notice text field.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get noticesFieldBody;

  /// Hint inside the empty notice text field.
  ///
  /// In en, this message translates to:
  /// **'What would you like to tell the family?'**
  String get noticesFieldBodyHint;

  /// Label under the photo picker of the notice form.
  ///
  /// In en, this message translates to:
  /// **'Photo (optional)'**
  String get noticesFieldImage;

  /// Switch in the notice form (admins only) that pins the notice.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get noticesFieldPinned;

  /// Explanation under the pin switch in the notice form.
  ///
  /// In en, this message translates to:
  /// **'Pinned notices stay above all others.'**
  String get noticesFieldPinnedHint;

  /// Submit button of the create-notice screen.
  ///
  /// In en, this message translates to:
  /// **'Post notice'**
  String get noticesPost;

  /// Privacy hint on the notice form: who can see the notice.
  ///
  /// In en, this message translates to:
  /// **'Everyone in your family can see this notice.'**
  String get noticesVisibleToFamily;

  /// Shown instead of the edit form when the member is neither the author nor an admin.
  ///
  /// In en, this message translates to:
  /// **'You can\'t edit this notice'**
  String get noticesEditNotAllowed;

  /// Explanation when the member may not edit a notice.
  ///
  /// In en, this message translates to:
  /// **'Only the person who posted it or a family admin can change it.'**
  String get noticesEditNotAllowedMessage;

  /// Shown when the member taps Post/Save on the notice form while the attached photo is still uploading.
  ///
  /// In en, this message translates to:
  /// **'Please wait until the photo has finished uploading.'**
  String get noticesPhotoUploading;

  /// Shown when an action (save, pin, unpin) fails because someone else deleted the notice meanwhile.
  ///
  /// In en, this message translates to:
  /// **'This notice was deleted in the meantime.'**
  String get noticesGone;

  /// Title shown when a link opens a notice that does not exist any more.
  ///
  /// In en, this message translates to:
  /// **'This notice is no longer available'**
  String get noticesNotFoundTitle;

  /// Explanation under noticesNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted by the person who posted it or by a family admin.'**
  String get noticesNotFoundMessage;

  /// Short line under the notice board title in the coloured header.
  ///
  /// In en, this message translates to:
  /// **'News, plans and reminders for the whole family.'**
  String get noticesSubtitle;

  /// Label under the number of notices on the board, shown as a small stat in the notice board header.
  ///
  /// In en, this message translates to:
  /// **'On the board'**
  String get noticesStatTotal;

  /// Heading of the notice form section with the title and message fields.
  ///
  /// In en, this message translates to:
  /// **'What\'s new?'**
  String get noticesSectionMessage;

  /// Text under the photo picker of the notice form; also its screen-reader label.
  ///
  /// In en, this message translates to:
  /// **'Tap to add or change the photo'**
  String get noticesPhotoHint;

  /// Android notification channel name (Settings > Apps > FamilyHub > Notifications) for emergency alerts from family members.
  ///
  /// In en, this message translates to:
  /// **'SOS alerts'**
  String get servicesPushChannelSosName;

  /// Android notification channel description for SOS alerts.
  ///
  /// In en, this message translates to:
  /// **'Emergency alerts from your family. These are loud and appear on the lock screen.'**
  String get servicesPushChannelSosDescription;

  /// Android notification channel name for everything that is not an SOS.
  ///
  /// In en, this message translates to:
  /// **'Family updates'**
  String get servicesPushChannelGeneralName;

  /// Android notification channel description for general family updates.
  ///
  /// In en, this message translates to:
  /// **'Tasks, notices, savings goals and new family members.'**
  String get servicesPushChannelGeneralDescription;

  /// Android notification channel name for the ongoing notification shown while live location is shared (SOS).
  ///
  /// In en, this message translates to:
  /// **'Live location sharing'**
  String get servicesLocationChannelName;

  /// Title of the ongoing notification while the app shares live location with the family.
  ///
  /// In en, this message translates to:
  /// **'Sharing your live location'**
  String get servicesLocationSharingTitle;

  /// Text of the ongoing notification while the app shares live location with the family.
  ///
  /// In en, this message translates to:
  /// **'Your family can see where you are until you stop sharing.'**
  String get servicesLocationSharingText;

  /// Shown when location permission was not granted (the app can ask again).
  ///
  /// In en, this message translates to:
  /// **'FamilyHub needs location permission to share where you are.'**
  String get servicesLocationDenied;

  /// Shown when location permission was permanently denied; only the system settings can change it.
  ///
  /// In en, this message translates to:
  /// **'Location permission is turned off for FamilyHub. Allow it in Settings to share where you are.'**
  String get servicesLocationDeniedForever;

  /// Shown when the device-wide location switch (GPS) is off.
  ///
  /// In en, this message translates to:
  /// **'Location services are turned off on this device. Turn them on to share where you are.'**
  String get servicesLocationServiceDisabled;

  /// Button that shows the system location permission prompt again.
  ///
  /// In en, this message translates to:
  /// **'Allow location'**
  String get servicesLocationAllow;

  /// Button that opens the system settings (app permissions or location services).
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get servicesOpenSettings;

  /// Error code UPLOAD_FAILED: Cloudinary rejected the upload or returned an unusable response.
  ///
  /// In en, this message translates to:
  /// **'The image couldn\'t be uploaded. Please try again.'**
  String get servicesErrorUploadFailed;

  /// Error code FILE_TOO_LARGE: the picked image exceeds the upload size limit.
  ///
  /// In en, this message translates to:
  /// **'This image is too large. Please choose a smaller one.'**
  String get servicesErrorFileTooLarge;

  /// Error code UPLOAD_CANCELLED: the image upload was cancelled.
  ///
  /// In en, this message translates to:
  /// **'The upload was cancelled.'**
  String get servicesErrorUploadCancelled;

  /// Screen-reader hint on the profile card at the top of the More tab.
  ///
  /// In en, this message translates to:
  /// **'Opens your profile'**
  String get settingsProfileHeaderHint;

  /// Section title on the More tab grouping family screens (members, notices, emergency cards...).
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get settingsSectionFamily;

  /// More tab entry that opens the list of family members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get settingsMembers;

  /// More tab entry (admins only) that opens family name, country, currency and invite code settings.
  ///
  /// In en, this message translates to:
  /// **'Family settings'**
  String get settingsFamilySettings;

  /// More tab entry that opens the family notice board (announcements).
  ///
  /// In en, this message translates to:
  /// **'Notice board'**
  String get settingsNoticeBoard;

  /// More tab entry that opens the members' emergency (medical information) cards.
  ///
  /// In en, this message translates to:
  /// **'Emergency cards'**
  String get settingsEmergencyCards;

  /// More tab entry that opens past (resolved / expired) SOS alerts.
  ///
  /// In en, this message translates to:
  /// **'SOS history'**
  String get settingsSosHistory;

  /// Section title on the More tab grouping language, appearance, location and notification settings.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsSectionPreferences;

  /// Section title grouping password, privacy and about entries.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// Settings entry / screen title for the app language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Settings entry / screen title for theme (light/dark) and text size.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Settings entry / screen title for who can see the member's location.
  ///
  /// In en, this message translates to:
  /// **'Location sharing'**
  String get settingsLocationSharing;

  /// Settings entry showing whether push notifications are turned on for this app.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Notification status: the phone allows notifications from the app.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingsNotificationsEnabled;

  /// Notification status: notifications are blocked in the phone settings.
  ///
  /// In en, this message translates to:
  /// **'Off. Turn them on in your phone settings to get SOS alerts.'**
  String get settingsNotificationsDisabled;

  /// Notification status: the user has not been asked for notification permission yet.
  ///
  /// In en, this message translates to:
  /// **'Not turned on yet'**
  String get settingsNotificationsNotAsked;

  /// Notification status: push notifications are not set up in this build / on this device.
  ///
  /// In en, this message translates to:
  /// **'Not available in this version of the app'**
  String get settingsNotificationsUnavailable;

  /// Button / tooltip that opens the phone's settings page for this app.
  ///
  /// In en, this message translates to:
  /// **'Open phone settings'**
  String get settingsNotificationsOpenSettings;

  /// Shown when the system settings screen could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the phone settings. Open them from your phone\'s Settings app.'**
  String get settingsOpenSettingsFailed;

  /// Shown when a web link (privacy policy, terms) could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link. Please try again.'**
  String get settingsLinkOpenFailed;

  /// Settings entry, screen title and submit button for changing the account password.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// Settings entry / screen title: privacy policy, data export, leave family, delete account.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data'**
  String get settingsPrivacy;

  /// Settings entry that opens information about the app.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Button that signs the user out of the app.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogout;

  /// Title of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Log out of FamilyHub?'**
  String get settingsLogoutConfirmTitle;

  /// Message of the log-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'SOS alerts and family updates will no longer reach this phone until you sign in again.'**
  String get settingsLogoutConfirmMessage;

  /// App version shown at the bottom of the More tab and on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// Theme option: follow the phone's light/dark setting.
  ///
  /// In en, this message translates to:
  /// **'Same as phone'**
  String get settingsThemeSystem;

  /// Theme option: always light colours.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme option: always dark colours.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Title of the screen where members edit their own profile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get settingsProfileTitle;

  /// Label of the profile photo picker.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get settingsProfilePhoto;

  /// Profile form field: the member's name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsProfileName;

  /// Profile form field: the member's phone number (optional).
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get settingsProfilePhone;

  /// Hint under the phone field explaining the expected format.
  ///
  /// In en, this message translates to:
  /// **'Include the country code, e.g. +91'**
  String get settingsProfilePhoneHint;

  /// Profile form field: date of birth (optional for adults).
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get settingsProfileDateOfBirth;

  /// Profile form field label for the gender choice.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get settingsProfileGender;

  /// Read-only profile row showing the account email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get settingsProfileEmail;

  /// Read-only profile row: the member's 'company title' in the family, e.g. Finance Head.
  ///
  /// In en, this message translates to:
  /// **'Title in the family'**
  String get settingsProfileDesignation;

  /// Read-only profile row: Admin or Member.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get settingsProfileRole;

  /// Note under the read-only title / role rows on the profile screen.
  ///
  /// In en, this message translates to:
  /// **'Your title and role are set by a family admin.'**
  String get settingsProfileManagedByAdmin;

  /// Snackbar after the profile was saved.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get settingsProfileSaved;

  /// Shown under the name field when the server rejected the name.
  ///
  /// In en, this message translates to:
  /// **'Enter a name with 1 to {max} characters.'**
  String settingsProfileNameInvalid(int max);

  /// Shown under the date-of-birth field when the server rejected the date.
  ///
  /// In en, this message translates to:
  /// **'Enter a real date of birth. It cannot be in the future.'**
  String get settingsProfileDateOfBirthInvalid;

  /// Shown under the date-of-birth field when the chosen date makes the member younger than the country consent age and no guardian consent is recorded.
  ///
  /// In en, this message translates to:
  /// **'Members younger than {age} need a parent or guardian to set this. Ask a family admin to change your date of birth.'**
  String settingsProfileGuardianConsentNeeded(int age);

  /// Snackbar when the server rejected the uploaded profile photo URL.
  ///
  /// In en, this message translates to:
  /// **'This photo couldn\'t be saved. Please choose it again.'**
  String get settingsProfilePhotoRejected;

  /// Empty state on member-only settings screens when the user has no family.
  ///
  /// In en, this message translates to:
  /// **'You\'re not in a family yet'**
  String get settingsNoFamilyTitle;

  /// Empty state message on member-only settings screens when the user has no family.
  ///
  /// In en, this message translates to:
  /// **'Create or join a family to use this.'**
  String get settingsNoFamilyMessage;

  /// Language option: follow the phone's language setting.
  ///
  /// In en, this message translates to:
  /// **'Phone language'**
  String get settingsLanguageDevice;

  /// Subtitle of the 'Phone language' option naming the language it resolves to.
  ///
  /// In en, this message translates to:
  /// **'Currently {language}'**
  String settingsLanguageDeviceCurrent(String language);

  /// Explanation at the top of the language screen.
  ///
  /// In en, this message translates to:
  /// **'Changes the language on this phone. Your notifications and emails will use it too.'**
  String get settingsLanguageHint;

  /// Section title for the light / dark theme choice.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsAppearanceTheme;

  /// Section title for the large text setting.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get settingsAppearanceTextSize;

  /// Switch that makes all text in the app bigger.
  ///
  /// In en, this message translates to:
  /// **'Large text'**
  String get settingsAppearanceLargeText;

  /// Explanation under the large text switch.
  ///
  /// In en, this message translates to:
  /// **'Makes all text bigger and easier to read. Your phone\'s text size setting is also respected.'**
  String get settingsAppearanceLargeTextDescription;

  /// Label above the sample text that shows the current text size.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsAppearancePreview;

  /// Sample notice title used only to preview the text size.
  ///
  /// In en, this message translates to:
  /// **'Family meeting on Sunday'**
  String get settingsAppearancePreviewTitle;

  /// Sample body text used only to preview the text size.
  ///
  /// In en, this message translates to:
  /// **'This is how text looks in FamilyHub with your current settings.'**
  String get settingsAppearancePreviewBody;

  /// Explanation at the top of the location sharing screen.
  ///
  /// In en, this message translates to:
  /// **'Choose when your family can see where you are. Only members of your family can see it, and only you can change this.'**
  String get settingsLocationIntro;

  /// Indicator shown while the member's location sharing mode is 'Always share'.
  ///
  /// In en, this message translates to:
  /// **'Your family can see your location'**
  String get settingsLocationSharedNow;

  /// When the location was last shared, e.g. 'Last shared 5 minutes ago'.
  ///
  /// In en, this message translates to:
  /// **'Last shared {time}'**
  String settingsLocationLastShared(String time);

  /// Shown in the sharing indicator when no location was shared yet.
  ///
  /// In en, this message translates to:
  /// **'Your location will be shared the next time you open the app.'**
  String get settingsLocationNotSharedYet;

  /// Button that sends the current location to the family right away.
  ///
  /// In en, this message translates to:
  /// **'Share now'**
  String get settingsLocationShareNow;

  /// Snackbar after the current location was sent.
  ///
  /// In en, this message translates to:
  /// **'Location shared with your family'**
  String get settingsLocationUpdated;

  /// Snackbar after the location sharing mode was changed.
  ///
  /// In en, this message translates to:
  /// **'Location sharing updated'**
  String get settingsLocationSaved;

  /// Shown when sharing is on but the phone could not provide a location fix.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t get your location right now. It will be shared the next time you open the app.'**
  String get settingsLocationFixUnavailable;

  /// Section title for the location sharing explanations.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get settingsLocationHowItWorks;

  /// Explains how often the location is updated in 'Always share' mode.
  ///
  /// In en, this message translates to:
  /// **'With “Always share”, your location is updated when you open the app, at most every 10 minutes. The app does not follow you in the background.'**
  String get settingsLocationAlwaysNote;

  /// Explains the visible indicator while the live location is shared during an SOS.
  ///
  /// In en, this message translates to:
  /// **'During an SOS your phone shows a notification for as long as your live location is being shared.'**
  String get settingsLocationSosNote;

  /// Explains what 'Never share' means for SOS alerts.
  ///
  /// In en, this message translates to:
  /// **'With “Never share”, an SOS still alerts your family, but without your location.'**
  String get settingsLocationNeverNote;

  /// Consent information at the top of the privacy screen.
  ///
  /// In en, this message translates to:
  /// **'When you signed up, you agreed to the Privacy Policy and the Terms of Service. You can read them at any time.'**
  String get settingsPrivacyConsent;

  /// Link to the privacy policy web page.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// Link to the terms of service web page.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTerms;

  /// Section title on the privacy screen (export data).
  ///
  /// In en, this message translates to:
  /// **'Your data'**
  String get settingsPrivacyYourData;

  /// Section title on the privacy screen (leave family).
  ///
  /// In en, this message translates to:
  /// **'Family membership'**
  String get settingsPrivacyMembership;

  /// Privacy screen entry that shows a copy of all personal data the app stores.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get settingsExportData;

  /// Subtitle of the 'Export my data' entry.
  ///
  /// In en, this message translates to:
  /// **'See a copy of everything FamilyHub stores about you.'**
  String get settingsExportDataDescription;

  /// Title of the screen showing the exported personal data.
  ///
  /// In en, this message translates to:
  /// **'My data'**
  String get settingsExportTitle;

  /// Button that copies the exported data (JSON text) to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get settingsExportCopy;

  /// When the data export was created.
  ///
  /// In en, this message translates to:
  /// **'Exported {date}'**
  String settingsExportGeneratedAt(String date);

  /// Heading above the full machine-readable export.
  ///
  /// In en, this message translates to:
  /// **'Full data (JSON)'**
  String get settingsExportRawData;

  /// Empty state of the data export screen.
  ///
  /// In en, this message translates to:
  /// **'There is no personal data to show.'**
  String get settingsExportEmpty;

  /// Data export summary row: account data (email, name, language).
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsExportSectionUser;

  /// Data export summary row: the member profile in the family.
  ///
  /// In en, this message translates to:
  /// **'Family profile'**
  String get settingsExportSectionMember;

  /// Data export summary row: the family the user belongs to.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get settingsExportSectionFamily;

  /// Data export summary row: tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get settingsExportSectionTasks;

  /// Data export summary row: ledger (income / expense) entries.
  ///
  /// In en, this message translates to:
  /// **'Money entries'**
  String get settingsExportSectionLedger;

  /// Data export summary row: notices the user wrote.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get settingsExportSectionNotices;

  /// Data export summary row: the emergency (medical) card.
  ///
  /// In en, this message translates to:
  /// **'Emergency card'**
  String get settingsExportSectionEmergencyCard;

  /// Data export summary row: SOS alerts the user raised.
  ///
  /// In en, this message translates to:
  /// **'SOS alerts'**
  String get settingsExportSectionSos;

  /// Data export summary row: phones registered for push notifications.
  ///
  /// In en, this message translates to:
  /// **'Phones for notifications'**
  String get settingsExportSectionDevices;

  /// Data export summary row: sign-in sessions of the account.
  ///
  /// In en, this message translates to:
  /// **'Sign-ins'**
  String get settingsExportSectionSessions;

  /// Number of records in a data export section.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} =1{1 item} other{{count} items}}'**
  String settingsExportItemCount(int count);

  /// Data export summary: a single record (e.g. the profile) is included.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get settingsExportIncluded;

  /// Privacy screen entry and confirm button to leave the current family.
  ///
  /// In en, this message translates to:
  /// **'Leave family'**
  String get settingsLeaveFamily;

  /// Subtitle of the 'Leave family' entry.
  ///
  /// In en, this message translates to:
  /// **'Stop being part of {family}. Your account stays.'**
  String settingsLeaveFamilyDescription(String family);

  /// Title of the leave-family confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Leave {family}?'**
  String settingsLeaveFamilyConfirmTitle(String family);

  /// Message of the leave-family confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'You will lose access to the family\'s tasks, money, notices and SOS alerts, and your profile is removed from the family. You can join again later with an invite code.'**
  String get settingsLeaveFamilyConfirmMessage;

  /// Message of the leave-family confirmation dialog when the user is the only member (the family is then deleted).
  ///
  /// In en, this message translates to:
  /// **'You are the only member, so leaving deletes the family and all of its tasks, money records, notices, emergency cards and SOS history. This cannot be undone. Your account stays.'**
  String get settingsLeaveFamilyOnlyMemberMessage;

  /// Snackbar after leaving the family.
  ///
  /// In en, this message translates to:
  /// **'You left the family'**
  String get settingsLeaveFamilyDone;

  /// Dialog title when the last admin tries to leave or delete their account (error LAST_ADMIN).
  ///
  /// In en, this message translates to:
  /// **'You\'re the last admin'**
  String get settingsLastAdminTitle;

  /// Dialog message when the last admin tries to leave the family.
  ///
  /// In en, this message translates to:
  /// **'A family always needs an admin. Make another member an admin first, then leave the family.'**
  String get settingsLastAdminLeaveMessage;

  /// Dialog message when the last admin tries to delete their account.
  ///
  /// In en, this message translates to:
  /// **'A family always needs an admin. Make another member an admin first, then delete your account.'**
  String get settingsLastAdminDeleteMessage;

  /// Button in the last-admin dialog that opens the members list.
  ///
  /// In en, this message translates to:
  /// **'Go to members'**
  String get settingsLastAdminOpenMembers;

  /// Privacy screen entry to permanently delete the account.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// Subtitle of the 'Delete account' entry.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and personal data.'**
  String get settingsDeleteAccountDescription;

  /// Title of the delete-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get settingsDeleteAccountTitle;

  /// Explanation in the delete-account dialog of what will be deleted.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account, your family profile, your emergency card and your registered devices. Money entries you recorded stay in the family ledger. If you are the only member, the whole family is deleted. This cannot be undone.'**
  String get settingsDeleteAccountMessage;

  /// Password field in the delete-account dialog (confirms the deletion).
  ///
  /// In en, this message translates to:
  /// **'Your password'**
  String get settingsDeleteAccountPassword;

  /// Destructive confirm button in the delete-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get settingsDeleteAccountConfirm;

  /// Error under the password field when the password is wrong.
  ///
  /// In en, this message translates to:
  /// **'That password is not correct.'**
  String get settingsDeleteAccountWrongPassword;

  /// Snackbar after the account was deleted.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get settingsDeleteAccountDone;

  /// Change-password form field.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get settingsPasswordCurrent;

  /// Change-password form field.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get settingsPasswordNew;

  /// Change-password form field (repeat the new password).
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get settingsPasswordConfirm;

  /// Password rules shown on the change-password screen.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters, with at least one letter and one number.'**
  String get settingsPasswordRules;

  /// Validation error when the new password equals the current one.
  ///
  /// In en, this message translates to:
  /// **'Choose a password that is different from your current one.'**
  String get settingsPasswordSameAsCurrent;

  /// Error under the current password field (server said INVALID_CREDENTIALS).
  ///
  /// In en, this message translates to:
  /// **'Your current password is not correct.'**
  String get settingsPasswordWrongCurrent;

  /// Snackbar after the password was changed.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get settingsPasswordChanged;

  /// Mission line on the About screen.
  ///
  /// In en, this message translates to:
  /// **'FamilyHub helps your family work together like a great team: clear roles, shared tasks, open money records and help when it matters.'**
  String get settingsAboutMission;

  /// About screen: title of the SOS disclaimer.
  ///
  /// In en, this message translates to:
  /// **'SOS alerts your family only'**
  String get settingsAboutSosTitle;

  /// About screen: SOS disclaimer with the country's emergency number.
  ///
  /// In en, this message translates to:
  /// **'SOS sends an alert to your family members. It does not contact the police, an ambulance or any emergency service. If you are in danger, call {number}.'**
  String settingsAboutSosDisclaimer(String number);

  /// Button that calls the country's emergency number.
  ///
  /// In en, this message translates to:
  /// **'Call {number}'**
  String settingsAboutCallEmergency(String number);

  /// About screen: title of the medical disclaimer.
  ///
  /// In en, this message translates to:
  /// **'Not medical advice'**
  String get settingsAboutMedicalTitle;

  /// About screen: medical disclaimer for emergency cards.
  ///
  /// In en, this message translates to:
  /// **'FamilyHub is not a medical service and does not give medical advice. Emergency cards only show what your family has written down.'**
  String get settingsAboutMedicalDisclaimer;

  /// About screen: title of the ledger-only note.
  ///
  /// In en, this message translates to:
  /// **'Records money, never moves it'**
  String get settingsAboutLedgerTitle;

  /// About screen: explains that the ledger is record-keeping only (no payments).
  ///
  /// In en, this message translates to:
  /// **'The family ledger only records income, expenses and savings. FamilyHub never sends or receives money and never asks for bank, card or UPI details.'**
  String get settingsAboutLedgerNote;

  /// About screen link that emails the privacy contact.
  ///
  /// In en, this message translates to:
  /// **'Privacy questions'**
  String get settingsAboutPrivacyContact;

  /// About screen link to the licences of the open-source libraries used.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsAboutLicenses;

  /// Small button in the profile header at the top of the More tab that opens the profile editor.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get settingsEditProfile;

  /// Section title on the profile screen above the name, phone, date of birth and gender fields.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get settingsProfileSectionPersonal;

  /// Section title on the change-password screen above the current password field.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get settingsPasswordSectionCurrent;

  /// Section title on the change-password screen above the new password fields.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get settingsPasswordSectionNew;

  /// Section title on the About screen above the SOS, medical and money disclaimers.
  ///
  /// In en, this message translates to:
  /// **'Good to know'**
  String get settingsAboutGoodToKnow;

  /// Section title on the About screen above the privacy policy, terms, privacy contact and licences links.
  ///
  /// In en, this message translates to:
  /// **'Legal & contact'**
  String get settingsAboutLegal;

  /// Family role label: a member who can manage the family (like a manager in a company).
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// Family role label: a regular family member without admin rights.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// One-line explanation shown under the Admin role option.
  ///
  /// In en, this message translates to:
  /// **'Can manage members, tasks, money and family settings'**
  String get roleAdminDescription;

  /// One-line explanation shown under the Member role option.
  ///
  /// In en, this message translates to:
  /// **'Can view the family, do their tasks and post notices'**
  String get roleMemberDescription;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// Gender option for people who do not identify as male or female.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genderOther;

  /// Gender option / label when no gender is set.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get genderUnspecified;

  /// Age group label for members younger than 13.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get ageGroupChild;

  /// Age group label for members aged 13 to 17.
  ///
  /// In en, this message translates to:
  /// **'Teen'**
  String get ageGroupTeen;

  /// Age group label for members aged 18 to 59.
  ///
  /// In en, this message translates to:
  /// **'Adult'**
  String get ageGroupAdult;

  /// Age group label for members aged 60 or older.
  ///
  /// In en, this message translates to:
  /// **'Senior'**
  String get ageGroupSenior;

  /// A person's age in completed years, e.g. shown next to a family member's name.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Under 1 year} =1{1 year} other{{count} years}}'**
  String ageYears(int count);

  /// Location sharing mode: location is never shared.
  ///
  /// In en, this message translates to:
  /// **'Never share'**
  String get locationSharingNever;

  /// Location sharing mode: live location is shared only while the member's SOS alert is active.
  ///
  /// In en, this message translates to:
  /// **'Only during SOS'**
  String get locationSharingSosOnly;

  /// Location sharing mode: the family can always see the member's last known location.
  ///
  /// In en, this message translates to:
  /// **'Always share'**
  String get locationSharingAlways;

  /// One-line explanation of the 'Never share' location mode.
  ///
  /// In en, this message translates to:
  /// **'Your location is never shared, not even during an SOS.'**
  String get locationSharingNeverDescription;

  /// One-line explanation of the 'Only during SOS' location mode.
  ///
  /// In en, this message translates to:
  /// **'Your family sees your live location only while your SOS is active.'**
  String get locationSharingSosOnlyDescription;

  /// One-line explanation of the 'Always share' location mode.
  ///
  /// In en, this message translates to:
  /// **'Your family can always see your last known location.'**
  String get locationSharingAlwaysDescription;

  /// App bar title of the SOS tab.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get sosTitle;

  /// Tooltip of the history icon in the SOS tab app bar.
  ///
  /// In en, this message translates to:
  /// **'SOS history'**
  String get sosHistoryTooltip;

  /// Text inside the large round SOS button. Keep it very short; 'SOS' is understood in most languages.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get sosButtonLabel;

  /// Screen-reader label of the large round SOS button.
  ///
  /// In en, this message translates to:
  /// **'Send an SOS alert to your family'**
  String get sosButtonSemantics;

  /// Hint under the SOS button.
  ///
  /// In en, this message translates to:
  /// **'Tap to alert your family. You can cancel within {seconds} seconds.'**
  String sosButtonHint(int seconds);

  /// Countdown text before the SOS is sent (can be cancelled).
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Sending in 1 second} other{Sending in {seconds} seconds}}'**
  String sosSendingIn(int seconds);

  /// Button shown during the countdown to cancel the SOS before it is sent.
  ///
  /// In en, this message translates to:
  /// **'Cancel SOS'**
  String get sosCancelAlert;

  /// Snackbar after the countdown was cancelled.
  ///
  /// In en, this message translates to:
  /// **'SOS cancelled. Nobody was alerted.'**
  String get sosCancelled;

  /// Shown while the SOS is being sent.
  ///
  /// In en, this message translates to:
  /// **'Alerting your family…'**
  String get sosSending;

  /// Snackbar after the SOS was sent with location.
  ///
  /// In en, this message translates to:
  /// **'Your family has been alerted.'**
  String get sosSent;

  /// Snackbar after the SOS was sent without location (sharing mode is Never).
  ///
  /// In en, this message translates to:
  /// **'Your family has been alerted, without your location.'**
  String get sosSentWithoutLocation;

  /// Snackbar after the SOS was sent without location because location permission / GPS is missing. {reason} is a full sentence explaining the problem.
  ///
  /// In en, this message translates to:
  /// **'Your family has been alerted, but without your location: {reason}'**
  String sosSentPermissionMissing(String reason);

  /// Snackbar when the member chose to share the location but switching the sharing mode failed.
  ///
  /// In en, this message translates to:
  /// **'Your family has been alerted, but location sharing could not be turned on.'**
  String get sosSentSharingUpdateFailed;

  /// Title of the error card after sending the SOS failed.
  ///
  /// In en, this message translates to:
  /// **'The SOS was not sent'**
  String get sosSendFailedTitle;

  /// Message of the error card after sending the SOS failed. {number} is the country emergency number.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection and try again. If you are in danger, call {number} now.'**
  String sosSendFailedMessage(String number);

  /// Button that sends the SOS again right away (without countdown) after a failure.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get sosTryAgain;

  /// Title of the disclaimer card on the SOS screen.
  ///
  /// In en, this message translates to:
  /// **'Alerts your family only'**
  String get sosDisclaimerTitle;

  /// Disclaimer on the SOS screen (legal requirement: the app never contacts emergency services).
  ///
  /// In en, this message translates to:
  /// **'SOS notifies the members of your family in FamilyHub. It does not contact the police, an ambulance or any other emergency service.'**
  String get sosDisclaimer;

  /// Button that dials the country's emergency number.
  ///
  /// In en, this message translates to:
  /// **'Call emergency services {number}'**
  String sosCallEmergency(String number);

  /// Error when the dialer could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the phone app. Please dial {number} yourself.'**
  String sosCallFailed(String number);

  /// Title of the row that shows the member's location sharing mode and opens the location settings.
  ///
  /// In en, this message translates to:
  /// **'Your location during SOS'**
  String get sosLocationModeTitle;

  /// Title of the panel while the member's own SOS is active.
  ///
  /// In en, this message translates to:
  /// **'Your SOS is active'**
  String get sosActiveTitle;

  /// Indicator while the live location is being shared during the member's SOS.
  ///
  /// In en, this message translates to:
  /// **'Sharing your live location with family'**
  String get sosSharingLive;

  /// Indicator while the member's SOS is active without location sharing.
  ///
  /// In en, this message translates to:
  /// **'Your location is not being shared'**
  String get sosNotSharingLocation;

  /// Explanation under the indicator when the member's sharing mode is Never.
  ///
  /// In en, this message translates to:
  /// **'Your location sharing is set to Never, so your family can\'t see where you are.'**
  String get sosLocationOffHint;

  /// Button under 'Your location is not being shared' that opens the location sharing settings.
  ///
  /// In en, this message translates to:
  /// **'Change location sharing'**
  String get sosChangeSharing;

  /// Button on the active SOS panel that opens the alert screen.
  ///
  /// In en, this message translates to:
  /// **'View alert details'**
  String get sosViewAlert;

  /// Time left in the 15-minute live window, e.g. 'Ends in 14:05'.
  ///
  /// In en, this message translates to:
  /// **'Ends in {time}'**
  String sosTimeRemaining(String time);

  /// When the location last reached the family, e.g. 'Location sent 5 seconds ago'.
  ///
  /// In en, this message translates to:
  /// **'Location sent {time}'**
  String sosLastSent(String time);

  /// Shown until the first location of the member's SOS reached the server.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your location…'**
  String get sosWaitingForLocation;

  /// Relative time under one minute, used for live location updates.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =0{just now} =1{1 second ago} other{{seconds} seconds ago}}'**
  String sosSecondsAgo(int seconds);

  /// Button that ends the member's own SOS as safe.
  ///
  /// In en, this message translates to:
  /// **'I am okay'**
  String get sosImOkay;

  /// Button that ends the member's own SOS as a false alarm.
  ///
  /// In en, this message translates to:
  /// **'False alarm'**
  String get sosFalseAlarm;

  /// Snackbar after the member ended their SOS with 'I am okay'.
  ///
  /// In en, this message translates to:
  /// **'Glad you are okay. Your family has been told.'**
  String get sosResolvedSafe;

  /// Snackbar after the member ended their SOS as a false alarm.
  ///
  /// In en, this message translates to:
  /// **'SOS ended as a false alarm. Your family has been told.'**
  String get sosResolvedFalseAlarm;

  /// Section title of other members' active alerts on the SOS screen.
  ///
  /// In en, this message translates to:
  /// **'Family alerts'**
  String get sosOthersTitle;

  /// Shown when no other member has an active SOS.
  ///
  /// In en, this message translates to:
  /// **'No one in your family needs help right now.'**
  String get sosOthersEmpty;

  /// Row on the SOS screen that opens the SOS history.
  ///
  /// In en, this message translates to:
  /// **'Past alerts'**
  String get sosHistoryLink;

  /// Title of the dialog shown when sending an SOS while location sharing is set to Never.
  ///
  /// In en, this message translates to:
  /// **'Share your location?'**
  String get sosLocationDialogTitle;

  /// Message of the location question dialog.
  ///
  /// In en, this message translates to:
  /// **'Your location sharing is set to Never. Your family can find you faster if they see your live location while this SOS is active.'**
  String get sosLocationDialogMessage;

  /// Dialog button: switch sharing to 'only during SOS' and send the location.
  ///
  /// In en, this message translates to:
  /// **'Share location for SOS only'**
  String get sosLocationDialogShare;

  /// Dialog button: send the SOS without location.
  ///
  /// In en, this message translates to:
  /// **'Send without location'**
  String get sosLocationDialogWithout;

  /// Countdown line in the 'share your location?' dialog: the SOS is sent without location automatically when nobody answers.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{If you don\'t choose, it is sent without your location in 1 second.} other{If you don\'t choose, it is sent without your location in {seconds} seconds.}}'**
  String sosLocationDialogAutoSend(int seconds);

  /// Global red banner while the member's own SOS is active and the location is shared.
  ///
  /// In en, this message translates to:
  /// **'Your SOS is active – sharing live location'**
  String get sosBannerSharing;

  /// Global red banner while the member's own SOS is active without location.
  ///
  /// In en, this message translates to:
  /// **'Your SOS is active'**
  String get sosBannerActive;

  /// Global banner / alert screen headline when another member raised an SOS.
  ///
  /// In en, this message translates to:
  /// **'{name} needs help'**
  String sosNeedsHelp(String name);

  /// Global banner when several members have an active SOS.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 family member needs help} other{{count} family members need help}}'**
  String sosManyNeedHelp(int count);

  /// Button on the global SOS banner that opens the alert.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get sosBannerOpen;

  /// Name shown for an alert of a member who left the family.
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get sosFormerMember;

  /// Status chip: the SOS is active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get sosStatusActive;

  /// Status chip: the SOS was resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get sosStatusResolved;

  /// Status chip: the 15-minute SOS window passed without resolution.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get sosStatusExpired;

  /// Resolution: the member said they are okay.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get sosResolutionSafe;

  /// Resolution: the alert was an accident.
  ///
  /// In en, this message translates to:
  /// **'False alarm'**
  String get sosResolutionFalseAlarm;

  /// Resolution: an admin marked the member as helped.
  ///
  /// In en, this message translates to:
  /// **'Helped'**
  String get sosResolutionHelped;

  /// When the alert started, e.g. 'Started 5 minutes ago'.
  ///
  /// In en, this message translates to:
  /// **'Started {time}'**
  String sosStarted(String time);

  /// When the alert ended, e.g. 'Ended 26 Sep, 10:15 AM'.
  ///
  /// In en, this message translates to:
  /// **'Ended {time}'**
  String sosEnded(String time);

  /// Tile hint: the alert shares a live location.
  ///
  /// In en, this message translates to:
  /// **'Live location'**
  String get sosLiveLocation;

  /// Tile hint: the alert does not share a location.
  ///
  /// In en, this message translates to:
  /// **'No location shared'**
  String get sosNoLocation;

  /// App bar title of the alert detail screen.
  ///
  /// In en, this message translates to:
  /// **'SOS alert'**
  String get sosAlertTitle;

  /// Headline of the alert detail screen when it is the viewer's own alert.
  ///
  /// In en, this message translates to:
  /// **'Your SOS'**
  String get sosYourAlert;

  /// Label above the optional SOS message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get sosMessageLabel;

  /// Title of the location card on the alert screen.
  ///
  /// In en, this message translates to:
  /// **'Last location'**
  String get sosLastLocationTitle;

  /// GPS accuracy radius in metres.
  ///
  /// In en, this message translates to:
  /// **'Accurate to about {meters} m'**
  String sosAccuracy(String meters);

  /// When the location was recorded, e.g. 'Updated 5 seconds ago'.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String sosUpdated(String time);

  /// Latitude and longitude, e.g. '28.613900, 77.209000'.
  ///
  /// In en, this message translates to:
  /// **'{lat}, {lng}'**
  String sosCoordinates(String lat, String lng);

  /// Button that opens the location in the maps app.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get sosOpenInMaps;

  /// Error when no maps app / browser could open the location.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the maps app.'**
  String get sosMapsFailed;

  /// Alert screen: the member's sharing mode is Never.
  ///
  /// In en, this message translates to:
  /// **'{name} is not sharing their location.'**
  String sosNoLocationShared(String name);

  /// Alert screen: location sharing is on but no location has arrived yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first location…'**
  String get sosWaitingForMemberLocation;

  /// Section title of the recent location points of an alert.
  ///
  /// In en, this message translates to:
  /// **'Recent locations'**
  String get sosTrailTitle;

  /// Button that calls the member who raised the SOS.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String sosCallMember(String name);

  /// Admin button that ends another member's SOS as helped.
  ///
  /// In en, this message translates to:
  /// **'Mark as helped'**
  String get sosMarkHelped;

  /// Title of the confirmation before an admin marks an SOS as helped.
  ///
  /// In en, this message translates to:
  /// **'End this SOS?'**
  String get sosMarkHelpedConfirmTitle;

  /// Confirmation message before an admin marks an SOS as helped.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s alert ends for everyone and live location sharing stops. Only do this when {name} is safe.'**
  String sosMarkHelpedConfirmMessage(String name);

  /// Snackbar after an admin marked an SOS as helped.
  ///
  /// In en, this message translates to:
  /// **'The SOS was marked as helped.'**
  String get sosMarkedHelped;

  /// How and by whom an alert was resolved, e.g. 'Helped · by Amit'.
  ///
  /// In en, this message translates to:
  /// **'{resolution} · by {name}'**
  String sosResolvedBy(String resolution, String name);

  /// Title when an SOS alert does not exist (removed member, wrong family, bad link).
  ///
  /// In en, this message translates to:
  /// **'Alert not available'**
  String get sosAlertGoneTitle;

  /// Message when an SOS alert does not exist.
  ///
  /// In en, this message translates to:
  /// **'This SOS alert no longer exists or belongs to another family.'**
  String get sosAlertGoneMessage;

  /// Button on the 'alert not available' state that opens the SOS tab.
  ///
  /// In en, this message translates to:
  /// **'Go to SOS'**
  String get sosBackToSos;

  /// Section title of the member's emergency card on the alert screen.
  ///
  /// In en, this message translates to:
  /// **'Emergency card'**
  String get sosEmergencyCardTitle;

  /// App bar title of the SOS history screen.
  ///
  /// In en, this message translates to:
  /// **'SOS history'**
  String get sosHistoryTitle;

  /// Empty state title of the SOS history.
  ///
  /// In en, this message translates to:
  /// **'No past alerts'**
  String get sosHistoryEmptyTitle;

  /// Empty state message of the SOS history.
  ///
  /// In en, this message translates to:
  /// **'Alerts that were resolved or ended appear here.'**
  String get sosHistoryEmptyMessage;

  /// App bar title of the Tasks tab.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTitle;

  /// Button that opens the form to create a task.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get tasksNewTask;

  /// Segment of the Tasks tab: the signed-in member's pending tasks.
  ///
  /// In en, this message translates to:
  /// **'My tasks'**
  String get tasksViewMine;

  /// Segment of the Tasks tab: pending tasks of the whole family.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get tasksViewFamily;

  /// Segment of the Tasks tab: completed tasks.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tasksViewDone;

  /// Filter chip: tasks whose due date has passed.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get tasksDueOverdue;

  /// Filter chip: tasks due today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tasksDueToday;

  /// Filter chip: tasks due this week (Monday to Sunday).
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get tasksDueWeek;

  /// Screen-reader label of the due date filter chips.
  ///
  /// In en, this message translates to:
  /// **'Filter by due date'**
  String get tasksFilterDueLabel;

  /// Screen-reader label of the member filter chips.
  ///
  /// In en, this message translates to:
  /// **'Filter by family member'**
  String get tasksFilterMemberLabel;

  /// Member filter chip: tasks of all family members.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get tasksFilterEveryone;

  /// Section header in the task list: due date has passed.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get tasksSectionOverdue;

  /// Section header in the task list: due today.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get tasksSectionToday;

  /// Section header in the task list: due later.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get tasksSectionUpcoming;

  /// Section header in the task list: tasks without a due date.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get tasksSectionNoDueDate;

  /// Number of pending tasks (task list summary, dashboard member row).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pending tasks} =1{1 pending task} other{{count} pending tasks}}'**
  String tasksPendingCount(int count);

  /// Number of completed tasks (summary above the Done list).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No completed tasks} =1{1 completed task} other{{count} completed tasks}}'**
  String tasksDoneCount(int count);

  /// Empty state: the signed-in member has no pending tasks.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up!'**
  String get tasksEmptyMineTitle;

  /// Empty state message: the signed-in member has no pending tasks.
  ///
  /// In en, this message translates to:
  /// **'No pending tasks for you. Enjoy the free time or add something new.'**
  String get tasksEmptyMineMessage;

  /// Empty state: nobody in the family has pending tasks.
  ///
  /// In en, this message translates to:
  /// **'No pending family tasks'**
  String get tasksEmptyFamilyTitle;

  /// Empty state message of the Family view.
  ///
  /// In en, this message translates to:
  /// **'Assign a task to get everyone moving.'**
  String get tasksEmptyFamilyMessage;

  /// Empty state of the Family view filtered to one member.
  ///
  /// In en, this message translates to:
  /// **'{name} has no pending tasks'**
  String tasksEmptyMemberTitle(String name);

  /// Empty state of the Overdue filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing overdue'**
  String get tasksEmptyOverdueTitle;

  /// Empty state message of the Overdue filter.
  ///
  /// In en, this message translates to:
  /// **'Great job staying on top of things.'**
  String get tasksEmptyOverdueMessage;

  /// Empty state of the Today filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing due today'**
  String get tasksEmptyTodayTitle;

  /// Empty state message of the Today filter.
  ///
  /// In en, this message translates to:
  /// **'The day is clear. Plan ahead or take a break.'**
  String get tasksEmptyTodayMessage;

  /// Empty state of the This week filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing due this week'**
  String get tasksEmptyWeekTitle;

  /// Empty state message of the This week filter.
  ///
  /// In en, this message translates to:
  /// **'Add a due date to tasks to see them here.'**
  String get tasksEmptyWeekMessage;

  /// Empty state of the Done view.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks yet'**
  String get tasksEmptyDoneTitle;

  /// Empty state of the Done view filtered to one member.
  ///
  /// In en, this message translates to:
  /// **'{name} hasn\'t completed any tasks yet'**
  String tasksEmptyDoneMemberTitle(String name);

  /// Empty state message of the Done view.
  ///
  /// In en, this message translates to:
  /// **'Completed tasks will show up here.'**
  String get tasksEmptyDoneMessage;

  /// Task status: not done yet.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get tasksStatusPending;

  /// Task status: completed.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tasksStatusDone;

  /// Status chip of a pending task whose due date has passed.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get tasksStatusOverdue;

  /// Task category: homework, reading, learning.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get tasksCategoryStudy;

  /// Task category: household chore.
  ///
  /// In en, this message translates to:
  /// **'Chore'**
  String get tasksCategoryChore;

  /// Task category: practising or learning a skill.
  ///
  /// In en, this message translates to:
  /// **'Skill'**
  String get tasksCategorySkill;

  /// Task category: medicine, exercise, check-ups.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get tasksCategoryHealth;

  /// Task category: bills, shopping, appointments.
  ///
  /// In en, this message translates to:
  /// **'Errand'**
  String get tasksCategoryErrand;

  /// Task category: anything else.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get tasksCategoryOther;

  /// Task priority.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get tasksPriorityLow;

  /// Task priority.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get tasksPriorityMedium;

  /// Task priority.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get tasksPriorityHigh;

  /// Priority chip / screen-reader label, e.g. 'High priority'.
  ///
  /// In en, this message translates to:
  /// **'{priority} priority'**
  String tasksPrioritySemantics(String priority);

  /// Checkbox label / button that completes a task.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get tasksMarkDone;

  /// Screen-reader label of the checkbox of a completed task.
  ///
  /// In en, this message translates to:
  /// **'Mark as not done'**
  String get tasksMarkNotDone;

  /// Button that sets a completed task back to pending.
  ///
  /// In en, this message translates to:
  /// **'Reopen task'**
  String get tasksReopen;

  /// Snackbar after completing a task.
  ///
  /// In en, this message translates to:
  /// **'Nice work! Task completed.'**
  String get tasksMarkedDone;

  /// Snackbar after reopening a task.
  ///
  /// In en, this message translates to:
  /// **'Task reopened'**
  String get tasksReopened;

  /// Screen-reader label of a task's due date, e.g. 'Due Tomorrow'.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String tasksDueSemantics(String date);

  /// Screen-reader label of an overdue task's due date.
  ///
  /// In en, this message translates to:
  /// **'Overdue, was due {date}'**
  String tasksOverdueSemantics(String date);

  /// Relative due date in the future, e.g. 'in 3 days'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{in 1 day} other{in {count} days}}'**
  String tasksDueInDays(int count);

  /// Screen-reader label of a task's assignee.
  ///
  /// In en, this message translates to:
  /// **'Assigned to {name}'**
  String tasksAssignedToSemantics(String name);

  /// App bar title of the task detail screen.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get tasksDetailTitle;

  /// Task detail row label.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get tasksInfoAssignee;

  /// Task detail row label.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get tasksInfoDue;

  /// Task detail value when the task has no due date.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get tasksInfoNoDueDate;

  /// Task detail row label.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get tasksInfoCreatedBy;

  /// Task detail row label.
  ///
  /// In en, this message translates to:
  /// **'Completed by'**
  String get tasksInfoCompletedBy;

  /// Task detail row label.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get tasksInfoUpdated;

  /// Who did something and when, e.g. 'Priya · 2 hours ago'.
  ///
  /// In en, this message translates to:
  /// **'{name} · {time}'**
  String tasksPersonAtTime(String name, String time);

  /// The signed-in member in an assignee picker / detail.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String tasksAssigneeMe(String name);

  /// Task detail note when the viewer may not complete / reopen the task.
  ///
  /// In en, this message translates to:
  /// **'Only {name} or an admin can change the status of this task.'**
  String tasksCompleteNotAllowed(String name);

  /// Confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete this task?'**
  String get tasksDeleteTitle;

  /// Confirmation dialog message before deleting a task.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be removed for the whole family. This can\'t be undone.'**
  String tasksDeleteMessage(String title);

  /// Snackbar / state after deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Task deleted'**
  String get tasksDeleted;

  /// App bar title of the create-task form.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get tasksFormNewTitle;

  /// App bar title of the edit-task form.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get tasksFormEditTitle;

  /// Form field: family member who should do the task.
  ///
  /// In en, this message translates to:
  /// **'Assign to'**
  String get tasksFieldAssignee;

  /// Validation error: no assignee selected.
  ///
  /// In en, this message translates to:
  /// **'Choose who should do this task'**
  String get tasksFieldAssigneeRequired;

  /// Helper text under the locked assignee field for non-admins.
  ///
  /// In en, this message translates to:
  /// **'Only admins can assign tasks to other family members.'**
  String get tasksAssigneeSelfOnly;

  /// Form field: task title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get tasksFieldTitle;

  /// Hint of the task title field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Finish maths homework'**
  String get tasksFieldTitleHint;

  /// Form field: task description.
  ///
  /// In en, this message translates to:
  /// **'Details (optional)'**
  String get tasksFieldDescription;

  /// Hint of the task description field.
  ///
  /// In en, this message translates to:
  /// **'Anything that helps to get it done'**
  String get tasksFieldDescriptionHint;

  /// Form field: task due date.
  ///
  /// In en, this message translates to:
  /// **'Due date (optional)'**
  String get tasksFieldDueDate;

  /// Form section label: task category chips.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get tasksFieldCategory;

  /// Form section label: task priority chips.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get tasksFieldPriority;

  /// Submit button of the create-task form.
  ///
  /// In en, this message translates to:
  /// **'Create task'**
  String get tasksCreate;

  /// Submit button of the edit-task form.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get tasksSaveChanges;

  /// Snackbar after creating a task.
  ///
  /// In en, this message translates to:
  /// **'Task created'**
  String get tasksCreated;

  /// Snackbar after editing a task.
  ///
  /// In en, this message translates to:
  /// **'Task updated'**
  String get tasksUpdated;

  /// Shown when the edit form is opened without permission.
  ///
  /// In en, this message translates to:
  /// **'You can\'t edit this task'**
  String get tasksEditNotAllowedTitle;

  /// Shown when the edit form is opened without permission.
  ///
  /// In en, this message translates to:
  /// **'Only an admin or the person who created it can make changes.'**
  String get tasksEditNotAllowedMessage;

  /// Header of the task template chips.
  ///
  /// In en, this message translates to:
  /// **'Quick ideas'**
  String get tasksTemplatesTitle;

  /// Header of the age-appropriate task template chips for the chosen assignee.
  ///
  /// In en, this message translates to:
  /// **'Quick ideas for {name}'**
  String tasksTemplatesFor(String name);

  /// Task template for a child.
  ///
  /// In en, this message translates to:
  /// **'Finish homework'**
  String get tasksTemplateHomeworkTitle;

  /// Task template for a child.
  ///
  /// In en, this message translates to:
  /// **'Complete today\'s homework and pack the school bag for tomorrow.'**
  String get tasksTemplateHomeworkDescription;

  /// Task template for a child.
  ///
  /// In en, this message translates to:
  /// **'Tidy your room'**
  String get tasksTemplateTidyRoomTitle;

  /// Task template for a child.
  ///
  /// In en, this message translates to:
  /// **'Put toys and clothes away and make the bed.'**
  String get tasksTemplateTidyRoomDescription;

  /// Task template for a child.
  ///
  /// In en, this message translates to:
  /// **'Read for 20 minutes'**
  String get tasksTemplateReadTitle;

  /// Task template for a child.
  ///
  /// In en, this message translates to:
  /// **'Pick a favourite book and read for 20 minutes.'**
  String get tasksTemplateReadDescription;

  /// Task template for a teenager.
  ///
  /// In en, this message translates to:
  /// **'Learn a new skill'**
  String get tasksTemplateLearnSkillTitle;

  /// Task template for a teenager.
  ///
  /// In en, this message translates to:
  /// **'Spend 30 minutes on something new: coding, music, a language or a craft.'**
  String get tasksTemplateLearnSkillDescription;

  /// Task template for a teenager.
  ///
  /// In en, this message translates to:
  /// **'Help cook a family meal'**
  String get tasksTemplateHelpCookTitle;

  /// Task template for a teenager.
  ///
  /// In en, this message translates to:
  /// **'Help plan, cook and clean up after one family meal.'**
  String get tasksTemplateHelpCookDescription;

  /// Task template for a teenager (managing pocket money).
  ///
  /// In en, this message translates to:
  /// **'Budget practice'**
  String get tasksTemplateBudgetTitle;

  /// Task template for a teenager.
  ///
  /// In en, this message translates to:
  /// **'Plan this week\'s pocket money: what to save and what to spend.'**
  String get tasksTemplateBudgetDescription;

  /// Task template for an adult.
  ///
  /// In en, this message translates to:
  /// **'Pay the bills'**
  String get tasksTemplatePayBillsTitle;

  /// Task template for an adult.
  ///
  /// In en, this message translates to:
  /// **'Check and pay this month\'s electricity, water, phone and internet bills.'**
  String get tasksTemplatePayBillsDescription;

  /// Task template for an adult: talk to a family member.
  ///
  /// In en, this message translates to:
  /// **'Family check-in'**
  String get tasksTemplateCheckInTitle;

  /// Task template for an adult.
  ///
  /// In en, this message translates to:
  /// **'Call or sit with a family member and ask how they are doing.'**
  String get tasksTemplateCheckInDescription;

  /// Task template for a senior (medicine reminder).
  ///
  /// In en, this message translates to:
  /// **'Take medicines on time'**
  String get tasksTemplateMedicineTitle;

  /// Task template for a senior.
  ///
  /// In en, this message translates to:
  /// **'Take the prescribed medicines at the right time, with water.'**
  String get tasksTemplateMedicineDescription;

  /// Task template for a senior.
  ///
  /// In en, this message translates to:
  /// **'Take a gentle walk'**
  String get tasksTemplateWalkTitle;

  /// Task template for a senior.
  ///
  /// In en, this message translates to:
  /// **'Go for a 20-minute walk, ideally with someone from the family.'**
  String get tasksTemplateWalkDescription;

  /// Placeholder name for a person who is no longer in the family (e.g. the assignee of an old completed task).
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get tasksFormerMember;

  /// Shown when opening a task (e.g. from a notification) that was deleted or is not in the user's family.
  ///
  /// In en, this message translates to:
  /// **'This task is no longer available'**
  String get tasksGoneTitle;

  /// Message under tasksGoneTitle.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted by someone in your family.'**
  String get tasksGoneMessage;

  /// Button that leaves a missing task and opens the Tasks tab.
  ///
  /// In en, this message translates to:
  /// **'Back to tasks'**
  String get tasksBackToTasks;

  /// Error when saving, completing or deleting a task that no longer exists.
  ///
  /// In en, this message translates to:
  /// **'This task was deleted by someone else.'**
  String get tasksErrorGone;

  /// Error when the server refuses an edit/delete (e.g. the user's admin role was removed meanwhile).
  ///
  /// In en, this message translates to:
  /// **'Only an admin or the person who created this task can change or delete it.'**
  String get tasksErrorEditNotAllowed;

  /// Error when the server refuses complete/reopen.
  ///
  /// In en, this message translates to:
  /// **'Only the person the task is assigned to or an admin can complete or reopen it.'**
  String get tasksErrorCompleteNotAllowed;

  /// Error when a non-admin tries to create or move a task for someone else.
  ///
  /// In en, this message translates to:
  /// **'You can only assign tasks to yourself. Ask an admin to assign tasks to others.'**
  String get tasksErrorAssignSelfOnly;

  /// Error when the chosen assignee was removed from the family meanwhile.
  ///
  /// In en, this message translates to:
  /// **'That person is no longer in your family. Please choose someone else.'**
  String get tasksErrorAssigneeNotInFamily;

  /// Error when reopening a completed task whose assignee left the family.
  ///
  /// In en, this message translates to:
  /// **'The person this task was assigned to is no longer in your family. Assign it to someone else first.'**
  String get tasksErrorAssigneeRemoved;

  /// Shown instead of the Reopen button when the assignee left the family (the API no longer knows their name).
  ///
  /// In en, this message translates to:
  /// **'This task can\'t be reopened because the person it was assigned to is no longer in your family. An admin or the task\'s creator can assign it to someone else first.'**
  String get tasksReopenAssigneeGone;

  /// Helper under the assignee field when editing a task whose assignee left the family.
  ///
  /// In en, this message translates to:
  /// **'The person this task was assigned to is no longer in your family. You can keep it as it is or choose someone else.'**
  String get tasksAssigneeFormer;

  /// Shown on the new-task screen when the user is not a member of a family.
  ///
  /// In en, this message translates to:
  /// **'You can\'t create tasks right now'**
  String get tasksCreateNotAllowedTitle;

  /// Message under tasksCreateNotAllowedTitle.
  ///
  /// In en, this message translates to:
  /// **'Only members of a family can create tasks.'**
  String get tasksCreateNotAllowedMessage;

  /// Subtitle in the gradient header of the Tasks tab in the 'My tasks' view.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what\'s on your list'**
  String get tasksHeaderSubtitleMine;

  /// Subtitle in the gradient header of the Tasks tab when showing the whole family's tasks.
  ///
  /// In en, this message translates to:
  /// **'Everything your family is working on'**
  String get tasksHeaderSubtitleFamily;

  /// Subtitle in the gradient header of the Tasks tab when the list is filtered to one family member.
  ///
  /// In en, this message translates to:
  /// **'What {name} is working on'**
  String tasksHeaderSubtitleMember(String name);

  /// Label of the header counter: tasks completed since Monday.
  ///
  /// In en, this message translates to:
  /// **'Done this week'**
  String get tasksHeaderDoneThisWeek;

  /// Label of the progress bar in the Tasks header: tasks done this week compared to tasks done this week plus pending tasks.
  ///
  /// In en, this message translates to:
  /// **'Weekly progress'**
  String get tasksHeaderProgress;

  /// Header counter when only part of the list is loaded and there are at least this many, e.g. '20+'.
  ///
  /// In en, this message translates to:
  /// **'{count}+'**
  String tasksHeaderCountAtLeast(String count);

  /// Section title of the task form that holds the title and details fields.
  ///
  /// In en, this message translates to:
  /// **'What needs doing'**
  String get tasksFormSectionTask;

  /// Form validation: empty required field.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get validationRequired;

  /// Form validation: malformed email.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get validationEmail;

  /// Form validation: password shorter than 8 characters.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get validationPasswordLength;

  /// Form validation: password needs a letter and a digit.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one letter and one number'**
  String get validationPasswordComplexity;

  /// Form validation: confirm password differs.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get validationPasswordMismatch;

  /// Form validation: text shorter than min characters.
  ///
  /// In en, this message translates to:
  /// **'{min, plural, =1{Enter at least 1 character} other{Enter at least {min} characters}}'**
  String validationMinLength(int min);

  /// Form validation: text longer than max characters.
  ///
  /// In en, this message translates to:
  /// **'{max, plural, =1{Use at most 1 character} other{Use at most {max} characters}}'**
  String validationMaxLength(int max);

  /// Form validation: amount missing, not a number or not positive.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero'**
  String get validationAmount;

  /// Form validation: amount above the 1,000,000,000,000 limit.
  ///
  /// In en, this message translates to:
  /// **'This amount is too large'**
  String get validationAmountTooLarge;

  /// Form validation: more than 2 decimals in an amount.
  ///
  /// In en, this message translates to:
  /// **'Use at most 2 decimal places'**
  String get validationAmountDecimals;

  /// Form validation: phone number format.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number (6 to 15 digits, optional +country code)'**
  String get validationPhone;

  /// Form validation: OTP must be exactly 6 digits.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get validationOtp;

  /// Form validation: family invite code format (8 characters).
  ///
  /// In en, this message translates to:
  /// **'Invite codes have 8 letters and numbers'**
  String get validationInviteCode;

  /// Shown by the photo picker when the user has denied camera / photo library permission.
  ///
  /// In en, this message translates to:
  /// **'FamilyHub can\'t open your camera or photos. Please allow access in your phone\'s Settings and try again.'**
  String get widgetPhotoPermissionDenied;

  /// Shown by the photo picker when the selected source (e.g. camera) is not supported on the device.
  ///
  /// In en, this message translates to:
  /// **'This option isn\'t available on this device.'**
  String get widgetPhotoSourceUnavailable;

  /// Small inline notice above a list or screen when refreshing failed but older data is still displayed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. Showing the last loaded information.'**
  String get widgetStaleDataNotice;

  /// Screen-reader value of a progress bar, e.g. '45% complete'. {percent} is an already formatted percentage including the % sign.
  ///
  /// In en, this message translates to:
  /// **'{percent} complete'**
  String widgetProgressLabel(String percent);

  /// Screen-reader label of a photo picker field when no custom label is given.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get widgetPhotoLabel;

  /// Tooltip / screen-reader label of the clear button inside a date field.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get widgetClearDate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
