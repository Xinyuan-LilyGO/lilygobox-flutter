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

  /// No description provided for @homeDeviceCardLabel.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get homeDeviceCardLabel;

  /// No description provided for @deviceBatteryPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery status'**
  String get deviceBatteryPageTitle;

  /// No description provided for @deviceDetails.
  ///
  /// In en, this message translates to:
  /// **'Device overview'**
  String get deviceDetails;

  /// No description provided for @deviceControlTab.
  ///
  /// In en, this message translates to:
  /// **'Device controls'**
  String get deviceControlTab;

  /// No description provided for @deviceConnectionTab.
  ///
  /// In en, this message translates to:
  /// **'Device connection'**
  String get deviceConnectionTab;

  /// No description provided for @deviceInfoTab.
  ///
  /// In en, this message translates to:
  /// **'Device information'**
  String get deviceInfoTab;

  /// No description provided for @deviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceNameLabel;

  /// No description provided for @deviceScreenControls.
  ///
  /// In en, this message translates to:
  /// **'Screen controls'**
  String get deviceScreenControls;

  /// No description provided for @deviceScreenDisplay.
  ///
  /// In en, this message translates to:
  /// **'Screen display'**
  String get deviceScreenDisplay;

  /// No description provided for @deviceBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get deviceBrightness;

  /// No description provided for @deviceSound.
  ///
  /// In en, this message translates to:
  /// **'Device sounds'**
  String get deviceSound;

  /// No description provided for @deviceDisplaySettings.
  ///
  /// In en, this message translates to:
  /// **'Display settings'**
  String get deviceDisplaySettings;

  /// No description provided for @deviceControlUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not supported yet'**
  String get deviceControlUnavailable;

  /// No description provided for @deviceControlsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'These controls are not available for this device yet.'**
  String get deviceControlsUnavailable;

  /// No description provided for @deviceConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get deviceConnectionStatus;

  /// No description provided for @deviceConnectionMethod.
  ///
  /// In en, this message translates to:
  /// **'Connection method'**
  String get deviceConnectionMethod;

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

  /// No description provided for @minimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimizeWindow;

  /// No description provided for @maximizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximizeWindow;

  /// No description provided for @restoreWindow.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreWindow;

  /// No description provided for @closeWindow.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeWindow;

  /// No description provided for @closeSettings.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get closeSettings;

  /// No description provided for @decreaseValue.
  ///
  /// In en, this message translates to:
  /// **'Decrease value'**
  String get decreaseValue;

  /// No description provided for @increaseValue.
  ///
  /// In en, this message translates to:
  /// **'Increase value'**
  String get increaseValue;

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

  /// No description provided for @homeDeviceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search by name or model'**
  String get homeDeviceSearch;

  /// No description provided for @homeClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get homeClearSearch;

  /// No description provided for @homeDeviceOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get homeDeviceOnline;

  /// No description provided for @homeDeviceOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get homeDeviceOffline;

  /// No description provided for @homeDeviceConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get homeDeviceConnecting;

  /// No description provided for @homeDevicesNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching devices'**
  String get homeDevicesNoResults;

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
  /// **'Make sure your device is powered on and allows LilygoBox connections, then select the device to connect.'**
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

  /// No description provided for @deleteDevice.
  ///
  /// In en, this message translates to:
  /// **'Delete device'**
  String get deleteDevice;

  /// No description provided for @deleteDeviceConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete device?'**
  String get deleteDeviceConfirmTitle;

  /// No description provided for @deleteDeviceConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'This will disconnect from “{deviceName}” and remove its settings and pairing information from this computer. Adding it again will require new approval.'**
  String deleteDeviceConfirmDescription(String deviceName);

  /// No description provided for @deleteDeviceSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Device deleted.'**
  String get deleteDeviceSucceeded;

  /// No description provided for @deleteDeviceFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete this device. Please try again.'**
  String get deleteDeviceFailed;

  /// No description provided for @discoveryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get discoveryEmpty;

  /// No description provided for @discoveryEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Make sure your device is powered on and allows app connections.\nFor local network connections, make sure both devices are on the same network.'**
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
  /// **'The search could not finish. Check your network connection and network access permissions, then try again.'**
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

  /// No description provided for @lanConnectingDescription.
  ///
  /// In en, this message translates to:
  /// **'Establishing the connection. Please wait.'**
  String get lanConnectingDescription;

  /// No description provided for @deviceConnected.
  ///
  /// In en, this message translates to:
  /// **'Device connected'**
  String get deviceConnected;

  /// No description provided for @deviceConnectionComplete.
  ///
  /// In en, this message translates to:
  /// **'Connection complete'**
  String get deviceConnectionComplete;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @deviceConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get deviceConnectionFailed;

  /// No description provided for @deviceConnectionFailedDescription.
  ///
  /// In en, this message translates to:
  /// **'Could not establish a connection. Make sure the device is online and allows LilygoBox connections, then try again.'**
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

  /// No description provided for @deviceConnectionTroubleshooting.
  ///
  /// In en, this message translates to:
  /// **'Troubleshoot connection'**
  String get deviceConnectionTroubleshooting;

  /// No description provided for @closeHelp.
  ///
  /// In en, this message translates to:
  /// **'Close help'**
  String get closeHelp;

  /// No description provided for @deviceHelpPreparation.
  ///
  /// In en, this message translates to:
  /// **'Prepare your device'**
  String get deviceHelpPreparation;

  /// No description provided for @deviceHelpPreparationDescription.
  ///
  /// In en, this message translates to:
  /// **'Make sure your device is powered on and allows LilygoBox connections. Refer to the instructions for your device.'**
  String get deviceHelpPreparationDescription;

  /// No description provided for @deviceHelpNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check the network'**
  String get deviceHelpNetwork;

  /// No description provided for @deviceHelpNetworkDescription.
  ///
  /// In en, this message translates to:
  /// **'For local network connections, connect your computer or phone and the device to the same network. If the device is still not found, check firewall permissions for the app and whether your router blocks communication between devices.'**
  String get deviceHelpNetworkDescription;

  /// No description provided for @deviceHelpApproval.
  ///
  /// In en, this message translates to:
  /// **'Approve the connection'**
  String get deviceHelpApproval;

  /// No description provided for @deviceHelpApprovalDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow the device prompts to approve the first connection. Previously authorized devices usually do not require confirmation again. Adding a deleted device requires new approval.'**
  String get deviceHelpApprovalDescription;

  /// No description provided for @tapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Select to connect'**
  String get tapToConnect;

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
  /// **'The theme will reset to Dark, the language to English, and sidebar layouts to their defaults. Your account and added devices will be kept.'**
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

  /// No description provided for @githubSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with GitHub'**
  String get githubSignIn;

  /// No description provided for @githubAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Link your public GitHub profile. Devices and app settings stay on this device.'**
  String get githubAccountDescription;

  /// No description provided for @githubRequesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting an authorization code…'**
  String get githubRequesting;

  /// No description provided for @githubRestoring.
  ///
  /// In en, this message translates to:
  /// **'Checking your session…'**
  String get githubRestoring;

  /// No description provided for @githubCompleting.
  ///
  /// In en, this message translates to:
  /// **'Finishing sign-in…'**
  String get githubCompleting;

  /// No description provided for @githubSigningOut.
  ///
  /// In en, this message translates to:
  /// **'Signing out…'**
  String get githubSigningOut;

  /// No description provided for @githubCodeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Copy the code below, enter it on GitHub, and approve access. Then return to the app.'**
  String get githubCodeInstructions;

  /// No description provided for @githubWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GitHub authorization…'**
  String get githubWaiting;

  /// No description provided for @githubCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get githubCopyCode;

  /// No description provided for @githubCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get githubCodeCopied;

  /// No description provided for @githubOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open GitHub authorization'**
  String get githubOpenBrowser;

  /// No description provided for @githubSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get githubSignOut;

  /// No description provided for @githubSignOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get githubSignOutConfirmTitle;

  /// No description provided for @githubSignOutDescription.
  ///
  /// In en, this message translates to:
  /// **'Signing out removes the saved session on this device. Your GitHub account and local devices are kept. Revoke app access in GitHub authorized application settings.'**
  String get githubSignOutDescription;

  /// No description provided for @githubNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'GitHub sign-in is not configured yet. Local device features are available.'**
  String get githubNotConfigured;

  /// No description provided for @githubUnsupported.
  ///
  /// In en, this message translates to:
  /// **'GitHub sign-in is not available on this platform yet.'**
  String get githubUnsupported;

  /// No description provided for @githubNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect to GitHub. Check your connection and try again.'**
  String get githubNetworkError;

  /// No description provided for @githubDenied.
  ///
  /// In en, this message translates to:
  /// **'Authorization was declined. You can start sign-in again.'**
  String get githubDenied;

  /// No description provided for @githubExpired.
  ///
  /// In en, this message translates to:
  /// **'The authorization code or session has expired. Please sign in again.'**
  String get githubExpired;

  /// No description provided for @githubConfigurationError.
  ///
  /// In en, this message translates to:
  /// **'GitHub sign-in is misconfigured. Please contact the app maintainer.'**
  String get githubConfigurationError;

  /// No description provided for @githubRateLimited.
  ///
  /// In en, this message translates to:
  /// **'GitHub has limited requests. Please try again later.'**
  String get githubRateLimited;

  /// No description provided for @githubInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'Could not complete GitHub authorization. Please try again later.'**
  String get githubInvalidResponse;

  /// No description provided for @githubStorageError.
  ///
  /// In en, this message translates to:
  /// **'Cannot access secure storage. Check system permissions and try again.'**
  String get githubStorageError;

  /// No description provided for @githubBrowserError.
  ///
  /// In en, this message translates to:
  /// **'Cannot open the browser. Visit https://github.com/login/device and enter the code above.'**
  String get githubBrowserError;

  /// No description provided for @githubRetryRestore.
  ///
  /// In en, this message translates to:
  /// **'Retry session verification'**
  String get githubRetryRestore;

  /// No description provided for @githubRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get githubRetry;

  /// No description provided for @preferencesReadError.
  ///
  /// In en, this message translates to:
  /// **'Local settings could not be read. Defaults are in use and the original settings have not been overwritten. Check folder permissions and retry.'**
  String get preferencesReadError;

  /// No description provided for @preferencesWriteError.
  ///
  /// In en, this message translates to:
  /// **'Local settings could not be saved. Changes may be lost after restarting. Check disk space and folder permissions, then retry.'**
  String get preferencesWriteError;

  /// No description provided for @preferencesRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get preferencesRetry;

  /// No description provided for @preferencesExitWithoutSaving.
  ///
  /// In en, this message translates to:
  /// **'Exit without saving'**
  String get preferencesExitWithoutSaving;

  /// No description provided for @trayShowWindow.
  ///
  /// In en, this message translates to:
  /// **'Show window'**
  String get trayShowWindow;

  /// No description provided for @trayExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get trayExit;

  /// No description provided for @lanOffline.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get lanOffline;

  /// No description provided for @lanModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get lanModel;

  /// No description provided for @lanModelVersion.
  ///
  /// In en, this message translates to:
  /// **'Model version'**
  String get lanModelVersion;

  /// No description provided for @lanMacAddress.
  ///
  /// In en, this message translates to:
  /// **'MAC address'**
  String get lanMacAddress;

  /// No description provided for @lanIdentityChanged.
  ///
  /// In en, this message translates to:
  /// **'The device identity has changed. Connection stopped. If you reset this device, pair it again.'**
  String get lanIdentityChanged;

  /// No description provided for @lanRepair.
  ///
  /// In en, this message translates to:
  /// **'Pair again'**
  String get lanRepair;

  /// No description provided for @lanRepairDescription.
  ///
  /// In en, this message translates to:
  /// **'Continue only if you reset this device. This clears its local pairing information. You will need to approve the connection on the device again.'**
  String get lanRepairDescription;

  /// No description provided for @lanDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get lanDeviceId;

  /// No description provided for @lanAddress.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get lanAddress;

  /// No description provided for @lanFirmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get lanFirmware;

  /// No description provided for @lanUptime.
  ///
  /// In en, this message translates to:
  /// **'Device uptime'**
  String get lanUptime;

  /// No description provided for @lanDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get lanDisconnect;

  /// No description provided for @lanDisconnectConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect device?'**
  String get lanDisconnectConfirmTitle;

  /// No description provided for @lanDisconnectDescription.
  ///
  /// In en, this message translates to:
  /// **'Your pairing information will be kept. Automatic connection will pause for this session. You can reconnect manually or restart the app to resume automatic connection.'**
  String get lanDisconnectDescription;

  /// No description provided for @lanConnectedDescription.
  ///
  /// In en, this message translates to:
  /// **'Connected to the device. Device information is refreshed automatically.'**
  String get lanConnectedDescription;

  /// No description provided for @lanConfirmOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Please allow the connection on your device.'**
  String get lanConfirmOnDevice;

  /// No description provided for @lanReconnectDescription.
  ///
  /// In en, this message translates to:
  /// **'Make sure your device is online and allows LilygoBox connections, then try again. If you still cannot connect, search for the device again.'**
  String get lanReconnectDescription;

  /// No description provided for @deviceDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Screen, sound and device connection'**
  String get deviceDashboardSubtitle;

  /// No description provided for @deviceDashboardMyDevice.
  ///
  /// In en, this message translates to:
  /// **'Device information'**
  String get deviceDashboardMyDevice;

  /// No description provided for @deviceDashboardIdentity.
  ///
  /// In en, this message translates to:
  /// **'Model and firmware'**
  String get deviceDashboardIdentity;

  /// No description provided for @deviceDashboardViewInfo.
  ///
  /// In en, this message translates to:
  /// **'View device information'**
  String get deviceDashboardViewInfo;

  /// No description provided for @deviceDashboardBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get deviceDashboardBattery;

  /// No description provided for @deviceDashboardCharging.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get deviceDashboardCharging;

  /// No description provided for @deviceDashboardViewBattery.
  ///
  /// In en, this message translates to:
  /// **'View charge and battery status'**
  String get deviceDashboardViewBattery;

  /// No description provided for @deviceDashboardSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get deviceDashboardSound;

  /// No description provided for @deviceDisableVibration.
  ///
  /// In en, this message translates to:
  /// **'Disable vibration'**
  String get deviceDisableVibration;

  /// No description provided for @deviceEnableVibration.
  ///
  /// In en, this message translates to:
  /// **'Enable vibration'**
  String get deviceEnableVibration;

  /// No description provided for @deviceMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get deviceMute;

  /// No description provided for @deviceSoundAndHaptics.
  ///
  /// In en, this message translates to:
  /// **'Sound and haptics'**
  String get deviceSoundAndHaptics;

  /// No description provided for @deviceVibrationIntensity.
  ///
  /// In en, this message translates to:
  /// **'Vibration intensity'**
  String get deviceVibrationIntensity;

  /// No description provided for @deviceUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get deviceUnmute;

  /// No description provided for @deviceScreenTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn screen off'**
  String get deviceScreenTurnOff;

  /// No description provided for @deviceScreenTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn screen on'**
  String get deviceScreenTurnOn;

  /// No description provided for @deviceDashboardScreenOn.
  ///
  /// In en, this message translates to:
  /// **'Screen is on'**
  String get deviceDashboardScreenOn;

  /// No description provided for @deviceDashboardScreenOff.
  ///
  /// In en, this message translates to:
  /// **'Screen is off'**
  String get deviceDashboardScreenOff;

  /// No description provided for @deviceDashboardRotation.
  ///
  /// In en, this message translates to:
  /// **'Screen rotation'**
  String get deviceDashboardRotation;

  /// No description provided for @deviceAutoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto lock'**
  String get deviceAutoLock;

  /// No description provided for @deviceAutoLockNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get deviceAutoLockNever;

  /// No description provided for @deviceAutoLockSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} sec'**
  String deviceAutoLockSeconds(int seconds);

  /// No description provided for @deviceAutoLockMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String deviceAutoLockMinutes(int minutes);

  /// No description provided for @deviceDashboardConnection.
  ///
  /// In en, this message translates to:
  /// **'Device connection'**
  String get deviceDashboardConnection;

  /// No description provided for @deviceInformationTitle.
  ///
  /// In en, this message translates to:
  /// **'Device information'**
  String get deviceInformationTitle;

  /// No description provided for @deviceInformationIdentity.
  ///
  /// In en, this message translates to:
  /// **'LilygoBox device'**
  String get deviceInformationIdentity;

  /// No description provided for @deviceInformationConnection.
  ///
  /// In en, this message translates to:
  /// **'Device connection'**
  String get deviceInformationConnection;

  /// No description provided for @deviceInformationView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get deviceInformationView;

  /// No description provided for @connectionReady.
  ///
  /// In en, this message translates to:
  /// **'Connection ready'**
  String get connectionReady;

  /// No description provided for @connectionThisComputer.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get connectionThisComputer;

  /// No description provided for @connectionInformation.
  ///
  /// In en, this message translates to:
  /// **'Connection information'**
  String get connectionInformation;

  /// No description provided for @connectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get connectionStatus;

  /// No description provided for @connectionMethod.
  ///
  /// In en, this message translates to:
  /// **'Connection method'**
  String get connectionMethod;

  /// No description provided for @connectionManage.
  ///
  /// In en, this message translates to:
  /// **'Manage connection'**
  String get connectionManage;

  /// No description provided for @connectionManualRecovery.
  ///
  /// In en, this message translates to:
  /// **'After disconnecting manually, select Reconnect to restore the connection.'**
  String get connectionManualRecovery;

  /// No description provided for @connectionCredentialTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection credentials'**
  String get connectionCredentialTitle;

  /// No description provided for @connectionCredentialDescription.
  ///
  /// In en, this message translates to:
  /// **'Credentials are saved after initial authorization, so reconnecting does not require approval again. Disconnecting keeps them; deleting the device removes its locally saved credentials.'**
  String get connectionCredentialDescription;

  /// No description provided for @deviceConnectionStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Device status'**
  String get deviceConnectionStatusTitle;

  /// No description provided for @deviceBatteryUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get deviceBatteryUnknown;

  /// No description provided for @deviceBatteryFull.
  ///
  /// In en, this message translates to:
  /// **'Fully charged'**
  String get deviceBatteryFull;

  /// No description provided for @deviceBatteryChargingState.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get deviceBatteryChargingState;

  /// No description provided for @deviceBatteryPowerState.
  ///
  /// In en, this message translates to:
  /// **'On battery'**
  String get deviceBatteryPowerState;

  /// No description provided for @deviceBatteryOffline.
  ///
  /// In en, this message translates to:
  /// **'Device not connected'**
  String get deviceBatteryOffline;

  /// No description provided for @deviceBatteryNoData.
  ///
  /// In en, this message translates to:
  /// **'No battery data'**
  String get deviceBatteryNoData;

  /// No description provided for @deviceBatteryChargerConnected.
  ///
  /// In en, this message translates to:
  /// **'Charger connected'**
  String get deviceBatteryChargerConnected;

  /// No description provided for @deviceBatteryNotCharging.
  ///
  /// In en, this message translates to:
  /// **'Not charging'**
  String get deviceBatteryNotCharging;

  /// No description provided for @deviceBatteryVoltage.
  ///
  /// In en, this message translates to:
  /// **'Voltage'**
  String get deviceBatteryVoltage;

  /// No description provided for @deviceBatteryTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get deviceBatteryTemperature;

  /// No description provided for @deviceBatteryChargingStatus.
  ///
  /// In en, this message translates to:
  /// **'Charging status'**
  String get deviceBatteryChargingStatus;

  /// No description provided for @deviceBatteryCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get deviceBatteryCurrent;

  /// No description provided for @deviceRotationConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Change display orientation?'**
  String get deviceRotationConfirmTitle;

  /// No description provided for @deviceRotationConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'Rotating will close the current page on the device and return to its home screen. Unsaved changes will be discarded. If the device is locked, it will stay locked.'**
  String get deviceRotationConfirmDescription;

  /// No description provided for @deviceRotationConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get deviceRotationConfirmAction;

  /// No description provided for @deviceBatteryHealth.
  ///
  /// In en, this message translates to:
  /// **'Battery health'**
  String get deviceBatteryHealth;

  /// No description provided for @deviceBatteryTimeToFull.
  ///
  /// In en, this message translates to:
  /// **'Estimated time to full'**
  String get deviceBatteryTimeToFull;

  /// No description provided for @deviceBatteryTimeToEmpty.
  ///
  /// In en, this message translates to:
  /// **'Estimated battery runtime'**
  String get deviceBatteryTimeToEmpty;

  /// No description provided for @deviceBatteryDuration.
  ///
  /// In en, this message translates to:
  /// **'{hours} hr {minutes} min'**
  String deviceBatteryDuration(int hours, int minutes);

  /// No description provided for @deviceBatteryCapacity.
  ///
  /// In en, this message translates to:
  /// **'Rated battery capacity'**
  String get deviceBatteryCapacity;

  /// No description provided for @deviceBatteryCapacityEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get deviceBatteryCapacityEdit;

  /// No description provided for @deviceBatteryCapacityDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter the rated capacity in mAh. This setting is saved on the device and used for battery and runtime estimates; it is not the remaining capacity.'**
  String get deviceBatteryCapacityDescription;

  /// No description provided for @deviceBatteryCapacityRange.
  ///
  /// In en, this message translates to:
  /// **'Range: {minimum}–{maximum} mAh'**
  String deviceBatteryCapacityRange(int minimum, int maximum);

  /// No description provided for @deviceBatteryCapacityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole-number capacity within the range.'**
  String get deviceBatteryCapacityInvalid;

  /// No description provided for @deviceBatteryCapacitySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Check the device connection and try again.'**
  String get deviceBatteryCapacitySaveFailed;

  /// No description provided for @deviceBatteryCapacitySaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get deviceBatteryCapacitySaving;

  /// No description provided for @deviceBatteryCapacitySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get deviceBatteryCapacitySave;

  /// No description provided for @deviceBatteryEstimateMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String deviceBatteryEstimateMinutes(int minutes);

  /// No description provided for @deviceBatteryEstimateToFull.
  ///
  /// In en, this message translates to:
  /// **'{duration} to full'**
  String deviceBatteryEstimateToFull(String duration);

  /// No description provided for @deviceBatteryEstimateRemaining.
  ///
  /// In en, this message translates to:
  /// **'{duration} remaining'**
  String deviceBatteryEstimateRemaining(Object duration);

  /// No description provided for @deviceBatteryLevel.
  ///
  /// In en, this message translates to:
  /// **'Battery level'**
  String get deviceBatteryLevel;

  /// No description provided for @deviceWifiSignal.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi signal'**
  String get deviceWifiSignal;

  /// No description provided for @deviceNameEditDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter a device name (up to 64 UTF-8 bytes). The name is saved on the device.'**
  String get deviceNameEditDescription;

  /// No description provided for @deviceNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-empty name within 64 UTF-8 bytes, without control characters.'**
  String get deviceNameInvalid;

  /// No description provided for @deviceNameSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the name. Check the device connection and try again.'**
  String get deviceNameSaveFailed;

  /// No description provided for @deviceNameStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'The device could not save the name to storage. Your input has been kept; please try again.'**
  String get deviceNameStorageFailed;

  /// Firmware update interface: otaUpdating
  ///
  /// In en, this message translates to:
  /// **'Updating'**
  String get otaUpdating;

  /// Firmware update interface: otaCheck
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get otaCheck;

  /// Firmware update interface: otaNewVersion
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get otaNewVersion;

  /// Firmware update interface: otaViewStatus
  ///
  /// In en, this message translates to:
  /// **'View device update status'**
  String get otaViewStatus;

  /// Firmware update interface: otaCheckTitle
  ///
  /// In en, this message translates to:
  /// **'Check for firmware updates'**
  String get otaCheckTitle;

  /// Firmware update interface: otaUpdateTo
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String otaUpdateTo(String version);

  /// Firmware update interface: otaUpdateFirmware
  ///
  /// In en, this message translates to:
  /// **'Update firmware'**
  String get otaUpdateFirmware;

  /// Firmware update interface: otaWirelessVersion
  ///
  /// In en, this message translates to:
  /// **'Wireless firmware version'**
  String get otaWirelessVersion;

  /// Firmware update interface: otaMainVersion
  ///
  /// In en, this message translates to:
  /// **'Main firmware version'**
  String get otaMainVersion;

  /// Firmware update interface: otaNotes
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get otaNotes;

  /// Firmware update interface: otaUnknown
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get otaUnknown;

  /// Firmware update interface: otaCheckDisconnected
  ///
  /// In en, this message translates to:
  /// **'The device disconnected or changed. Reconnect before checking for updates.'**
  String get otaCheckDisconnected;

  /// Firmware update interface: otaCheckTimeout
  ///
  /// In en, this message translates to:
  /// **'The update check timed out. Check your network and try again.'**
  String get otaCheckTimeout;

  /// Firmware update interface: otaManifestMissing
  ///
  /// In en, this message translates to:
  /// **'No OTA manifest was found for this device (HTTP 404).'**
  String get otaManifestMissing;

  /// Firmware update interface: otaManifestTimeout
  ///
  /// In en, this message translates to:
  /// **'The OTA manifest request timed out. Check your network and try again.'**
  String get otaManifestTimeout;

  /// Firmware update interface: otaManifestIncompatible
  ///
  /// In en, this message translates to:
  /// **'The OTA manifest does not match this device model, hardware version, or chip.'**
  String get otaManifestIncompatible;

  /// Firmware update interface: otaManifestNetwork
  ///
  /// In en, this message translates to:
  /// **'Could not retrieve the OTA manifest. Check your network and try again.'**
  String get otaManifestNetwork;

  /// Firmware update interface: otaCheckError
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates: {detail}'**
  String otaCheckError(String detail);

  /// Firmware update interface: otaCheckFailed
  ///
  /// In en, this message translates to:
  /// **'Update check failed'**
  String get otaCheckFailed;

  /// Firmware update interface: otaChecking
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get otaChecking;

  /// Firmware update interface: otaLatest
  ///
  /// In en, this message translates to:
  /// **'You are up to date'**
  String get otaLatest;

  /// Firmware update interface: otaCancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get otaCancel;

  /// Firmware update interface: otaClose
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get otaClose;

  /// Firmware update interface: otaRetry
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get otaRetry;

  /// Firmware update interface: otaFound
  ///
  /// In en, this message translates to:
  /// **'Firmware update available'**
  String get otaFound;

  /// Firmware update interface: otaDeviceTitle
  ///
  /// In en, this message translates to:
  /// **'Device firmware update'**
  String get otaDeviceTitle;

  /// Firmware update interface: otaTitle
  ///
  /// In en, this message translates to:
  /// **'Firmware update'**
  String get otaTitle;

  /// Firmware update interface: otaRemoteSource
  ///
  /// In en, this message translates to:
  /// **'Device online update · Closing this window does not stop the device task'**
  String get otaRemoteSource;

  /// Firmware update interface: otaLocalSource
  ///
  /// In en, this message translates to:
  /// **'LAN update · Firmware is provided by the app that started the update'**
  String get otaLocalSource;

  /// Firmware update interface: otaDeviceCacheHint
  ///
  /// In en, this message translates to:
  /// **'The device already has all firmware required for this update. It can verify the files again and prepare installation.'**
  String get otaDeviceCacheHint;

  /// Firmware update interface: otaCacheChecking
  ///
  /// In en, this message translates to:
  /// **'Verifying firmware downloaded on this computer…'**
  String get otaCacheChecking;

  /// Firmware update interface: otaAppCacheHint
  ///
  /// In en, this message translates to:
  /// **'Downloaded and verified: {components}. Use these files and download any missing components.'**
  String otaAppCacheHint(String components);

  /// Firmware update interface: otaMainComponent
  ///
  /// In en, this message translates to:
  /// **'Main firmware'**
  String get otaMainComponent;

  /// Firmware update interface: otaWirelessComponent
  ///
  /// In en, this message translates to:
  /// **'Wireless firmware'**
  String get otaWirelessComponent;

  /// Firmware update interface: otaComponentsSeparator
  ///
  /// In en, this message translates to:
  /// **', '**
  String get otaComponentsSeparator;

  /// Firmware update interface: otaCancelling
  ///
  /// In en, this message translates to:
  /// **'Cancelling update…'**
  String get otaCancelling;

  /// Firmware update interface: otaCancelUpdate
  ///
  /// In en, this message translates to:
  /// **'Cancel update'**
  String get otaCancelUpdate;

  /// Firmware update interface: otaRedownload
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get otaRedownload;

  /// Firmware update interface: otaUseDeviceCache
  ///
  /// In en, this message translates to:
  /// **'Use device firmware'**
  String get otaUseDeviceCache;

  /// Firmware update interface: otaUseCache
  ///
  /// In en, this message translates to:
  /// **'Use downloaded firmware'**
  String get otaUseCache;

  /// Firmware update interface: otaDownloadUpdate
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get otaDownloadUpdate;

  /// Firmware update interface: otaInstall
  ///
  /// In en, this message translates to:
  /// **'Restart and install'**
  String get otaInstall;

  /// Firmware update interface: otaDownloadingMain
  ///
  /// In en, this message translates to:
  /// **'Downloading main firmware'**
  String get otaDownloadingMain;

  /// Firmware update interface: otaDownloadingWireless
  ///
  /// In en, this message translates to:
  /// **'Downloading wireless firmware'**
  String get otaDownloadingWireless;

  /// Firmware update interface: otaRequestCache
  ///
  /// In en, this message translates to:
  /// **'Requesting verification of firmware already on the device…'**
  String get otaRequestCache;

  /// Firmware update interface: otaCacheTimeout
  ///
  /// In en, this message translates to:
  /// **'Device firmware cache verification timed out.'**
  String get otaCacheTimeout;

  /// Firmware update interface: otaCacheRejected
  ///
  /// In en, this message translates to:
  /// **'The device did not accept the cached firmware. Try again or download the files again.'**
  String get otaCacheRejected;

  /// Firmware update interface: otaCacheFailed
  ///
  /// In en, this message translates to:
  /// **'Could not use the device firmware cache: {detail}'**
  String otaCacheFailed(String detail);

  /// Firmware update interface: otaDownloadTimeout
  ///
  /// In en, this message translates to:
  /// **'The download timed out. Please try again.'**
  String get otaDownloadTimeout;

  /// Firmware update interface: otaDownloadFailed
  ///
  /// In en, this message translates to:
  /// **'Firmware download or verification failed: {detail}'**
  String otaDownloadFailed(String detail);

  /// Firmware update interface: otaWaitingTransfer
  ///
  /// In en, this message translates to:
  /// **'Waiting for the device to accept the transfer…'**
  String get otaWaitingTransfer;

  /// Firmware update interface: otaTransferTimeout
  ///
  /// In en, this message translates to:
  /// **'Firmware transfer to the device timed out.'**
  String get otaTransferTimeout;

  /// Firmware update interface: otaTransferRejected
  ///
  /// In en, this message translates to:
  /// **'The device did not accept the transfer. Make sure its firmware supports staged updates.'**
  String get otaTransferRejected;

  /// Firmware update interface: otaTransferFailed
  ///
  /// In en, this message translates to:
  /// **'Could not transfer firmware: {detail}'**
  String otaTransferFailed(String detail);

  /// Firmware update interface: otaRequestInstall
  ///
  /// In en, this message translates to:
  /// **'Requesting restart and installation…\nYou may close this window. Do not turn off the device.'**
  String get otaRequestInstall;

  /// Firmware update interface: otaInstallRejected
  ///
  /// In en, this message translates to:
  /// **'The device did not confirm restart and installation.'**
  String get otaInstallRejected;

  /// Firmware update interface: otaInstallConfirmed
  ///
  /// In en, this message translates to:
  /// **'Restart and installation confirmed. The device will install automatically and restart. Do not turn it off.'**
  String get otaInstallConfirmed;

  /// Firmware update interface: otaDeviceChanged
  ///
  /// In en, this message translates to:
  /// **'The selected device changed. This update has stopped.'**
  String get otaDeviceChanged;

  /// Firmware update interface: otaInstallDisconnected
  ///
  /// In en, this message translates to:
  /// **'The device disconnected. Waiting for confirmation of restart and installation…'**
  String get otaInstallDisconnected;

  /// Firmware update interface: otaObserverDisconnected
  ///
  /// In en, this message translates to:
  /// **'The device disconnected. Reconnect to view its update status.'**
  String get otaObserverDisconnected;

  /// Firmware update interface: otaDisconnected
  ///
  /// In en, this message translates to:
  /// **'The device disconnected. The update has stopped.'**
  String get otaDisconnected;

  /// Firmware update interface: otaTaskChanged
  ///
  /// In en, this message translates to:
  /// **'The device update task changed. Reopen the update window.'**
  String get otaTaskChanged;

  /// Firmware update interface: otaOtherTask
  ///
  /// In en, this message translates to:
  /// **'The device is already updating. Close this window to view its current task.'**
  String get otaOtherTask;

  /// Firmware update interface: otaLatestComplete
  ///
  /// In en, this message translates to:
  /// **'You are up to date.'**
  String get otaLatestComplete;

  /// Firmware update interface: otaCheckAvailable
  ///
  /// In en, this message translates to:
  /// **'An update is available. Start the download on the device or close this window to choose it in the app.'**
  String get otaCheckAvailable;

  /// Firmware update interface: otaNoTask
  ///
  /// In en, this message translates to:
  /// **'The device has no update task in progress.'**
  String get otaNoTask;

  /// Firmware update interface: otaDeviceFailed
  ///
  /// In en, this message translates to:
  /// **'The device update failed: {detail}'**
  String otaDeviceFailed(String detail);

  /// Firmware update interface: otaDeviceCancelled
  ///
  /// In en, this message translates to:
  /// **'The device cancelled the update and kept its current firmware.'**
  String get otaDeviceCancelled;

  /// Firmware update interface: otaPrepared
  ///
  /// In en, this message translates to:
  /// **'Firmware received and verified. Select Restart and install to turn off the device screen, install the update, and restart automatically.'**
  String get otaPrepared;

  /// Firmware update interface: otaPreparedOtherApp
  ///
  /// In en, this message translates to:
  /// **'Firmware is ready. Confirm restart and installation in the app that started the update.'**
  String get otaPreparedOtherApp;

  /// Firmware update interface: otaInstalling
  ///
  /// In en, this message translates to:
  /// **'The device is installing and restarting. Do not turn it off.\nClosing this window does not stop installation.'**
  String get otaInstalling;

  /// Firmware update interface: otaDeviceChecking
  ///
  /// In en, this message translates to:
  /// **'The device is checking for firmware updates online…'**
  String get otaDeviceChecking;

  /// Firmware update interface: otaPaused
  ///
  /// In en, this message translates to:
  /// **'The device paused the download. Resume it on the device or cancel this update.'**
  String get otaPaused;

  /// Firmware update interface: otaVerifyingMain
  ///
  /// In en, this message translates to:
  /// **'The device is verifying the main firmware image and SHA-256…'**
  String get otaVerifyingMain;

  /// Firmware update interface: otaVerifyingWireless
  ///
  /// In en, this message translates to:
  /// **'The device is verifying the wireless firmware image and SHA-256…'**
  String get otaVerifyingWireless;

  /// Firmware update interface: otaPreparing
  ///
  /// In en, this message translates to:
  /// **'The device is preparing firmware for installation…'**
  String get otaPreparing;

  /// Firmware update interface: otaCancelled
  ///
  /// In en, this message translates to:
  /// **'Update cancelled. The current firmware has been kept.'**
  String get otaCancelled;

  /// Firmware update interface: otaCancelRejected
  ///
  /// In en, this message translates to:
  /// **'The device rejected cancellation of this task.'**
  String get otaCancelRejected;

  /// Firmware update interface: otaCancelUnconfirmed
  ///
  /// In en, this message translates to:
  /// **'The device did not confirm cancellation: {detail}'**
  String otaCancelUnconfirmed(String detail);

  /// Firmware update interface: otaProgress
  ///
  /// In en, this message translates to:
  /// **'{action} · {received} / {total}'**
  String otaProgress(String action, String received, String total);

  /// Firmware update interface: otaDownloadMain
  ///
  /// In en, this message translates to:
  /// **'Download main firmware'**
  String get otaDownloadMain;

  /// Firmware update interface: otaDownloadWireless
  ///
  /// In en, this message translates to:
  /// **'Download wireless firmware'**
  String get otaDownloadWireless;

  /// Firmware update interface: otaDeviceDownloadMain
  ///
  /// In en, this message translates to:
  /// **'Device downloading main firmware'**
  String get otaDeviceDownloadMain;

  /// Firmware update interface: otaDeviceDownloadWireless
  ///
  /// In en, this message translates to:
  /// **'Device downloading wireless firmware'**
  String get otaDeviceDownloadWireless;

  /// Firmware update interface: otaTransferMain
  ///
  /// In en, this message translates to:
  /// **'Transfer main firmware'**
  String get otaTransferMain;

  /// Firmware update interface: otaTransferWireless
  ///
  /// In en, this message translates to:
  /// **'Transfer wireless firmware'**
  String get otaTransferWireless;

  /// Firmware update interface: otaAwaitingProgress
  ///
  /// In en, this message translates to:
  /// **'{action} · Waiting for device progress'**
  String otaAwaitingProgress(String action);

  /// Firmware update interface: otaDownloadComplete
  ///
  /// In en, this message translates to:
  /// **'{component} downloaded. Waiting for device verification…'**
  String otaDownloadComplete(String component);

  /// Firmware update interface: otaTransferComplete
  ///
  /// In en, this message translates to:
  /// **'{component} transferred. Waiting for device verification…'**
  String otaTransferComplete(String component);
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
