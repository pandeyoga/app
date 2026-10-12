import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL
/// returned by `AppL.of(context)`.
///
/// Applications need to include `AppL.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL.localizationsDelegates,
///   supportedLocales: AppL.supportedLocales,
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
/// be consistent with the languages listed in the AppL.supportedLocales
/// property.
abstract class AppL {
  AppL(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL? of(BuildContext context) {
    return Localizations.of<AppL>(context, AppL);
  }

  static const LocalizationsDelegate<AppL> delegate = _AppLDelegate();

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id')
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Revive'**
  String get appName;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Automotive Body Repair Portal'**
  String get appTagline;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @noDataFound.
  ///
  /// In en, this message translates to:
  /// **'No data found.'**
  String get noDataFound;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection.'**
  String get networkError;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirm;

  /// No description provided for @languageId.
  ///
  /// In en, this message translates to:
  /// **'Bahasa Indonesia'**
  String get languageId;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @heroTagBadge.
  ///
  /// In en, this message translates to:
  /// **'AUTOMOTIVE AI CARE'**
  String get heroTagBadge;

  /// No description provided for @heroTitle.
  ///
  /// In en, this message translates to:
  /// **'Body Repair\nMade Simple.'**
  String get heroTitle;

  /// No description provided for @heroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Instant body repair estimation & real-time tracking. Get your car shining faster, with absolute transparency.'**
  String get heroSubtitle;

  /// No description provided for @heroCtaButton.
  ///
  /// In en, this message translates to:
  /// **'Get Free AI Estimate'**
  String get heroCtaButton;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'CONTACT US'**
  String get contactUs;

  /// No description provided for @activeRepair.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE REPAIR'**
  String get activeRepair;

  /// No description provided for @repairProgress.
  ///
  /// In en, this message translates to:
  /// **'Repair Progress'**
  String get repairProgress;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgress;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @trackLive.
  ///
  /// In en, this message translates to:
  /// **'Track Live'**
  String get trackLive;

  /// No description provided for @newClaim.
  ///
  /// In en, this message translates to:
  /// **'New Claim'**
  String get newClaim;

  /// No description provided for @newClaimDesc.
  ///
  /// In en, this message translates to:
  /// **'Scan car damage with AI'**
  String get newClaimDesc;

  /// No description provided for @startScan.
  ///
  /// In en, this message translates to:
  /// **'Start Scan'**
  String get startScan;

  /// No description provided for @trackStatus.
  ///
  /// In en, this message translates to:
  /// **'Track Status'**
  String get trackStatus;

  /// No description provided for @trackStatusDesc.
  ///
  /// In en, this message translates to:
  /// **'Live workshop cameras'**
  String get trackStatusDesc;

  /// No description provided for @viewQueue.
  ///
  /// In en, this message translates to:
  /// **'View Queue'**
  String get viewQueue;

  /// No description provided for @aiTelemetryHub.
  ///
  /// In en, this message translates to:
  /// **'AI TELEMETRY HUB'**
  String get aiTelemetryHub;

  /// No description provided for @slaLabel.
  ///
  /// In en, this message translates to:
  /// **'SLA < 48 Hrs'**
  String get slaLabel;

  /// No description provided for @networkTitle.
  ///
  /// In en, this message translates to:
  /// **'Jabodetabek Certified Network'**
  String get networkTitle;

  /// No description provided for @networkDesc.
  ///
  /// In en, this message translates to:
  /// **'Over 38 OEM-compliant spray booths with digitized color-matching precision down to 99.4% factory accuracy.'**
  String get networkDesc;

  /// No description provided for @seamlessProcess.
  ///
  /// In en, this message translates to:
  /// **'SEAMLESS PROCESS'**
  String get seamlessProcess;

  /// No description provided for @howItWorks.
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get howItWorks;

  /// No description provided for @step1Title.
  ///
  /// In en, this message translates to:
  /// **'Snap Damage Photos'**
  String get step1Title;

  /// No description provided for @step1Desc.
  ///
  /// In en, this message translates to:
  /// **'Take 3 clear photos around your vehicle dents, scratches, or panel gaps directly in the web scanner.'**
  String get step1Desc;

  /// No description provided for @step2Title.
  ///
  /// In en, this message translates to:
  /// **'Instant AI Assessment'**
  String get step2Title;

  /// No description provided for @step2Desc.
  ///
  /// In en, this message translates to:
  /// **'Get sub-millimeter part analysis and guaranteed fixed-price estimate with parts catalog breakdown.'**
  String get step2Desc;

  /// No description provided for @step3Title.
  ///
  /// In en, this message translates to:
  /// **'Select Hub & Bay'**
  String get step3Title;

  /// No description provided for @step3Desc.
  ///
  /// In en, this message translates to:
  /// **'Choose your closest certified workshop and lock priority slot reservation with door-to-door towing.'**
  String get step3Desc;

  /// No description provided for @step4Title.
  ///
  /// In en, this message translates to:
  /// **'Live Tracking to Handover'**
  String get step4Title;

  /// No description provided for @step4Desc.
  ///
  /// In en, this message translates to:
  /// **'Watch real-time prep, booth painting, and quality control telemetry until delivery back to your driveway.'**
  String get step4Desc;

  /// No description provided for @recentInspections.
  ///
  /// In en, this message translates to:
  /// **'RECENT INSPECTIONS'**
  String get recentInspections;

  /// No description provided for @trustVerified.
  ///
  /// In en, this message translates to:
  /// **'TRUST & VERIFIED'**
  String get trustVerified;

  /// No description provided for @trustTitle.
  ///
  /// In en, this message translates to:
  /// **'Why Revive?'**
  String get trustTitle;

  /// No description provided for @quickLinks.
  ///
  /// In en, this message translates to:
  /// **'QUICK LINKS'**
  String get quickLinks;

  /// No description provided for @linkFaq.
  ///
  /// In en, this message translates to:
  /// **'FAQ & Help'**
  String get linkFaq;

  /// No description provided for @linkAbout.
  ///
  /// In en, this message translates to:
  /// **'About Revive'**
  String get linkAbout;

  /// No description provided for @linkPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get linkPrivacy;

  /// No description provided for @linkSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get linkSupport;

  /// No description provided for @footerCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2025 Revive Technologies Indonesia'**
  String get footerCopyright;

  /// No description provided for @footerTagline.
  ///
  /// In en, this message translates to:
  /// **'AI-Powered Automotive Body Repair'**
  String get footerTagline;

  /// No description provided for @estimatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Damage Estimator'**
  String get estimatorTitle;

  /// No description provided for @estimatorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload a photo and get an instant AI repair estimate'**
  String get estimatorSubtitle;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload Photo'**
  String get uploadPhoto;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @analyzeNow.
  ///
  /// In en, this message translates to:
  /// **'Analyze Now'**
  String get analyzeNow;

  /// No description provided for @estimateResult.
  ///
  /// In en, this message translates to:
  /// **'Estimate Result'**
  String get estimateResult;

  /// No description provided for @totalEstimate.
  ///
  /// In en, this message translates to:
  /// **'Total Estimate'**
  String get totalEstimate;

  /// No description provided for @orderNow.
  ///
  /// In en, this message translates to:
  /// **'Order Now'**
  String get orderNow;

  /// No description provided for @getEstimate.
  ///
  /// In en, this message translates to:
  /// **'Get Estimate'**
  String get getEstimate;

  /// No description provided for @severityLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get severityLight;

  /// No description provided for @severityMedium.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get severityMedium;

  /// No description provided for @severityHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get severityHeavy;

  /// No description provided for @panelDamage.
  ///
  /// In en, this message translates to:
  /// **'Panel Damage'**
  String get panelDamage;

  /// No description provided for @faqTitle.
  ///
  /// In en, this message translates to:
  /// **'FAQ & Support'**
  String get faqTitle;

  /// No description provided for @faqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find answers to common questions'**
  String get faqSubtitle;

  /// No description provided for @faqSearch.
  ///
  /// In en, this message translates to:
  /// **'How does the AI estimation work?'**
  String get faqSearch;

  /// No description provided for @faqNoResults.
  ///
  /// In en, this message translates to:
  /// **'No questions found for your search.'**
  String get faqNoResults;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Revive'**
  String get aboutTitle;

  /// No description provided for @aboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Indonesia\'s premier AI-powered automotive body repair network'**
  String get aboutSubtitle;

  /// No description provided for @ourMission.
  ///
  /// In en, this message translates to:
  /// **'Our Mission'**
  String get ourMission;

  /// No description provided for @ourVision.
  ///
  /// In en, this message translates to:
  /// **'Our Vision'**
  String get ourVision;

  /// No description provided for @ourTeam.
  ///
  /// In en, this message translates to:
  /// **'Our Team'**
  String get ourTeam;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyTitle;

  /// No description provided for @privacyLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get privacyLastUpdated;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get profileTitle;

  /// No description provided for @profileVehicles.
  ///
  /// In en, this message translates to:
  /// **'My Vehicles'**
  String get profileVehicles;

  /// No description provided for @profileOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get profileOrders;

  /// No description provided for @profileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEditProfile;

  /// No description provided for @profileChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get profileChangePassword;

  /// No description provided for @profileNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get profileNotifications;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileSettings;

  /// No description provided for @profileLogout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get profileLogout;

  /// No description provided for @addVehicle.
  ///
  /// In en, this message translates to:
  /// **'Add Vehicle'**
  String get addVehicle;

  /// No description provided for @vehiclePlate.
  ///
  /// In en, this message translates to:
  /// **'License Plate'**
  String get vehiclePlate;

  /// No description provided for @vehicleBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get vehicleBrand;

  /// No description provided for @vehicleModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get vehicleModel;

  /// No description provided for @vehicleYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get vehicleYear;

  /// No description provided for @vehicleColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get vehicleColor;

  /// No description provided for @orderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderTitle;

  /// No description provided for @orderStatus.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get orderStatus;

  /// No description provided for @orderDate.
  ///
  /// In en, this message translates to:
  /// **'Order Date'**
  String get orderDate;

  /// No description provided for @orderTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get orderTotal;

  /// No description provided for @orderWorkshop.
  ///
  /// In en, this message translates to:
  /// **'Workshop'**
  String get orderWorkshop;

  /// No description provided for @checkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Checkout & Booking'**
  String get checkoutTitle;

  /// No description provided for @checkoutLogistics.
  ///
  /// In en, this message translates to:
  /// **'Logistics Configuration'**
  String get checkoutLogistics;

  /// No description provided for @checkoutSelfDeliver.
  ///
  /// In en, this message translates to:
  /// **'Self Delivery'**
  String get checkoutSelfDeliver;

  /// No description provided for @checkoutValetPickup.
  ///
  /// In en, this message translates to:
  /// **'Valet Pickup'**
  String get checkoutValetPickup;

  /// No description provided for @checkoutPickupDetails.
  ///
  /// In en, this message translates to:
  /// **'Pickup Location Details'**
  String get checkoutPickupDetails;

  /// No description provided for @checkoutAddress.
  ///
  /// In en, this message translates to:
  /// **'Full Street Address'**
  String get checkoutAddress;

  /// No description provided for @checkoutLatitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get checkoutLatitude;

  /// No description provided for @checkoutLongitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get checkoutLongitude;

  /// No description provided for @checkoutSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule Intake Date'**
  String get checkoutSchedule;

  /// No description provided for @checkoutVerifiedDate.
  ///
  /// In en, this message translates to:
  /// **'Verified Intake Date'**
  String get checkoutVerifiedDate;

  /// No description provided for @checkoutPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get checkoutPayment;

  /// No description provided for @checkoutOnlinePayment.
  ///
  /// In en, this message translates to:
  /// **'Online / QR / VA'**
  String get checkoutOnlinePayment;

  /// No description provided for @checkoutBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get checkoutBankTransfer;

  /// No description provided for @checkoutTransferProof.
  ///
  /// In en, this message translates to:
  /// **'Transfer Proof'**
  String get checkoutTransferProof;

  /// No description provided for @checkoutUploadProof.
  ///
  /// In en, this message translates to:
  /// **'Upload Proof'**
  String get checkoutUploadProof;

  /// No description provided for @checkoutChangeFile.
  ///
  /// In en, this message translates to:
  /// **'Change File'**
  String get checkoutChangeFile;

  /// No description provided for @checkoutProofSelected.
  ///
  /// In en, this message translates to:
  /// **'Proof Selected'**
  String get checkoutProofSelected;

  /// No description provided for @checkoutUploadHint.
  ///
  /// In en, this message translates to:
  /// **'Please upload an image of your transfer receipt.'**
  String get checkoutUploadHint;

  /// No description provided for @checkoutAiSummary.
  ///
  /// In en, this message translates to:
  /// **'AI Estimate Summary'**
  String get checkoutAiSummary;

  /// No description provided for @checkoutValetFee.
  ///
  /// In en, this message translates to:
  /// **'+ Valet Service Fee Applicable'**
  String get checkoutValetFee;

  /// No description provided for @checkoutPayNow.
  ///
  /// In en, this message translates to:
  /// **'PAY NOW (QR / VA)'**
  String get checkoutPayNow;

  /// No description provided for @checkoutConfirmTransfer.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM BOOKING (TRANSFER)'**
  String get checkoutConfirmTransfer;

  /// No description provided for @checkoutAwaitingWebhook.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Gateway Webhook…'**
  String get checkoutAwaitingWebhook;

  /// No description provided for @checkoutSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get checkoutSummary;

  /// No description provided for @checkoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Place Order'**
  String get checkoutConfirm;

  /// No description provided for @trackingTitle.
  ///
  /// In en, this message translates to:
  /// **'View Repair Tracker'**
  String get trackingTitle;

  /// No description provided for @trackingStatus.
  ///
  /// In en, this message translates to:
  /// **'Service Progress'**
  String get trackingStatus;

  /// No description provided for @trackingWorkshop.
  ///
  /// In en, this message translates to:
  /// **'Workshop Photo Stream'**
  String get trackingWorkshop;

  /// No description provided for @trackingEstimatedReady.
  ///
  /// In en, this message translates to:
  /// **'Estimated Ready'**
  String get trackingEstimatedReady;

  /// No description provided for @trackingLiveTracker.
  ///
  /// In en, this message translates to:
  /// **'Live Tracker'**
  String get trackingLiveTracker;

  /// No description provided for @trackingStepIntake.
  ///
  /// In en, this message translates to:
  /// **'Intake & Submission'**
  String get trackingStepIntake;

  /// No description provided for @trackingStepEvaluated.
  ///
  /// In en, this message translates to:
  /// **'AI Evaluated'**
  String get trackingStepEvaluated;

  /// No description provided for @trackingStepBooked.
  ///
  /// In en, this message translates to:
  /// **'Schedule Booked'**
  String get trackingStepBooked;

  /// No description provided for @trackingStepPaid.
  ///
  /// In en, this message translates to:
  /// **'Payment Confirmed'**
  String get trackingStepPaid;

  /// No description provided for @trackingStepAdmitted.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Admitted'**
  String get trackingStepAdmitted;

  /// No description provided for @trackingStepActive.
  ///
  /// In en, this message translates to:
  /// **'Active Body & Painting'**
  String get trackingStepActive;

  /// No description provided for @trackingStepQC.
  ///
  /// In en, this message translates to:
  /// **'Quality Control Passed'**
  String get trackingStepQC;

  /// No description provided for @trackingStepReady.
  ///
  /// In en, this message translates to:
  /// **'Ready for Pickup / Valet'**
  String get trackingStepReady;

  /// No description provided for @trackingStepDone.
  ///
  /// In en, this message translates to:
  /// **'Handover Complete'**
  String get trackingStepDone;

  /// No description provided for @trackingDescIntake.
  ///
  /// In en, this message translates to:
  /// **'Your repair request has been received and your vehicle details registered.'**
  String get trackingDescIntake;

  /// No description provided for @trackingDescEvaluated.
  ///
  /// In en, this message translates to:
  /// **'Our AI has evaluated the damage and produced a cost estimate for your review.'**
  String get trackingDescEvaluated;

  /// No description provided for @trackingDescBooked.
  ///
  /// In en, this message translates to:
  /// **'Your appointment slot has been secured at the partner workshop.'**
  String get trackingDescBooked;

  /// No description provided for @trackingDescPaid.
  ///
  /// In en, this message translates to:
  /// **'Payment received and confirmed. Your vehicle is queued for admission.'**
  String get trackingDescPaid;

  /// No description provided for @trackingDescAdmitted.
  ///
  /// In en, this message translates to:
  /// **'Your vehicle has been admitted to the workshop bay and work is starting soon.'**
  String get trackingDescAdmitted;

  /// No description provided for @trackingDescActive.
  ///
  /// In en, this message translates to:
  /// **'Active bodywork and painting operations are underway on your vehicle.'**
  String get trackingDescActive;

  /// No description provided for @trackingDescQC.
  ///
  /// In en, this message translates to:
  /// **'Repair work complete. Your vehicle is undergoing our 32-point quality audit.'**
  String get trackingDescQC;

  /// No description provided for @trackingDescReady.
  ///
  /// In en, this message translates to:
  /// **'Your vehicle is ready for collection or valet pickup.'**
  String get trackingDescReady;

  /// No description provided for @trackingDescDone.
  ///
  /// In en, this message translates to:
  /// **'Handover complete. Thank you for choosing Revive!'**
  String get trackingDescDone;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Preferences'**
  String get notificationsTitle;

  /// No description provided for @notifRepairUpdates.
  ///
  /// In en, this message translates to:
  /// **'Repair Updates'**
  String get notifRepairUpdates;

  /// No description provided for @notifRepairUpdatesDesc.
  ///
  /// In en, this message translates to:
  /// **'Get notified on every repair milestone'**
  String get notifRepairUpdatesDesc;

  /// No description provided for @notifPromotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions & Offers'**
  String get notifPromotions;

  /// No description provided for @notifPromotionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Special deals and seasonal offers'**
  String get notifPromotionsDesc;

  /// No description provided for @notifReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get notifReminders;

  /// No description provided for @notifRemindersDesc.
  ///
  /// In en, this message translates to:
  /// **'Vehicle service and appointment reminders'**
  String get notifRemindersDesc;

  /// No description provided for @partnerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get partnerDashboard;

  /// No description provided for @partnerJobs.
  ///
  /// In en, this message translates to:
  /// **'Active Jobs'**
  String get partnerJobs;

  /// No description provided for @partnerWorkshop.
  ///
  /// In en, this message translates to:
  /// **'My Workshop'**
  String get partnerWorkshop;

  /// No description provided for @partnerEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get partnerEarnings;

  /// No description provided for @partnerSettings.
  ///
  /// In en, this message translates to:
  /// **'Workshop Settings'**
  String get partnerSettings;

  /// No description provided for @partnerProfile.
  ///
  /// In en, this message translates to:
  /// **'Partner Profile'**
  String get partnerProfile;

  /// No description provided for @partnerStatus.
  ///
  /// In en, this message translates to:
  /// **'Workshop Status'**
  String get partnerStatus;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @statusBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get statusBusy;

  /// No description provided for @jobAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept Job'**
  String get jobAccept;

  /// No description provided for @jobDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get jobDecline;

  /// No description provided for @jobComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark Complete'**
  String get jobComplete;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Support'**
  String get supportTitle;

  /// No description provided for @supportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re here to help'**
  String get supportSubtitle;

  /// No description provided for @supportHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get supportHowCanWeHelp;

  /// No description provided for @supportFindAnswers.
  ///
  /// In en, this message translates to:
  /// **'Find answers to common questions or contact our support team directly.'**
  String get supportFindAnswers;

  /// No description provided for @supportChat.
  ///
  /// In en, this message translates to:
  /// **'Chat with Us'**
  String get supportChat;

  /// No description provided for @supportEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Support'**
  String get supportEmail;

  /// No description provided for @supportPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get supportPhone;

  /// No description provided for @supportLiveChat.
  ///
  /// In en, this message translates to:
  /// **'Live Chat'**
  String get supportLiveChat;

  /// No description provided for @supportTalkToEstimator.
  ///
  /// In en, this message translates to:
  /// **'Talk to a master estimator'**
  String get supportTalkToEstimator;

  /// No description provided for @supportOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open Chat'**
  String get supportOpenChat;

  /// No description provided for @supportCallUs.
  ///
  /// In en, this message translates to:
  /// **'Call Us'**
  String get supportCallUs;

  /// No description provided for @supportCopyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy Number'**
  String get supportCopyNumber;

  /// No description provided for @supportCopyEmail.
  ///
  /// In en, this message translates to:
  /// **'Copy Email'**
  String get supportCopyEmail;

  /// No description provided for @supportEmergencyTitle.
  ///
  /// In en, this message translates to:
  /// **'24/7 Towing & Emergency Hotline'**
  String get supportEmergencyTitle;

  /// No description provided for @supportBackToProfile.
  ///
  /// In en, this message translates to:
  /// **'Back to My Garage Profile'**
  String get supportBackToProfile;

  /// No description provided for @supportFaqTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get supportFaqTitle;

  /// No description provided for @supportCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get supportCopy;

  /// No description provided for @passwordUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Password'**
  String get passwordUpdateTitle;

  /// No description provided for @passwordSecureAccount.
  ///
  /// In en, this message translates to:
  /// **'Secure Your Account'**
  String get passwordSecureAccount;

  /// No description provided for @passwordEnterNew.
  ///
  /// In en, this message translates to:
  /// **'Please enter a new password below.'**
  String get passwordEnterNew;

  /// No description provided for @passwordNew.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get passwordNew;

  /// No description provided for @passwordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get passwordConfirm;

  /// No description provided for @passwordSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE PASSWORD'**
  String get passwordSave;

  /// No description provided for @passwordNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordNoMatch;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @passwordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully!'**
  String get passwordSuccess;

  /// No description provided for @workshopBeingAssigned.
  ///
  /// In en, this message translates to:
  /// **'Workshop Being Assigned'**
  String get workshopBeingAssigned;

  /// No description provided for @workshopAssignedDesc.
  ///
  /// In en, this message translates to:
  /// **'Our team is matching your repair job to the best available workshop. You\'ll be notified once a workshop is assigned.\n\nYou can proceed to complete your booking details below.'**
  String get workshopAssignedDesc;

  /// No description provided for @continueToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Continue to Checkout'**
  String get continueToCheckout;

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String updatedAt(String date);

  /// No description provided for @jobIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Job #{id}'**
  String jobIdLabel(String id);

  /// No description provided for @panelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} panel'**
  String panelCount(int count);

  /// No description provided for @profileAccountTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Account & Telemetry'**
  String get profileAccountTelemetry;

  /// No description provided for @profileGarageTitle.
  ///
  /// In en, this message translates to:
  /// **'My Digital Garage'**
  String get profileGarageTitle;

  /// No description provided for @profileGarageEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your garage is empty'**
  String get profileGarageEmpty;

  /// No description provided for @profileGarageEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Register your vehicle to start managing service history, track repairs, and unlock exclusive perks.'**
  String get profileGarageEmptyDesc;

  /// No description provided for @profileMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get profileMember;

  /// No description provided for @profileReviveMember.
  ///
  /// In en, this message translates to:
  /// **'REVIVE MEMBER'**
  String get profileReviveMember;

  /// No description provided for @profileMemberPerks.
  ///
  /// In en, this message translates to:
  /// **'Register vehicles to unlock workshop perks'**
  String get profileMemberPerks;

  /// No description provided for @profileSignedInGoogle.
  ///
  /// In en, this message translates to:
  /// **'Signed in with Google'**
  String get profileSignedInGoogle;

  /// No description provided for @profileJobHistory.
  ///
  /// In en, this message translates to:
  /// **'Job History & Certificates'**
  String get profileJobHistory;

  /// No description provided for @profileHistoryComing.
  ///
  /// In en, this message translates to:
  /// **'Full history coming soon'**
  String get profileHistoryComing;

  /// No description provided for @profileRegisterVehicle.
  ///
  /// In en, this message translates to:
  /// **'Register New Vehicle to Garage'**
  String get profileRegisterVehicle;

  /// No description provided for @profileTrackLive.
  ///
  /// In en, this message translates to:
  /// **'Track Live Repair'**
  String get profileTrackLive;

  /// No description provided for @profileBookService.
  ///
  /// In en, this message translates to:
  /// **'Book a Service'**
  String get profileBookService;

  /// No description provided for @profileTrackOrder.
  ///
  /// In en, this message translates to:
  /// **'Track Order'**
  String get profileTrackOrder;

  /// No description provided for @profileGuarantee.
  ///
  /// In en, this message translates to:
  /// **'Guarantee'**
  String get profileGuarantee;

  /// No description provided for @profileCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get profileCompleted;

  /// No description provided for @profileLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out of Revive ID'**
  String get profileLogOut;

  /// No description provided for @profileTelemetryVersion.
  ///
  /// In en, this message translates to:
  /// **'Revive Workshop Telemetry OS v4.2.1-JKT'**
  String get profileTelemetryVersion;

  /// No description provided for @profileSelectJob.
  ///
  /// In en, this message translates to:
  /// **'Select a job from your history to track it'**
  String get profileSelectJob;

  /// No description provided for @profileGarageLabel.
  ///
  /// In en, this message translates to:
  /// **'GARAGE PROFILE'**
  String get profileGarageLabel;

  /// No description provided for @partnerPortal.
  ///
  /// In en, this message translates to:
  /// **'Partner Portal'**
  String get partnerPortal;

  /// No description provided for @partnerWorkshopProfile.
  ///
  /// In en, this message translates to:
  /// **'My Workshop Profile'**
  String get partnerWorkshopProfile;

  /// No description provided for @partnerContactOps.
  ///
  /// In en, this message translates to:
  /// **'Contact & Operations'**
  String get partnerContactOps;

  /// No description provided for @partnerPerformanceKpis.
  ///
  /// In en, this message translates to:
  /// **'Performance KPIs'**
  String get partnerPerformanceKpis;

  /// No description provided for @partnerFacilityPhotos.
  ///
  /// In en, this message translates to:
  /// **'Facility Photos'**
  String get partnerFacilityPhotos;

  /// No description provided for @partnerNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No facility photos uploaded yet.'**
  String get partnerNoPhotos;

  /// No description provided for @partnerDocumentStatus.
  ///
  /// In en, this message translates to:
  /// **'Document Status'**
  String get partnerDocumentStatus;

  /// No description provided for @partnerPendingReview.
  ///
  /// In en, this message translates to:
  /// **'PENDING REVIEW'**
  String get partnerPendingReview;

  /// No description provided for @partnerJobBoard.
  ///
  /// In en, this message translates to:
  /// **'Workshop Job Board & Active Pipeline'**
  String get partnerJobBoard;

  /// No description provided for @partnerJobBoardSub.
  ///
  /// In en, this message translates to:
  /// **'Live repair pipeline — tap any card to advance the stage.'**
  String get partnerJobBoardSub;

  /// No description provided for @partnerOpsCore.
  ///
  /// In en, this message translates to:
  /// **'OPS CORE'**
  String get partnerOpsCore;

  /// No description provided for @partnerActiveHub.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE HUB'**
  String get partnerActiveHub;

  /// No description provided for @partnerWorkshopOps.
  ///
  /// In en, this message translates to:
  /// **'Workshop Operations'**
  String get partnerWorkshopOps;

  /// No description provided for @partnerSignedIn.
  ///
  /// In en, this message translates to:
  /// **'SIGNED IN'**
  String get partnerSignedIn;

  /// No description provided for @partnerAccount.
  ///
  /// In en, this message translates to:
  /// **'Partner Account'**
  String get partnerAccount;

  /// No description provided for @partnerWorkshopPartner.
  ///
  /// In en, this message translates to:
  /// **'Workshop Partner'**
  String get partnerWorkshopPartner;

  /// No description provided for @partnerNoJobsStage.
  ///
  /// In en, this message translates to:
  /// **'No jobs in this stage'**
  String get partnerNoJobsStage;

  /// No description provided for @partnerNoActiveJobs.
  ///
  /// In en, this message translates to:
  /// **'No Active Jobs'**
  String get partnerNoActiveJobs;

  /// No description provided for @partnerNoActiveJobsSub.
  ///
  /// In en, this message translates to:
  /// **'Jobs will appear here once a customer booking is assigned to your workshop.'**
  String get partnerNoActiveJobsSub;

  /// No description provided for @partnerPhotoBtn.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get partnerPhotoBtn;

  /// No description provided for @partnerNoJobsFound.
  ///
  /// In en, this message translates to:
  /// **'No Jobs Found'**
  String get partnerNoJobsFound;

  /// No description provided for @partnerNoJobsFoundSub.
  ///
  /// In en, this message translates to:
  /// **'Try changing your filter or search term.'**
  String get partnerNoJobsFoundSub;

  /// No description provided for @vehicleRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Register New Vehicle'**
  String get vehicleRegisterTitle;

  /// No description provided for @vehicleRegisterSub.
  ///
  /// In en, this message translates to:
  /// **'Add a vehicle to your digital garage'**
  String get vehicleRegisterSub;

  /// No description provided for @vehicleType.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Type'**
  String get vehicleType;

  /// No description provided for @vehicleInsured.
  ///
  /// In en, this message translates to:
  /// **'Vehicle is Insured'**
  String get vehicleInsured;

  /// No description provided for @vehicleRegistrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get vehicleRegistrationFailed;

  /// No description provided for @vehicleInsuredSub.
  ///
  /// In en, this message translates to:
  /// **'Enable to link an insurance provider'**
  String get vehicleInsuredSub;

  /// No description provided for @commlinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Commlink — Admin Hotline'**
  String get commlinkTitle;

  /// No description provided for @commlinkSub.
  ///
  /// In en, this message translates to:
  /// **'Secure channel with Revive Ops Core admin team'**
  String get commlinkSub;

  /// No description provided for @commlinkAdminOnline.
  ///
  /// In en, this message translates to:
  /// **'ADMIN ONLINE'**
  String get commlinkAdminOnline;

  /// No description provided for @commlinkReviveAdmin.
  ///
  /// In en, this message translates to:
  /// **'Revive Admin'**
  String get commlinkReviveAdmin;

  /// No description provided for @commlinkNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get commlinkNoMessages;

  /// No description provided for @commlinkNoMessagesSub.
  ///
  /// In en, this message translates to:
  /// **'Send a message to the Revive Ops admin team.\nThey typically respond within 1 business hour.'**
  String get commlinkNoMessagesSub;

  /// No description provided for @estimatorSelectPanels.
  ///
  /// In en, this message translates to:
  /// **'Please capture an image and select panels before continuing.'**
  String get estimatorSelectPanels;

  /// No description provided for @estimatorLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Please log in or create an account to secure your booking.'**
  String get estimatorLoginRequired;

  /// No description provided for @estimatorBookingError.
  ///
  /// In en, this message translates to:
  /// **'Error securing booking'**
  String get estimatorBookingError;

  /// No description provided for @estimatorIntakeImagery.
  ///
  /// In en, this message translates to:
  /// **'INTAKE IMAGERY'**
  String get estimatorIntakeImagery;

  /// No description provided for @estimatorAiVerified.
  ///
  /// In en, this message translates to:
  /// **'AI Verified'**
  String get estimatorAiVerified;

  /// No description provided for @estimatorCaptureDamage.
  ///
  /// In en, this message translates to:
  /// **'Capture Damage Photo'**
  String get estimatorCaptureDamage;

  /// No description provided for @estimatorAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get estimatorAddPhoto;

  /// No description provided for @estimatorFromGallery.
  ///
  /// In en, this message translates to:
  /// **'From Gallery'**
  String get estimatorFromGallery;

  /// No description provided for @estimatorMaxReached.
  ///
  /// In en, this message translates to:
  /// **'5 photos uploaded — maximum reached'**
  String get estimatorMaxReached;

  /// No description provided for @estimatorDigitalTwin.
  ///
  /// In en, this message translates to:
  /// **'Digital Twin Analysis'**
  String get estimatorDigitalTwin;

  /// No description provided for @estimatorTapPanels.
  ///
  /// In en, this message translates to:
  /// **'Tap to select affected panels'**
  String get estimatorTapPanels;

  /// No description provided for @estimatorLiveTwin.
  ///
  /// In en, this message translates to:
  /// **'Live Twin'**
  String get estimatorLiveTwin;

  /// No description provided for @estimatorAssessmentReport.
  ///
  /// In en, this message translates to:
  /// **'Damage Assessment Report'**
  String get estimatorAssessmentReport;

  /// No description provided for @estimatorTriageMatrix.
  ///
  /// In en, this message translates to:
  /// **'Computer Vision Triage Matrix'**
  String get estimatorTriageMatrix;

  /// No description provided for @estimatorAssessmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Assessment:'**
  String get estimatorAssessmentLabel;

  /// No description provided for @estimatorObservation.
  ///
  /// In en, this message translates to:
  /// **'Observasi: '**
  String get estimatorObservation;

  /// No description provided for @estimatorTotalEstimation.
  ///
  /// In en, this message translates to:
  /// **'TOTAL ESTIMATION'**
  String get estimatorTotalEstimation;

  /// No description provided for @estimatorIncludesCoat.
  ///
  /// In en, this message translates to:
  /// **'Includes Color Matching & Clear Coat'**
  String get estimatorIncludesCoat;

  /// No description provided for @estimatorNoAiData.
  ///
  /// In en, this message translates to:
  /// **'No AI damage data available.'**
  String get estimatorNoAiData;

  /// No description provided for @estimatorEstimatedTotal.
  ///
  /// In en, this message translates to:
  /// **'ESTIMATED TOTAL'**
  String get estimatorEstimatedTotal;

  /// Platform tagline on login screen
  ///
  /// In en, this message translates to:
  /// **'Integrated Automotive Digital Platform'**
  String get loginPlatformTagline;

  /// No description provided for @loginHeadingLogin.
  ///
  /// In en, this message translates to:
  /// **'Secure Login'**
  String get loginHeadingLogin;

  /// No description provided for @loginHeadingRegister.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get loginHeadingRegister;

  /// No description provided for @loginEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get loginEmailLabel;

  /// No description provided for @loginPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// No description provided for @loginSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'SEND RESET LINK'**
  String get loginSendResetLink;

  /// No description provided for @loginRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'REGISTER'**
  String get loginRegisterButton;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'LOGIN'**
  String get loginButton;

  /// No description provided for @loginForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get loginForgotPassword;

  /// No description provided for @loginSwitchToLogin.
  ///
  /// In en, this message translates to:
  /// **'Login instead'**
  String get loginSwitchToLogin;

  /// No description provided for @loginSwitchToRegister.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get loginSwitchToRegister;

  /// No description provided for @loginBackToLogin.
  ///
  /// In en, this message translates to:
  /// **'Back to Login'**
  String get loginBackToLogin;

  /// No description provided for @loginOr.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get loginOr;

  /// No description provided for @loginContinueGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get loginContinueGoogle;

  /// No description provided for @loginRegistrationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration successful! Please check your email to verify your account before logging in.'**
  String get loginRegistrationSuccess;

  /// No description provided for @loginResetSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent! Check your email to securely reset your password.'**
  String get loginResetSent;

  /// No description provided for @loginAuthenticating.
  ///
  /// In en, this message translates to:
  /// **'Authenticating...'**
  String get loginAuthenticating;

  /// No description provided for @error404Title.
  ///
  /// In en, this message translates to:
  /// **'404 - SECTOR NOT FOUND'**
  String get error404Title;

  /// No description provided for @error404ReturnButton.
  ///
  /// In en, this message translates to:
  /// **'RETURN TO BASE'**
  String get error404ReturnButton;

  /// No description provided for @navAdminCentral.
  ///
  /// In en, this message translates to:
  /// **'Admin Central'**
  String get navAdminCentral;

  /// No description provided for @navPartnerDashboard.
  ///
  /// In en, this message translates to:
  /// **'Partner Dashboard'**
  String get navPartnerDashboard;

  /// No description provided for @navMyProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get navMyProfile;

  /// No description provided for @navLanguageAppearance.
  ///
  /// In en, this message translates to:
  /// **'Language & Appearance'**
  String get navLanguageAppearance;

  /// No description provided for @navLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get navLogOut;

  /// No description provided for @partnerRegBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Partner Onboarding'**
  String get partnerRegBreadcrumb;

  /// No description provided for @partnerRegTitle.
  ///
  /// In en, this message translates to:
  /// **'Workshop Partner Registration'**
  String get partnerRegTitle;

  /// No description provided for @partnerRegSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join Revive\'s AI-driven collision repair network'**
  String get partnerRegSubtitle;

  /// No description provided for @partnerRegStep1.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get partnerRegStep1;

  /// No description provided for @partnerRegStep1Sub.
  ///
  /// In en, this message translates to:
  /// **'Legal entity, contact, and tier'**
  String get partnerRegStep1Sub;

  /// No description provided for @partnerRegStep2.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get partnerRegStep2;

  /// No description provided for @partnerRegStep2Sub.
  ///
  /// In en, this message translates to:
  /// **'Facility audit photos — 4 slots'**
  String get partnerRegStep2Sub;

  /// No description provided for @partnerRegStep3.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get partnerRegStep3;

  /// No description provided for @partnerRegStep3Sub.
  ///
  /// In en, this message translates to:
  /// **'Legal & tax documents — encrypted'**
  String get partnerRegStep3Sub;

  /// No description provided for @partnerRegStep4.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get partnerRegStep4;

  /// No description provided for @partnerRegStep4Sub.
  ///
  /// In en, this message translates to:
  /// **'Workshop coordinates and service radius'**
  String get partnerRegStep4Sub;

  /// No description provided for @partnerRegStep5.
  ///
  /// In en, this message translates to:
  /// **'Bank & Sign'**
  String get partnerRegStep5;

  /// No description provided for @partnerRegStep5Sub.
  ///
  /// In en, this message translates to:
  /// **'Payout account and consent'**
  String get partnerRegStep5Sub;

  /// No description provided for @partnerRegEntityName.
  ///
  /// In en, this message translates to:
  /// **'Legal Entity Name (PT / CV / Firma)'**
  String get partnerRegEntityName;

  /// No description provided for @partnerRegBrandName.
  ///
  /// In en, this message translates to:
  /// **'Trade / Workshop Brand Name'**
  String get partnerRegBrandName;

  /// No description provided for @partnerRegPic.
  ///
  /// In en, this message translates to:
  /// **'PIC / Workshop General Manager'**
  String get partnerRegPic;

  /// No description provided for @partnerRegLegalAddress.
  ///
  /// In en, this message translates to:
  /// **'Legal Business Address'**
  String get partnerRegLegalAddress;

  /// No description provided for @partnerRegEmail.
  ///
  /// In en, this message translates to:
  /// **'Official Business Email'**
  String get partnerRegEmail;

  /// No description provided for @partnerRegEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get partnerRegEmailRequired;

  /// No description provided for @partnerRegEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get partnerRegEmailInvalid;

  /// No description provided for @partnerRegEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification link sent — check your inbox and click the link.'**
  String get partnerRegEmailSent;

  /// No description provided for @partnerRegPhone.
  ///
  /// In en, this message translates to:
  /// **'Direct WhatsApp Number'**
  String get partnerRegPhone;

  /// No description provided for @partnerRegPhoneVerified.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp number verified'**
  String get partnerRegPhoneVerified;

  /// No description provided for @partnerRegTier.
  ///
  /// In en, this message translates to:
  /// **'Operational Tier'**
  String get partnerRegTier;

  /// No description provided for @partnerRegPaint.
  ///
  /// In en, this message translates to:
  /// **'Certified Paint Brand'**
  String get partnerRegPaint;

  /// No description provided for @partnerTier1Name.
  ///
  /// In en, this message translates to:
  /// **'Flagship Spray Facility'**
  String get partnerTier1Name;

  /// No description provided for @partnerTier1Desc.
  ///
  /// In en, this message translates to:
  /// **'Down-draft booth, dry sanding'**
  String get partnerTier1Desc;

  /// No description provided for @partnerTier2Name.
  ///
  /// In en, this message translates to:
  /// **'Authorized Partner'**
  String get partnerTier2Name;

  /// No description provided for @partnerTier2Desc.
  ///
  /// In en, this message translates to:
  /// **'Standard booth, OEM refinish specs'**
  String get partnerTier2Desc;

  /// No description provided for @partnerTier3Name.
  ///
  /// In en, this message translates to:
  /// **'Express PDR Center'**
  String get partnerTier3Name;

  /// No description provided for @partnerTier3Desc.
  ///
  /// In en, this message translates to:
  /// **'Paintless dent & spot repair'**
  String get partnerTier3Desc;

  /// No description provided for @partnerRegSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get partnerRegSendOtp;

  /// No description provided for @partnerRegVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get partnerRegVerify;

  /// No description provided for @partnerRegVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified ✓'**
  String get partnerRegVerified;

  /// No description provided for @partnerRegOtpCode.
  ///
  /// In en, this message translates to:
  /// **'Enter 6-digit OTP'**
  String get partnerRegOtpCode;

  /// No description provided for @partnerRegPhotosUploaded.
  ///
  /// In en, this message translates to:
  /// **'photos uploaded'**
  String get partnerRegPhotosUploaded;

  /// No description provided for @partnerRegPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'At least 1 photo required. Max 4. Shows workshop condition to Revive reviewers.'**
  String get partnerRegPhotosHint;

  /// No description provided for @partnerRegDocNib.
  ///
  /// In en, this message translates to:
  /// **'Nomor Induk Berusaha'**
  String get partnerRegDocNib;

  /// No description provided for @partnerRegDocNpwp.
  ///
  /// In en, this message translates to:
  /// **'NPWP Badan Usaha Perusahaan'**
  String get partnerRegDocNpwp;

  /// No description provided for @partnerRegDocSiup.
  ///
  /// In en, this message translates to:
  /// **'Izin Operasional Bengkel (SIUP)'**
  String get partnerRegDocSiup;

  /// No description provided for @partnerRegDocKtp.
  ///
  /// In en, this message translates to:
  /// **'KTP Direktur / Penanggung Jawab Teknis'**
  String get partnerRegDocKtp;

  /// No description provided for @partnerRegDocEncrypted.
  ///
  /// In en, this message translates to:
  /// **'All documents are encrypted and only accessible to Revive\'s verification team.'**
  String get partnerRegDocEncrypted;

  /// No description provided for @partnerRegSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get partnerRegSelectFile;

  /// No description provided for @partnerRegReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get partnerRegReplace;

  /// No description provided for @partnerRegSameAsLegal.
  ///
  /// In en, this message translates to:
  /// **'Workshop address same as legal address'**
  String get partnerRegSameAsLegal;

  /// No description provided for @partnerRegWorkshopAddress.
  ///
  /// In en, this message translates to:
  /// **'Workshop Physical Address'**
  String get partnerRegWorkshopAddress;

  /// No description provided for @partnerRegMapPin.
  ///
  /// In en, this message translates to:
  /// **'Workshop Map Pin'**
  String get partnerRegMapPin;

  /// No description provided for @partnerRegLocateMe.
  ///
  /// In en, this message translates to:
  /// **'Use GPS'**
  String get partnerRegLocateMe;

  /// No description provided for @partnerRegMapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to set pin, or use GPS button above.'**
  String get partnerRegMapHint;

  /// No description provided for @partnerRegRadius.
  ///
  /// In en, this message translates to:
  /// **'Towing & Pick-up Service Radius'**
  String get partnerRegRadius;

  /// No description provided for @partnerRegBankName.
  ///
  /// In en, this message translates to:
  /// **'Bank Name'**
  String get partnerRegBankName;

  /// No description provided for @partnerRegBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Account Number'**
  String get partnerRegBankAccount;

  /// No description provided for @partnerRegBankHolder.
  ///
  /// In en, this message translates to:
  /// **'Account Holder Name'**
  String get partnerRegBankHolder;

  /// No description provided for @partnerRegConsent.
  ///
  /// In en, this message translates to:
  /// **'I certify under Indonesian Commercial Law (UU PT & Perbengkelan) that all submitted information is authentic and conforms to the Revive Collision Network Operating SLA.'**
  String get partnerRegConsent;

  /// No description provided for @partnerRegSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Application'**
  String get partnerRegSubmit;

  /// No description provided for @partnerRegSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get partnerRegSubmitting;

  /// No description provided for @partnerRegSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed'**
  String get partnerRegSubmitFailed;

  /// No description provided for @partnerRegBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get partnerRegBack;

  /// No description provided for @partnerRegNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get partnerRegNext;

  /// No description provided for @partnerRegSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Application Submitted'**
  String get partnerRegSuccessTitle;

  /// No description provided for @partnerRegSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Your application has been sent to the Revive verification team. You will be notified via WhatsApp and email on the outcome.'**
  String get partnerRegSuccessBody;

  /// No description provided for @partnerRegSuccessPhotos.
  ///
  /// In en, this message translates to:
  /// **'facility photos'**
  String get partnerRegSuccessPhotos;

  /// No description provided for @partnerRegSuccessDocs.
  ///
  /// In en, this message translates to:
  /// **'legal documents'**
  String get partnerRegSuccessDocs;

  /// No description provided for @partnerRegGoHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get partnerRegGoHome;

  /// No description provided for @partnerNotifApproved.
  ///
  /// In en, this message translates to:
  /// **'Selamat! Pendaftaran bengkel Anda disetujui. Login menggunakan email ini.'**
  String get partnerNotifApproved;

  /// No description provided for @partnerNotifRejected.
  ///
  /// In en, this message translates to:
  /// **'Pendaftaran bengkel Anda ditolak.'**
  String get partnerNotifRejected;

  /// No description provided for @partnerNotifRevision.
  ///
  /// In en, this message translates to:
  /// **'Pendaftaran Anda memerlukan perbaikan.'**
  String get partnerNotifRevision;
}

class _AppLDelegate extends LocalizationsDelegate<AppL> {
  const _AppLDelegate();

  @override
  Future<AppL> load(Locale locale) {
    return SynchronousFuture<AppL>(lookupAppL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLDelegate old) => false;
}

AppL lookupAppL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLEn();
    case 'id':
      return AppLId();
  }

  throw FlutterError(
      'AppL.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
