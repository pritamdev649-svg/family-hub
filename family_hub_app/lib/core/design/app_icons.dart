import 'package:flutter/widgets.dart';

/// Central icon set — **Phosphor Light** (thin 1.5 px outline icons) from the
/// `phosphor_flutter` package. Feature code must only use `AppIcons.*`, never
/// `Icons.*` or `PhosphorIcons*` directly, so the whole app keeps one visual
/// language and the icon font stays tree-shakable (every icon is `const`).
///
/// Only directional icons (arrows, chevrons, sign in/out) mirror in RTL
/// layouts; everything else keeps its orientation.
abstract final class AppIcons {
  // ── Navigation (light = unselected, bold-looking fill = selected) ─────────
  static const IconData home = _Ph(0xe2c2); // house
  static const IconData homeSelected = _Ph(0xe2c2); // house
  static const IconData tasks = _Ph(0xe188); // checkSquareOffset
  static const IconData tasksSelected = _Ph(0xe188); // checkSquareOffset
  static const IconData sos = _Ph(0xe9b8); // siren
  static const IconData sosSelected = _Ph(0xe9b8); // siren
  static const IconData money = _Ph(0xe68a); // wallet
  static const IconData moneySelected = _Ph(0xe68a); // wallet
  static const IconData more = _Ph(0xe464); // squaresFour
  static const IconData moreSelected = _Ph(0xe464); // squaresFour

  // ── Family & members ──────────────────────────────────────────────────────
  static const IconData family = _Ph(0xe68e); // usersThree
  static const IconData members = _Ph(0xe68e); // usersThree
  static const IconData member = _Ph(0xe4c2); // user
  static const IconData memberOutlined = _Ph(0xe4c4); // userCircle
  static const IconData addMember = _Ph(0xe4d0); // userPlus
  static const IconData admin = _Ph(0xec34); // shieldStar
  static const IconData designation = _Ph(0xe6f6); // identificationBadge
  static const IconData birthday = _Ph(0xe780); // cake
  static const IconData gender = _Ph(0xe6e6); // genderIntersex
  static const IconData guardian = _Ph(0xe68c); // usersFour
  static const IconData inviteCode = _Ph(0xe2d6); // key
  static const IconData roleAdmin = _Ph(0xe614); // crown
  static const IconData roleMember = _Ph(0xe4c2); // user

  // ── Tasks ─────────────────────────────────────────────────────────────────
  static const IconData task = _Ph(0xeadc); // listChecks
  static const IconData taskDone = _Ph(0xe184); // checkCircle
  static const IconData taskPending = _Ph(0xe18a); // circle
  static const IconData overdue = _Ph(0xe10c); // calendarX
  static const IconData dueDate = _Ph(0xe10a); // calendarBlank
  static const IconData priority = _Ph(0xe244); // flag
  static const IconData category = _Ph(0xe464); // squaresFour
  static const IconData doneAll = _Ph(0xe53a); // checks
  static const IconData taskStudy = _Ph(0xe8f2); // bookOpenText
  static const IconData taskChore = _Ph(0xec54); // broom
  static const IconData taskSkill = _Ph(0xe2dc); // lightbulb
  static const IconData taskHealth = _Ph(0xe2ac); // heartbeat
  static const IconData taskErrand = _Ph(0xe416); // shoppingBag
  static const IconData taskOther = _Ph(0xe478); // tag
  static const IconData priorityHigh = _Ph(0xe12c); // caretDoubleUp
  static const IconData priorityMedium = _Ph(0xe21c); // equals
  static const IconData priorityLow = _Ph(0xe126); // caretDoubleDown
  static const IconData template = _Ph(0xe6a2); // sparkle

  // ── Money ─────────────────────────────────────────────────────────────────
  static const IconData ledger = _Ph(0xe3ec); // receipt
  static const IconData income = _Ph(0xe02a); // arrowCircleDownLeft
  static const IconData expense = _Ph(0xe034); // arrowCircleUpRight
  static const IconData trendUp = _Ph(0xe4ae); // trendUp
  static const IconData trendDown = _Ph(0xe4ac); // trendDown
  static const IconData goal = _Ph(0xea04); // piggyBank
  static const IconData goalOutlined = _Ph(0xea04); // piggyBank
  static const IconData goalAchieved = _Ph(0xe67e); // trophy
  static const IconData archive = _Ph(0xe00c); // archive
  static const IconData summary = _Ph(0xe15a); // chartPieSlice
  static const IconData target = _Ph(0xe47c); // target
  static const IconData currency = _Ph(0xe78e); // coins
  static const IconData catSalary = _Ph(0xe0ee); // briefcase
  static const IconData catBusiness = _Ph(0xe470); // storefront
  static const IconData catAllowance = _Ph(0xea8c); // handCoins
  static const IconData catGift = _Ph(0xe276); // gift
  static const IconData catInterest = _Ph(0xe3b6); // percent
  static const IconData catOtherIncome = _Ph(0xe3d6); // plusCircle
  static const IconData catGroceries = _Ph(0xe41e); // shoppingCart
  static const IconData catUtilities = _Ph(0xe2de); // lightning
  static const IconData catRent = _Ph(0xe2c4); // houseLine
  static const IconData catEducation = _Ph(0xe62c); // graduationCap
  static const IconData catHealth = _Ph(0xe570); // firstAidKit
  static const IconData catTransport = _Ph(0xe112); // car
  static const IconData catDining = _Ph(0xe262); // forkKnife
  static const IconData catShopping = _Ph(0xe416); // shoppingBag
  static const IconData catEntertainment = _Ph(0xe8c2); // filmSlate
  static const IconData catHouseholdHelp = _Ph(0xec54); // broom
  static const IconData catSavings = _Ph(0xea04); // piggyBank
  static const IconData catOtherExpense = _Ph(0xe3ec); // receipt

  // ── Notices ───────────────────────────────────────────────────────────────
  static const IconData notice = _Ph(0xe324); // megaphone
  static const IconData noticeOutlined = _Ph(0xe642); // megaphoneSimple
  static const IconData pin = _Ph(0xe3e2); // pushPin
  static const IconData unpin = _Ph(0xe3e4); // pushPinSlash

  // ── Emergency card ────────────────────────────────────────────────────────
  static const IconData emergencyCard = _Ph(0xe56e); // firstAid
  static const IconData emergencyCardOutlined = _Ph(0xe56e); // firstAid
  static const IconData bloodGroup = _Ph(0xe210); // drop
  static const IconData allergy = _Ph(0xe3de); // prohibit
  static const IconData medication = _Ph(0xe700); // pill
  static const IconData condition = _Ph(0xe0b2); // bandaids
  static const IconData doctor = _Ph(0xe7ea); // stethoscope
  static const IconData insurance = _Ph(0xe40c); // shieldCheck
  static const IconData emergencyContact = _Ph(0xe6f8); // addressBook
  static const IconData notes = _Ph(0xe63e); // notepad

  // ── SOS & location ────────────────────────────────────────────────────────
  static const IconData sosAlert = _Ph(0xe9b8); // siren
  static const IconData location = _Ph(0xe316); // mapPin
  static const IconData locationOff = _Ph(0xedd4); // gpsSlash
  static const IconData myLocation = _Ph(0xedd6); // gpsFix
  static const IconData liveLocation = _PhMirrored(0xeade); // navigationArrow
  static const IconData map = _Ph(0xe31a); // mapTrifold
  static const IconData safe = _Ph(0xe606); // sealCheck
  static const IconData falseAlarm = _Ph(0xe48e); // thumbsUp
  static const IconData helped = _Ph(0xe810); // handHeart
  static const IconData history = _Ph(0xe1a0); // clockCounterClockwise
  static const IconData locationNever = _Ph(0xedd4); // gpsSlash
  static const IconData locationSosOnly = _Ph(0xe9b8); // siren
  static const IconData locationAlways = _Ph(0xe0f2); // broadcast

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const IconData country = _Ph(0xe28a); // globeHemisphereEast
  static const IconData otp = _Ph(0xe752); // password
  static const IconData login = _PhMirrored(0xe428); // signIn
  static const IconData verifyEmail = _Ph(0xe21a); // envelopeSimpleOpen
  static const IconData resetPassword = _Ph(0xe300); // lockKeyOpen
  static const IconData demo = _Ph(0xe79e); // flask
  static const IconData createFamily = _Ph(0xe2c4); // houseLine
  static const IconData joinFamily = _Ph(0xe7e6); // doorOpen

  // ── Settings ──────────────────────────────────────────────────────────────
  static const IconData settings = _Ph(0xe272); // gearSix
  static const IconData profile = _Ph(0xe4c4); // userCircle
  static const IconData language = _Ph(0xe4a2); // translate
  static const IconData appearance = _Ph(0xe6c8); // palette
  static const IconData darkMode = _Ph(0xe330); // moon
  static const IconData lightMode = _Ph(0xe472); // sun
  static const IconData textSize = _Ph(0xe6ee); // textAa
  static const IconData privacy = _Ph(0xe708); // shieldCheckered
  static const IconData security = _Ph(0xe40a); // shield
  static const IconData password = _Ph(0xe2fe); // lockKey
  static const IconData notifications = _Ph(0xe0ce); // bell
  static const IconData about = _Ph(0xe2ce); // info
  static const IconData logout = _PhMirrored(0xe42a); // signOut
  static const IconData export = _Ph(0xe20c); // downloadSimple

  // ── Contact ───────────────────────────────────────────────────────────────
  static const IconData phone = _Ph(0xe3b8); // phone
  static const IconData calling = _Ph(0xe3ba); // phoneCall
  static const IconData email = _Ph(0xe218); // envelopeSimple
  static const IconData openExternal = _PhMirrored(0xe5de); // arrowSquareOut

  // ── Actions ───────────────────────────────────────────────────────────────
  static const IconData add = _Ph(0xe3d4); // plus
  static const IconData addCircle = _Ph(0xe3d6); // plusCircle
  static const IconData edit = _Ph(0xe3b4); // pencilSimple
  static const IconData delete = _Ph(0xe4a6); // trash
  static const IconData save = _Ph(0xe248); // floppyDisk
  static const IconData close = _Ph(0xe4f6); // x
  static const IconData clear = _Ph(0xe4f8); // xCircle
  static const IconData check = _Ph(0xe182); // check
  static const IconData retry = _PhMirrored(0xe036); // arrowClockwise
  static const IconData reopen = _PhMirrored(0xe038); // arrowCounterClockwise
  static const IconData sync = _Ph(0xe094); // arrowsClockwise
  static const IconData search = _Ph(0xe30c); // magnifyingGlass
  static const IconData filter = _Ph(0xe268); // funnelSimple
  static const IconData share = _Ph(0xe408); // shareNetwork
  static const IconData copy = _Ph(0xe1ca); // copy
  static const IconData menu = _Ph(0xe2f0); // list
  static const IconData moreVert = _Ph(0xe208); // dotsThreeVertical
  static const IconData moreHoriz = _Ph(0xe1fe); // dotsThree
  static const IconData expand = _Ph(0xe136); // caretDown
  static const IconData chevron = _PhMirrored(0xe13a); // caretRight
  static const IconData chevronLeft = _PhMirrored(0xe138); // caretLeft
  static const IconData back = _PhMirrored(0xe058); // arrowLeft
  static const IconData forward = _PhMirrored(0xe06c); // arrowRight
  static const IconData arrowUpRight = _PhMirrored(0xe092); // arrowUpRight

  // ── Time & media ──────────────────────────────────────────────────────────
  static const IconData calendar = _Ph(0xe7b4); // calendarDots
  static const IconData time = _Ph(0xe19a); // clock
  static const IconData visibility = _Ph(0xe220); // eye
  static const IconData visibilityOff = _Ph(0xe224); // eyeSlash
  static const IconData camera = _Ph(0xe10e); // camera
  static const IconData gallery = _Ph(0xe836); // images
  static const IconData addPhoto = _Ph(0xec58); // cameraPlus
  static const IconData image = _Ph(0xe2ca); // image
  static const IconData brokenImage = _Ph(0xe7a8); // imageBroken

  // ── Status / feedback / decoration ────────────────────────────────────────
  static const IconData success = _Ph(0xe184); // checkCircle
  static const IconData info = _Ph(0xe2ce); // info
  static const IconData warning = _Ph(0xe4e0); // warning
  static const IconData error = _Ph(0xe4e2); // warningCircle
  static const IconData offline = _Ph(0xe1b6); // cloudSlash
  static const IconData noConnection = _Ph(0xe4f2); // wifiSlash
  static const IconData empty = _Ph(0xe4aa); // tray
  static const IconData sparkle = _Ph(0xe6a2); // sparkle
  static const IconData heart = _Ph(0xe2a8); // heart
  static const IconData star = _Ph(0xe46a); // star
  static const IconData confetti = _Ph(0xe81a); // confetti
  static const IconData greeting = _Ph(0xe580); // handWaving
  static const IconData morning = _Ph(0xe5b6); // sunHorizon
  static const IconData afternoon = _Ph(0xe472); // sun
  static const IconData evening = _Ph(0xe58e); // moonStars
  static const IconData bell = _Ph(0xe0ce); // bell
  static const IconData lightning = _Ph(0xe2de); // lightning
  static const IconData chart = _Ph(0xe150); // chartBar
  static const IconData fire = _Ph(0xe242); // fire
}

/// Phosphor Light glyph (never mirrored).
class _Ph extends IconData {
  const _Ph(super.codePoint)
    : super(fontFamily: 'PhosphorLight', fontPackage: 'phosphor_flutter');
}

/// Phosphor Light glyph that flips horizontally in right-to-left locales.
class _PhMirrored extends IconData {
  const _PhMirrored(super.codePoint)
    : super(
        fontFamily: 'PhosphorLight',
        fontPackage: 'phosphor_flutter',
        matchTextDirection: true,
      );
}
