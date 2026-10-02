/*
 * @Description: 自动生成的本地化文件
 * @Author: LILYGO_L
 * @Date: 2025-10-27 11:20:43
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 * @Generated: flutter gen-l10n
 * @Note: 请勿手动编辑，翻译内容请在 lib/l10n 目录下的 .arb 文件中修改。
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose your current theme'**
  String get themeDescription;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @basic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get basic;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @application.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get application;

  /// No description provided for @languageAndRegion.
  ///
  /// In en, this message translates to:
  /// **'Language And Region'**
  String get languageAndRegion;

  /// No description provided for @personalization.
  ///
  /// In en, this message translates to:
  /// **'Personalization'**
  String get personalization;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @copyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get copyright;

  /// No description provided for @allRightsReserved.
  ///
  /// In en, this message translates to:
  /// **'. All rights reserved.'**
  String get allRightsReserved;

  /// No description provided for @addDevice.
  ///
  /// In en, this message translates to:
  /// **'Add Device'**
  String get addDevice;

  /// No description provided for @addDeviceDescription.
  ///
  /// In en, this message translates to:
  /// **'You can add development devices here, please select the method to add a development device'**
  String get addDeviceDescription;

  /// No description provided for @addByDeviceType.
  ///
  /// In en, this message translates to:
  /// **'Add by device type'**
  String get addByDeviceType;

  /// No description provided for @selectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select Device'**
  String get selectDevice;

  /// No description provided for @selectDeviceDescription.
  ///
  /// In en, this message translates to:
  /// **'Click below to select the device you want to add'**
  String get selectDeviceDescription;

  /// No description provided for @searchForDeviceModel.
  ///
  /// In en, this message translates to:
  /// **'Search for device model'**
  String get searchForDeviceModel;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @homePageContentStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to LilygoBox'**
  String get homePageContentStartTitle;

  /// No description provided for @homePageContentStartDescription.
  ///
  /// In en, this message translates to:
  /// **'LilygoBox is an integrated development and control center built specifically for Lilygo hardware.'**
  String get homePageContentStartDescription;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose your preferred application interface language'**
  String get languageDescription;

  /// No description provided for @deviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Device Settings'**
  String get deviceSettings;

  /// No description provided for @deviceSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Settings are not available for this device yet.'**
  String get deviceSettingsUnavailable;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @resetThisSetting.
  ///
  /// In en, this message translates to:
  /// **'Reset this setting'**
  String get resetThisSetting;

  /// No description provided for @controlCenter.
  ///
  /// In en, this message translates to:
  /// **'Control Center'**
  String get controlCenter;

  /// No description provided for @sidebarHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get sidebarHome;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @notSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notSignedIn;

  /// No description provided for @accountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Accounts are not available yet. You can still use local device features.'**
  String get accountUnavailable;

  /// No description provided for @showSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show sidebar'**
  String get showSidebar;

  /// No description provided for @hideSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide sidebar'**
  String get hideSidebar;

  /// No description provided for @homeDevicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your LILYGO devices, all in one place'**
  String get homeDevicesSubtitle;

  /// No description provided for @homeDevicesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No devices yet'**
  String get homeDevicesEmpty;

  /// No description provided for @homeDevicesEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Add your first device\nand bring it into LilygoBox.'**
  String get homeDevicesEmptyDescription;

  /// No description provided for @homeDevicesReady.
  ///
  /// In en, this message translates to:
  /// **'Your devices are ready'**
  String get homeDevicesReady;

  /// No description provided for @homeDevicesReadyDescription.
  ///
  /// In en, this message translates to:
  /// **'Open a device from the sidebar,\nor add another device.'**
  String get homeDevicesReadyDescription;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @connectYourDevice.
  ///
  /// In en, this message translates to:
  /// **'Connect your device'**
  String get connectYourDevice;

  /// No description provided for @discoveryDescription.
  ///
  /// In en, this message translates to:
  /// **'Turn on your device. LilygoBox will find available devices automatically.'**
  String get discoveryDescription;

  /// No description provided for @discoveredDevices.
  ///
  /// In en, this message translates to:
  /// **'Discovered devices'**
  String get discoveredDevices;

  /// No description provided for @searchingDevices.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices…'**
  String get searchingDevices;

  /// No description provided for @discoveryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get discoveryEmpty;

  /// No description provided for @discoveryEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Make sure your device is on and ready to connect.'**
  String get discoveryEmptyDescription;

  /// No description provided for @discoveryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device discovery unavailable'**
  String get discoveryUnavailable;

  /// No description provided for @discoveryUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'Device connections are not available in this version yet.'**
  String get discoveryUnavailableDescription;

  /// No description provided for @discoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to find devices'**
  String get discoveryFailed;

  /// No description provided for @discoveryFailedDescription.
  ///
  /// In en, this message translates to:
  /// **'Check your device and access permissions, then try again.'**
  String get discoveryFailedDescription;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @deviceConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to your device…'**
  String get deviceConnecting;

  /// No description provided for @keepDeviceOn.
  ///
  /// In en, this message translates to:
  /// **'Keep your device turned on'**
  String get keepDeviceOn;

  /// No description provided for @deviceConnected.
  ///
  /// In en, this message translates to:
  /// **'Device connected'**
  String get deviceConnected;

  /// No description provided for @deviceConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get deviceConnectionFailed;

  /// No description provided for @deviceConnectionFailedDescription.
  ///
  /// In en, this message translates to:
  /// **'Make sure your device is still on and ready to connect, then try again.'**
  String get deviceConnectionFailedDescription;

  /// No description provided for @retryConnection.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryConnection;

  /// No description provided for @cancelConnection.
  ///
  /// In en, this message translates to:
  /// **'Cancel connection'**
  String get cancelConnection;

  /// No description provided for @openDevice.
  ///
  /// In en, this message translates to:
  /// **'Open device'**
  String get openDevice;

  /// No description provided for @deviceConnectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Connection help'**
  String get deviceConnectionHelp;

  /// No description provided for @deviceConnectionHelpDescription.
  ///
  /// In en, this message translates to:
  /// **'Make sure your device is on and ready to connect.\nFollow any permission or confirmation prompts on your devices.'**
  String get deviceConnectionHelpDescription;

  /// No description provided for @tapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Select to connect'**
  String get tapToConnect;

  /// No description provided for @statePreview.
  ///
  /// In en, this message translates to:
  /// **'State preview'**
  String get statePreview;

  /// No description provided for @exitStatePreview.
  ///
  /// In en, this message translates to:
  /// **'Exit preview'**
  String get exitStatePreview;

  /// No description provided for @statePreviewActive.
  ///
  /// In en, this message translates to:
  /// **'Preview mode · Simulated data'**
  String get statePreviewActive;

  /// No description provided for @statePreviewNoDevice.
  ///
  /// In en, this message translates to:
  /// **'This preview does not add devices or open a real device page.'**
  String get statePreviewNoDevice;

  /// No description provided for @resizeSettingsSidebar.
  ///
  /// In en, this message translates to:
  /// **'Resize settings sidebar'**
  String get resizeSettingsSidebar;

  /// No description provided for @appearanceSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Customize the interface with your preferred theme.'**
  String get appearanceSettingsDescription;

  /// No description provided for @languageSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the display language for LilygoBox.'**
  String get languageSettingsDescription;

  /// No description provided for @generalSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage application preferences and defaults.'**
  String get generalSettingsDescription;

  /// No description provided for @aboutSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Application information and version.'**
  String get aboutSettingsDescription;

  /// No description provided for @restoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get restoreDefaults;

  /// No description provided for @restoreDefaultsDescription.
  ///
  /// In en, this message translates to:
  /// **'Reset application preferences while keeping your account and added devices.'**
  String get restoreDefaultsDescription;

  /// No description provided for @restoreDefaultsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore default settings?'**
  String get restoreDefaultsConfirmTitle;

  /// No description provided for @restoreDefaultsConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'The theme will reset to Dark and the language to English. Your account and added devices will be kept.'**
  String get restoreDefaultsConfirmDescription;

  /// No description provided for @settingsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancel;

  /// No description provided for @profileDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage your personal profile.'**
  String get profileDescription;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;
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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
