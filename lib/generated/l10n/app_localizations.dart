/*
 * @Description: 自动生成的本地化文件
 * @Author: LILYGO_L
 * @Date: 2025-10-27 11:20:43
 * @LastEditTime: 2026-11-09 09:47:22
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

  /// No description provided for @githubSignInDialogDescription.
  ///
  /// In en, this message translates to:
  /// **'Authorize this app in your browser, then return here to finish signing in. Closing this dialog cancels this sign-in attempt.'**
  String get githubSignInDialogDescription;

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

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @fontDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the application font. System follows the operating system default.'**
  String get fontDescription;

  /// No description provided for @fontSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get fontSystem;

  /// No description provided for @fontInter.
  ///
  /// In en, this message translates to:
  /// **'Inter'**
  String get fontInter;

  /// No description provided for @fontGoogleSansFlex.
  ///
  /// In en, this message translates to:
  /// **'Google Sans Flex'**
  String get fontGoogleSansFlex;

  /// No description provided for @fontRoboto.
  ///
  /// In en, this message translates to:
  /// **'Roboto'**
  String get fontRoboto;

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

  /// No description provided for @languageAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get languageAutoDetect;

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
  /// **'Automatically follow your system language or choose an application interface language.'**
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

  /// No description provided for @deviceManagement.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get deviceManagement;

  /// No description provided for @assistantTitle.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistantTitle;

  /// No description provided for @assistantGreeting.
  ///
  /// In en, this message translates to:
  /// **'What can I help you with today?'**
  String get assistantGreeting;

  /// No description provided for @assistantDescription.
  ///
  /// In en, this message translates to:
  /// **'Share an idea, or ask the assistant to adjust LilygoBox.'**
  String get assistantDescription;

  /// No description provided for @aiPromptDevices.
  ///
  /// In en, this message translates to:
  /// **'Show my devices'**
  String get aiPromptDevices;

  /// No description provided for @aiPromptAppearance.
  ///
  /// In en, this message translates to:
  /// **'Change the app theme'**
  String get aiPromptAppearance;

  /// No description provided for @aiPromptLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change the app language'**
  String get aiPromptLanguage;

  /// No description provided for @aiInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a question, or describe a setting to change…'**
  String get aiInputHint;

  /// No description provided for @aiAttachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach files'**
  String get aiAttachFile;

  /// No description provided for @aiStop.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get aiStop;

  /// No description provided for @aiContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue generating'**
  String get aiContinue;

  /// No description provided for @aiGuideTurn.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get aiGuideTurn;

  /// No description provided for @aiGuidanceHint.
  ///
  /// In en, this message translates to:
  /// **'Add a follow-up message…'**
  String get aiGuidanceHint;

  /// No description provided for @aiGuidancePending.
  ///
  /// In en, this message translates to:
  /// **'Queued messages'**
  String get aiGuidancePending;

  /// No description provided for @aiRemoveGuidance.
  ///
  /// In en, this message translates to:
  /// **'Remove queued message'**
  String get aiRemoveGuidance;

  /// No description provided for @aiSendPendingGuidance.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get aiSendPendingGuidance;

  /// No description provided for @aiEditQueuedMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit queued message'**
  String get aiEditQueuedMessage;

  /// No description provided for @aiSaveQueuedMessage.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get aiSaveQueuedMessage;

  /// No description provided for @aiRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get aiRemoveImage;

  /// No description provided for @aiViewOriginal.
  ///
  /// In en, this message translates to:
  /// **'View original image'**
  String get aiViewOriginal;

  /// No description provided for @aiImagePreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the image.'**
  String get aiImagePreviewFailed;

  /// No description provided for @aiCopyImage.
  ///
  /// In en, this message translates to:
  /// **'Copy image'**
  String get aiCopyImage;

  /// No description provided for @aiImageUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This model is declared text-only. Switch models to send images or continue a conversation containing images. Your draft has been kept.'**
  String get aiImageUnsupported;

  /// No description provided for @aiCopyImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy the image. Please try again.'**
  String get aiCopyImageFailed;

  /// No description provided for @aiPasteImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read clipboard images. Please try again.'**
  String get aiPasteImageFailed;

  /// No description provided for @aiSend.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get aiSend;

  /// No description provided for @aiClearConversation.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation'**
  String get aiClearConversation;

  /// No description provided for @aiConfigureMessage.
  ///
  /// In en, this message translates to:
  /// **'Configure an AI service in Settings to start chatting.'**
  String get aiConfigureMessage;

  /// No description provided for @aiSetupAction.
  ///
  /// In en, this message translates to:
  /// **'Configure AI service'**
  String get aiSetupAction;

  /// No description provided for @aiAssistantThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get aiAssistantThinking;

  /// No description provided for @aiConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get aiConnecting;

  /// No description provided for @aiAwaitingReply.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the model response'**
  String get aiAwaitingReply;

  /// No description provided for @aiProcessCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get aiProcessCompleted;

  /// No description provided for @aiProcessReasoning.
  ///
  /// In en, this message translates to:
  /// **'Model reasoning'**
  String get aiProcessReasoning;

  /// No description provided for @aiProcessActionSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Executed: {action}'**
  String aiProcessActionSucceeded(String action);

  /// No description provided for @aiProcessActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {action}'**
  String aiProcessActionFailed(String action);

  /// No description provided for @aiStreaming.
  ///
  /// In en, this message translates to:
  /// **'Responding'**
  String get aiStreaming;

  /// No description provided for @aiPreparingTools.
  ///
  /// In en, this message translates to:
  /// **'Preparing tool calls'**
  String get aiPreparingTools;

  /// No description provided for @aiRequestRetryRecord.
  ///
  /// In en, this message translates to:
  /// **'Model request retry {attempt}'**
  String aiRequestRetryRecord(int attempt);

  /// No description provided for @aiWebInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid webpage address. Check the complete URL.'**
  String get aiWebInvalidUrl;

  /// No description provided for @aiWebUnsupportedScheme.
  ///
  /// In en, this message translates to:
  /// **'Only HTTPS webpages are supported. Provide an HTTPS URL.'**
  String get aiWebUnsupportedScheme;

  /// No description provided for @aiWebUnsupportedPort.
  ///
  /// In en, this message translates to:
  /// **'Only the default HTTPS port 443 is supported.'**
  String get aiWebUnsupportedPort;

  /// No description provided for @aiWebCredentialsNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Webpage URLs cannot contain a username or password.'**
  String get aiWebCredentialsNotAllowed;

  /// No description provided for @aiWebBlockedAddress.
  ///
  /// In en, this message translates to:
  /// **'Local, private, or reserved addresses are blocked. Use a public webpage URL.'**
  String get aiWebBlockedAddress;

  /// No description provided for @aiWebDns.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve the website hostname. Check the URL or try again later.'**
  String get aiWebDns;

  /// No description provided for @aiWebConnection.
  ///
  /// In en, this message translates to:
  /// **'The connection failed or was interrupted. Check the network and try again.'**
  String get aiWebConnection;

  /// No description provided for @aiWebTimeout.
  ///
  /// In en, this message translates to:
  /// **'Reading the webpage timed out. Try again later.'**
  String get aiWebTimeout;

  /// No description provided for @aiWebTls.
  ///
  /// In en, this message translates to:
  /// **'Could not establish a secure connection. Check the website certificate and system time.'**
  String get aiWebTls;

  /// No description provided for @aiWebUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'The website requires authentication (HTTP 401). Signed-in access is not supported.'**
  String get aiWebUnauthorized;

  /// No description provided for @aiWebForbidden.
  ///
  /// In en, this message translates to:
  /// **'The website refused access (HTTP 403). Check whether the page allows public access.'**
  String get aiWebForbidden;

  /// No description provided for @aiWebNotFound.
  ///
  /// In en, this message translates to:
  /// **'The webpage was not found (HTTP 404). Check the URL.'**
  String get aiWebNotFound;

  /// No description provided for @aiWebRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The website rate limit was reached (HTTP 429). Try again later.'**
  String get aiWebRateLimited;

  /// No description provided for @aiWebServerError.
  ///
  /// In en, this message translates to:
  /// **'The website returned a server error (HTTP {status}). Try again later.'**
  String aiWebServerError(int status);

  /// No description provided for @aiWebHttpStatus.
  ///
  /// In en, this message translates to:
  /// **'The website returned HTTP {status}. The page could not be read.'**
  String aiWebHttpStatus(int status);

  /// No description provided for @aiWebInvalidRedirect.
  ///
  /// In en, this message translates to:
  /// **'The website returned a missing or invalid redirect URL. No further request was made.'**
  String get aiWebInvalidRedirect;

  /// No description provided for @aiWebRedirectLoop.
  ///
  /// In en, this message translates to:
  /// **'A redirect loop was detected. Webpage access was stopped.'**
  String get aiWebRedirectLoop;

  /// No description provided for @aiWebTooManyRedirects.
  ///
  /// In en, this message translates to:
  /// **'The webpage exceeded the limit of 5 redirects. Access was stopped.'**
  String get aiWebTooManyRedirects;

  /// No description provided for @aiWebContentType.
  ///
  /// In en, this message translates to:
  /// **'This URL did not return supported text content. Images and PDFs are not supported.'**
  String get aiWebContentType;

  /// No description provided for @aiWebEncoding.
  ///
  /// In en, this message translates to:
  /// **'The webpage uses an unsupported encoding or could not be decoded.'**
  String get aiWebEncoding;

  /// No description provided for @aiWebTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The webpage exceeds the 1 MiB limit. No partial content was returned.'**
  String get aiWebTooLarge;

  /// No description provided for @aiWebEmptyContent.
  ///
  /// In en, this message translates to:
  /// **'The website returned empty content. No page text was received.'**
  String get aiWebEmptyContent;

  /// No description provided for @aiWebCancelled.
  ///
  /// In en, this message translates to:
  /// **'Webpage access was cancelled.'**
  String get aiWebCancelled;

  /// No description provided for @aiAccessingWeb.
  ///
  /// In en, this message translates to:
  /// **'Accessing webpage'**
  String get aiAccessingWeb;

  /// No description provided for @aiWebSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Accessed webpage {url}'**
  String aiWebSucceeded(String url);

  /// No description provided for @aiWebFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to access webpage {url}'**
  String aiWebFailed(String url);

  /// No description provided for @aiExecutingTools.
  ///
  /// In en, this message translates to:
  /// **'Executing tools'**
  String get aiExecutingTools;

  /// No description provided for @aiOperationError.
  ///
  /// In en, this message translates to:
  /// **'Error details'**
  String get aiOperationError;

  /// No description provided for @aiOperationTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get aiOperationTarget;

  /// No description provided for @aiOperationSummary.
  ///
  /// In en, this message translates to:
  /// **'Outcome'**
  String get aiOperationSummary;

  /// No description provided for @aiDirectoryListed.
  ///
  /// In en, this message translates to:
  /// **'Listed directory · {target}'**
  String aiDirectoryListed(String target);

  /// No description provided for @aiFileReadCompleted.
  ///
  /// In en, this message translates to:
  /// **'Read file · {target}'**
  String aiFileReadCompleted(String target);

  /// No description provided for @aiFileWriteCompleted.
  ///
  /// In en, this message translates to:
  /// **'Wrote file · {target}'**
  String aiFileWriteCompleted(String target);

  /// No description provided for @aiTimeReadCompleted.
  ///
  /// In en, this message translates to:
  /// **'Read current time'**
  String get aiTimeReadCompleted;

  /// No description provided for @aiWebReadSummary.
  ///
  /// In en, this message translates to:
  /// **'Read the webpage content.'**
  String get aiWebReadSummary;

  /// No description provided for @aiDirectoryReadSummary.
  ///
  /// In en, this message translates to:
  /// **'Listed the directory entries.'**
  String get aiDirectoryReadSummary;

  /// No description provided for @aiFileReadSummary.
  ///
  /// In en, this message translates to:
  /// **'Read the file content.'**
  String get aiFileReadSummary;

  /// No description provided for @aiFileWriteSummary.
  ///
  /// In en, this message translates to:
  /// **'Wrote the content to the target file.'**
  String get aiFileWriteSummary;

  /// No description provided for @aiExecutingListDirectory.
  ///
  /// In en, this message translates to:
  /// **'Listing directory'**
  String get aiExecutingListDirectory;

  /// No description provided for @aiExecutingReadFile.
  ///
  /// In en, this message translates to:
  /// **'Reading file'**
  String get aiExecutingReadFile;

  /// No description provided for @aiExecutingWriteFile.
  ///
  /// In en, this message translates to:
  /// **'Writing file'**
  String get aiExecutingWriteFile;

  /// No description provided for @aiExecutingReadTime.
  ///
  /// In en, this message translates to:
  /// **'Reading current time'**
  String get aiExecutingReadTime;

  /// No description provided for @aiExecutingSetTheme.
  ///
  /// In en, this message translates to:
  /// **'Changing theme'**
  String get aiExecutingSetTheme;

  /// No description provided for @aiExecutingSetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Changing language'**
  String get aiExecutingSetLanguage;

  /// No description provided for @aiExecutingSetFont.
  ///
  /// In en, this message translates to:
  /// **'Changing font'**
  String get aiExecutingSetFont;

  /// No description provided for @aiExecutingSetSidebarVisibility.
  ///
  /// In en, this message translates to:
  /// **'Changing sidebar visibility'**
  String get aiExecutingSetSidebarVisibility;

  /// No description provided for @aiExecutingSetSidebarWidth.
  ///
  /// In en, this message translates to:
  /// **'Adjusting sidebar width'**
  String get aiExecutingSetSidebarWidth;

  /// No description provided for @aiExecutingSetContentSplitWidth.
  ///
  /// In en, this message translates to:
  /// **'Adjusting content split width'**
  String get aiExecutingSetContentSplitWidth;

  /// No description provided for @aiExecutingNamedTool.
  ///
  /// In en, this message translates to:
  /// **'Executing {name}'**
  String aiExecutingNamedTool(String name);

  /// No description provided for @aiResponseFailed.
  ///
  /// In en, this message translates to:
  /// **'Processing failed'**
  String get aiResponseFailed;

  /// No description provided for @aiResponseStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get aiResponseStopped;

  /// No description provided for @aiTurnFailed.
  ///
  /// In en, this message translates to:
  /// **'This turn failed'**
  String get aiTurnFailed;

  /// No description provided for @aiRetryingRequest.
  ///
  /// In en, this message translates to:
  /// **'Retrying model request ({attempt}/{total})'**
  String aiRetryingRequest(int attempt, int total);

  /// No description provided for @aiStatusElapsed.
  ///
  /// In en, this message translates to:
  /// **'{status} · {duration}'**
  String aiStatusElapsed(String status, String duration);

  /// No description provided for @aiResponseElapsed.
  ///
  /// In en, this message translates to:
  /// **'Worked for {duration}'**
  String aiResponseElapsed(String duration);

  /// No description provided for @aiResponseModel.
  ///
  /// In en, this message translates to:
  /// **'Model: {model}'**
  String aiResponseModel(String model);

  /// No description provided for @aiThinkingElapsed.
  ///
  /// In en, this message translates to:
  /// **'Thinking… {duration}'**
  String aiThinkingElapsed(String duration);

  /// No description provided for @aiApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Approval required'**
  String get aiApprovalTitle;

  /// No description provided for @aiApprove.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get aiApprove;

  /// No description provided for @aiReject.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get aiReject;

  /// No description provided for @aiActionApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get aiActionApproved;

  /// No description provided for @aiActionRejected.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get aiActionRejected;

  /// No description provided for @aiActionTheme.
  ///
  /// In en, this message translates to:
  /// **'Change theme to {value}'**
  String aiActionTheme(String value);

  /// No description provided for @aiActionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change language to {value}'**
  String aiActionLanguage(String value);

  /// No description provided for @aiActionFont.
  ///
  /// In en, this message translates to:
  /// **'Change font to {value}'**
  String aiActionFont(String value);

  /// No description provided for @aiActionShowSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show the main sidebar'**
  String get aiActionShowSidebar;

  /// No description provided for @aiActionHideSidebar.
  ///
  /// In en, this message translates to:
  /// **'Hide the main sidebar'**
  String get aiActionHideSidebar;

  /// No description provided for @aiActionSidebarWidth.
  ///
  /// In en, this message translates to:
  /// **'Set main sidebar width to {value} px'**
  String aiActionSidebarWidth(String value);

  /// No description provided for @aiActionSplitWidth.
  ///
  /// In en, this message translates to:
  /// **'Set device split width to {value} px'**
  String aiActionSplitWidth(String value);

  /// No description provided for @aiActionSettingsWidth.
  ///
  /// In en, this message translates to:
  /// **'Set settings sidebar width to {value} px'**
  String aiActionSettingsWidth(String value);

  /// No description provided for @aiActionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Change an application setting'**
  String get aiActionUnknown;

  /// No description provided for @aiServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Model services'**
  String get aiServiceTitle;

  /// No description provided for @aiServiceDescription.
  ///
  /// In en, this message translates to:
  /// **'Add model services and configure endpoints, keys and models. Keys stay in this device’s system secure storage.'**
  String get aiServiceDescription;

  /// No description provided for @aiProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get aiProviderLabel;

  /// No description provided for @aiProviderDescription.
  ///
  /// In en, this message translates to:
  /// **'Official providers set the API URL and protocol automatically. Choose Custom to configure them yourself. Switching providers clears the entered key and model list.'**
  String get aiProviderDescription;

  /// No description provided for @aiProviderDeepseek.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek (official)'**
  String get aiProviderDeepseek;

  /// No description provided for @aiProviderOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI (official)'**
  String get aiProviderOpenAi;

  /// No description provided for @aiProviderCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get aiProviderCustom;

  /// No description provided for @aiProviderCompatible.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible API'**
  String get aiProviderCompatible;

  /// No description provided for @aiBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'API URL'**
  String get aiBaseUrlLabel;

  /// No description provided for @aiBaseUrlDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter the API URL. The client adds the path required by the selected protocol.'**
  String get aiBaseUrlDescription;

  /// No description provided for @aiDragService.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder services'**
  String get aiDragService;

  /// No description provided for @aiModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModelLabel;

  /// No description provided for @aiModelDescription.
  ///
  /// In en, this message translates to:
  /// **'Model identifier used by the selected service.'**
  String get aiModelDescription;

  /// No description provided for @aiApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiApiKeyLabel;

  /// No description provided for @aiApiKeyDescription.
  ///
  /// In en, this message translates to:
  /// **'The key is saved locally using the operating system secure storage.'**
  String get aiApiKeyDescription;

  /// No description provided for @aiApiKeyStored.
  ///
  /// In en, this message translates to:
  /// **'A key is saved securely. Enter a new key to replace it.'**
  String get aiApiKeyStored;

  /// No description provided for @aiRemoveApiKey.
  ///
  /// In en, this message translates to:
  /// **'Remove saved API key'**
  String get aiRemoveApiKey;

  /// No description provided for @aiSaveAndTest.
  ///
  /// In en, this message translates to:
  /// **'Save and test connection'**
  String get aiSaveAndTest;

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

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @checkForAppUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for app updates'**
  String get checkForAppUpdates;

  /// No description provided for @appUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'App update'**
  String get appUpdateTitle;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get appVersion;

  /// No description provided for @downloadAppUpdate.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get downloadAppUpdate;

  /// No description provided for @cancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// No description provided for @installAppUpdate.
  ///
  /// In en, this message translates to:
  /// **'Install update'**
  String get installAppUpdate;

  /// No description provided for @preparingAppUpdate.
  ///
  /// In en, this message translates to:
  /// **'Preparing installer…'**
  String get preparingAppUpdate;

  /// No description provided for @downloadingAppUpdate.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get downloadingAppUpdate;

  /// No description provided for @appUpdateDownloadProgress.
  ///
  /// In en, this message translates to:
  /// **'{received} MB / {total} MB'**
  String appUpdateDownloadProgress(Object received, Object total);

  /// No description provided for @appUpdateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Download complete. The installer passed integrity verification.'**
  String get appUpdateDownloaded;

  /// No description provided for @appUpdateDownloadFailure.
  ///
  /// In en, this message translates to:
  /// **'Update download failed. Check your network and free disk space, then retry.'**
  String get appUpdateDownloadFailure;

  /// No description provided for @appUpdateIntegrityFailure.
  ///
  /// In en, this message translates to:
  /// **'The installer size or SHA-256 does not match. Installation was stopped.'**
  String get appUpdateIntegrityFailure;

  /// No description provided for @appUpdateInstallerLaunchFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not start the update installer. Try again, or open the downloaded installer manually.'**
  String get appUpdateInstallerLaunchFailure;

  /// No description provided for @checkingForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get checkingForUpdates;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'You are up to date'**
  String get upToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {version}'**
  String updateAvailable(Object version);

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to check for updates'**
  String get updateCheckFailed;

  /// No description provided for @updateCheckNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to GitHub. Check your network connection or proxy settings.'**
  String get updateCheckNetworkFailure;

  /// No description provided for @updateCheckTimeout.
  ///
  /// In en, this message translates to:
  /// **'The connection to GitHub timed out. Try again later.'**
  String get updateCheckTimeout;

  /// No description provided for @updateCheckManifestMissing.
  ///
  /// In en, this message translates to:
  /// **'The {channel} update manifest has not been published on GitHub yet.'**
  String updateCheckManifestMissing(Object channel);

  /// No description provided for @updateChannelAlpha.
  ///
  /// In en, this message translates to:
  /// **'Alpha'**
  String get updateChannelAlpha;

  /// No description provided for @updateChannelBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get updateChannelBeta;

  /// No description provided for @updateChannelStable.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get updateChannelStable;

  /// No description provided for @updateCheckServerFailure.
  ///
  /// In en, this message translates to:
  /// **'GitHub returned a server error. Try again later.'**
  String get updateCheckServerFailure;

  /// No description provided for @updateCheckHttpFailure.
  ///
  /// In en, this message translates to:
  /// **'GitHub rejected the update request. Check that the release is public.'**
  String get updateCheckHttpFailure;

  /// No description provided for @updateCheckInvalidManifest.
  ///
  /// In en, this message translates to:
  /// **'GitHub returned an invalid update manifest.'**
  String get updateCheckInvalidManifest;

  /// No description provided for @updateCheckUnknownFailure.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred while checking for updates.'**
  String get updateCheckUnknownFailure;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @configurationTitle.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configurationTitle;

  /// No description provided for @configurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Export or import appearance and layout preferences. Account data, devices, and firmware cache are excluded.'**
  String get configurationDescription;

  /// No description provided for @configurationExport.
  ///
  /// In en, this message translates to:
  /// **'Export configuration'**
  String get configurationExport;

  /// No description provided for @configurationImport.
  ///
  /// In en, this message translates to:
  /// **'Import configuration'**
  String get configurationImport;

  /// No description provided for @configurationExportSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Configuration exported successfully.'**
  String get configurationExportSucceeded;

  /// No description provided for @configurationImportSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Configuration imported successfully.'**
  String get configurationImportSucceeded;

  /// No description provided for @configurationExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the configuration file.'**
  String get configurationExportFailed;

  /// No description provided for @configurationImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not import the configuration file.'**
  String get configurationImportFailed;

  /// No description provided for @configurationImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'This file is invalid or uses an unsupported configuration version.'**
  String get configurationImportInvalid;

  /// No description provided for @configurationImportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Import configuration?'**
  String get configurationImportConfirmTitle;

  /// No description provided for @configurationImportConfirmDescription.
  ///
  /// In en, this message translates to:
  /// **'Importing this file will overwrite the current configuration.'**
  String get configurationImportConfirmDescription;

  /// No description provided for @configurationMainSidebar.
  ///
  /// In en, this message translates to:
  /// **'Main sidebar'**
  String get configurationMainSidebar;

  /// No description provided for @configurationSettingsSidebar.
  ///
  /// In en, this message translates to:
  /// **'Settings sidebar'**
  String get configurationSettingsSidebar;

  /// No description provided for @configurationContentPane.
  ///
  /// In en, this message translates to:
  /// **'Content pane'**
  String get configurationContentPane;

  /// No description provided for @configurationVisible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get configurationVisible;

  /// No description provided for @configurationCollapsed.
  ///
  /// In en, this message translates to:
  /// **'Collapsed'**
  String get configurationCollapsed;

  /// No description provided for @configurationFileType.
  ///
  /// In en, this message translates to:
  /// **'LilygoBox configuration (JSON)'**
  String get configurationFileType;

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

  /// No description provided for @uptimeDaySingular.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get uptimeDaySingular;

  /// No description provided for @uptimeDayPlural.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String uptimeDayPlural(int days);

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
  /// **'Check for device updates'**
  String get otaCheckTitle;

  /// Firmware update interface: otaUpdateTo
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String otaUpdateTo(String version);

  /// Firmware update interface: otaUpdateFirmware
  ///
  /// In en, this message translates to:
  /// **'Device update'**
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
  /// **'Device update'**
  String get otaDeviceTitle;

  /// Firmware update interface: otaTitle
  ///
  /// In en, this message translates to:
  /// **'Device update'**
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

  /// No description provided for @redownloadUpdate.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get redownloadUpdate;

  /// No description provided for @otaIntegrityFailed.
  ///
  /// In en, this message translates to:
  /// **'{component} failed verification. Download it again to continue. Other verified components will be kept.'**
  String otaIntegrityFailed(String component);

  /// Firmware update interface: otaTransferComplete
  ///
  /// In en, this message translates to:
  /// **'{component} transferred. Waiting for device verification…'**
  String otaTransferComplete(String component);

  /// No description provided for @aiSettingsGroup.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get aiSettingsGroup;

  /// No description provided for @aiProtocolLabel.
  ///
  /// In en, this message translates to:
  /// **'API protocol'**
  String get aiProtocolLabel;

  /// No description provided for @aiProtocolDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the API protocol supported by your provider.'**
  String get aiProtocolDescription;

  /// No description provided for @aiProtocolChatCompletions.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Chat Completions'**
  String get aiProtocolChatCompletions;

  /// No description provided for @aiProtocolResponses.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Responses'**
  String get aiProtocolResponses;

  /// No description provided for @aiCurrentService.
  ///
  /// In en, this message translates to:
  /// **'Current service'**
  String get aiCurrentService;

  /// No description provided for @aiResetEdits.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get aiResetEdits;

  /// No description provided for @aiAvailableActions.
  ///
  /// In en, this message translates to:
  /// **'Available settings actions'**
  String get aiAvailableActions;

  /// No description provided for @aiPermissionTheme.
  ///
  /// In en, this message translates to:
  /// **'Switch application theme'**
  String get aiPermissionTheme;

  /// No description provided for @aiPermissionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change interface language'**
  String get aiPermissionLanguage;

  /// No description provided for @aiPermissionFont.
  ///
  /// In en, this message translates to:
  /// **'Change application font'**
  String get aiPermissionFont;

  /// No description provided for @aiPermissionSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show, hide or resize the main sidebar'**
  String get aiPermissionSidebar;

  /// No description provided for @aiPermissionLayout.
  ///
  /// In en, this message translates to:
  /// **'Resize device panes and the settings sidebar'**
  String get aiPermissionLayout;

  /// No description provided for @aiAddModelService.
  ///
  /// In en, this message translates to:
  /// **'Add model service'**
  String get aiAddModelService;

  /// No description provided for @aiAddedServices.
  ///
  /// In en, this message translates to:
  /// **'Added services'**
  String get aiAddedServices;

  /// No description provided for @aiMoveServiceUp.
  ///
  /// In en, this message translates to:
  /// **'Move service up'**
  String get aiMoveServiceUp;

  /// No description provided for @aiMoveServiceDown.
  ///
  /// In en, this message translates to:
  /// **'Move service down'**
  String get aiMoveServiceDown;

  /// No description provided for @aiNoServices.
  ///
  /// In en, this message translates to:
  /// **'No model services yet. Add a service to get started.'**
  String get aiNoServices;

  /// No description provided for @aiServiceName.
  ///
  /// In en, this message translates to:
  /// **'Service name'**
  String get aiServiceName;

  /// No description provided for @aiServiceNameDescription.
  ///
  /// In en, this message translates to:
  /// **'Identifies this service in the home model selector.'**
  String get aiServiceNameDescription;

  /// No description provided for @aiEditService.
  ///
  /// In en, this message translates to:
  /// **'Edit service'**
  String get aiEditService;

  /// No description provided for @aiSaveService.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get aiSaveService;

  /// No description provided for @aiDeleteService.
  ///
  /// In en, this message translates to:
  /// **'Delete service'**
  String get aiDeleteService;

  /// No description provided for @aiDeleteServiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}” and its local key? Existing chat messages will be kept.'**
  String aiDeleteServiceMessage(String name);

  /// No description provided for @aiModelsHint.
  ///
  /// In en, this message translates to:
  /// **'Enter one model ID per line, or separate with commas. You can enter IDs manually if fetching fails.'**
  String get aiModelsHint;

  /// No description provided for @aiFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch models'**
  String get aiFetchModels;

  /// No description provided for @aiSelectModel.
  ///
  /// In en, this message translates to:
  /// **'Select model'**
  String get aiSelectModel;

  /// No description provided for @aiSearchModels.
  ///
  /// In en, this message translates to:
  /// **'Search models or providers'**
  String get aiSearchModels;

  /// No description provided for @aiSearchModelsDescription.
  ///
  /// In en, this message translates to:
  /// **'Filter by model name or service name.'**
  String get aiSearchModelsDescription;

  /// No description provided for @aiForNextMessages.
  ///
  /// In en, this message translates to:
  /// **'For next messages'**
  String get aiForNextMessages;

  /// No description provided for @aiNoMatchingModels.
  ///
  /// In en, this message translates to:
  /// **'No matching models'**
  String get aiNoMatchingModels;

  /// No description provided for @aiInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTP or HTTPS endpoint without query parameters or credentials.'**
  String get aiInvalidAddress;

  /// No description provided for @aiNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a service name.'**
  String get aiNameRequired;

  /// No description provided for @aiModelsRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one model ID, or fetch the model list.'**
  String get aiModelsRequired;

  /// No description provided for @aiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an API key. A new key is required when changing the service provider or host.'**
  String get aiKeyRequired;

  /// No description provided for @aiStorageError.
  ///
  /// In en, this message translates to:
  /// **'Unable to load or save service settings. Check local storage and try again.'**
  String get aiStorageError;

  /// No description provided for @aiServiceBusy.
  ///
  /// In en, this message translates to:
  /// **'Wait for the current request or resolve pending approvals before changing services.'**
  String get aiServiceBusy;

  /// No description provided for @aiInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The service returned an invalid response. Check its endpoint.'**
  String get aiInvalidResponse;

  /// No description provided for @aiRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to the model service. Check the endpoint, network and API key.'**
  String get aiRequestFailed;

  /// No description provided for @aiRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'The service timed out. Try again later.'**
  String get aiRequestTimeout;

  /// No description provided for @aiCopyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get aiCopyMessage;

  /// No description provided for @aiMessageCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get aiMessageCopied;

  /// No description provided for @aiOpenLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open this link.'**
  String get aiOpenLinkFailed;

  /// No description provided for @aiCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get aiCopyCode;

  /// No description provided for @aiPlainText.
  ///
  /// In en, this message translates to:
  /// **'Plain text'**
  String get aiPlainText;

  /// No description provided for @aiScrollToLatest.
  ///
  /// In en, this message translates to:
  /// **'Scroll to latest message'**
  String get aiScrollToLatest;

  /// No description provided for @aiResponseReasoningEffort.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort: {effort}'**
  String aiResponseReasoningEffort(String effort);

  /// No description provided for @aiReasoningEffort.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get aiReasoningEffort;

  /// No description provided for @aiReasoningNone.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aiReasoningNone;

  /// No description provided for @aiReasoningMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get aiReasoningMinimal;

  /// No description provided for @aiReasoningLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get aiReasoningLow;

  /// No description provided for @aiReasoningMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get aiReasoningMedium;

  /// No description provided for @aiReasoningHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get aiReasoningHigh;

  /// No description provided for @aiReasoningXhigh.
  ///
  /// In en, this message translates to:
  /// **'Extra high'**
  String get aiReasoningXhigh;

  /// No description provided for @aiReasoningMax.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get aiReasoningMax;

  /// No description provided for @aiReasoningUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get aiReasoningUltra;

  /// No description provided for @aiPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get aiPermissions;

  /// No description provided for @aiPermissionRequest.
  ///
  /// In en, this message translates to:
  /// **'Request approval'**
  String get aiPermissionRequest;

  /// No description provided for @aiPermissionCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom permissions'**
  String get aiPermissionCustom;

  /// No description provided for @aiPermissionRequestSummary.
  ///
  /// In en, this message translates to:
  /// **'Ask before restricted actions.'**
  String get aiPermissionRequestSummary;

  /// No description provided for @aiPermissionCustomSummary.
  ///
  /// In en, this message translates to:
  /// **'Set automatic access to webpages and files.'**
  String get aiPermissionCustomSummary;

  /// No description provided for @aiPermissionRequestHelp.
  ///
  /// In en, this message translates to:
  /// **'App settings and public HTTPS pages can be accessed directly. Local file operations require approval unless granted in Custom permissions. Each approval applies only to the displayed operation.'**
  String get aiPermissionRequestHelp;

  /// No description provided for @aiPermissionNetwork.
  ///
  /// In en, this message translates to:
  /// **'Allow webpage access'**
  String get aiPermissionNetwork;

  /// No description provided for @aiPermissionNetworkHelp.
  ///
  /// In en, this message translates to:
  /// **'When off, webpage access requires approval.'**
  String get aiPermissionNetworkHelp;

  /// No description provided for @aiPermissionFiles.
  ///
  /// In en, this message translates to:
  /// **'Default folder access'**
  String get aiPermissionFiles;

  /// No description provided for @aiPermissionDefaultFoldersHelp.
  ///
  /// In en, this message translates to:
  /// **'Initial access for newly added folders.'**
  String get aiPermissionDefaultFoldersHelp;

  /// No description provided for @aiPermissionFolderAccess.
  ///
  /// In en, this message translates to:
  /// **'Folder permissions'**
  String get aiPermissionFolderAccess;

  /// No description provided for @aiPermissionNone.
  ///
  /// In en, this message translates to:
  /// **'Require approval every time'**
  String get aiPermissionNone;

  /// No description provided for @aiPermissionReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Allow reading only'**
  String get aiPermissionReadOnly;

  /// No description provided for @aiPermissionReadWrite.
  ///
  /// In en, this message translates to:
  /// **'Allow reading and editing'**
  String get aiPermissionReadWrite;

  /// No description provided for @aiPermissionFoldersHelp.
  ///
  /// In en, this message translates to:
  /// **'Access is limited to authorized folders and their subfolders. Operations outside this scope still require approval.'**
  String get aiPermissionFoldersHelp;

  /// No description provided for @aiPermissionFolders.
  ///
  /// In en, this message translates to:
  /// **'Authorized folders'**
  String get aiPermissionFolders;

  /// No description provided for @aiPermissionNoFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders added. Every file operation requires approval.'**
  String get aiPermissionNoFolders;

  /// No description provided for @aiPermissionAddFolder.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get aiPermissionAddFolder;

  /// No description provided for @aiPermissionRemoveFolder.
  ///
  /// In en, this message translates to:
  /// **'Remove authorization'**
  String get aiPermissionRemoveFolder;

  /// No description provided for @aiPermissionSessionHelp.
  ///
  /// In en, this message translates to:
  /// **'Permissions apply to this conversation and reset when it is cleared or the app restarts. File contents read by the assistant are sent to your configured model service. Running terminal commands and deleting files are not supported.'**
  String get aiPermissionSessionHelp;

  /// No description provided for @aiAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get aiAwaitingApproval;

  /// No description provided for @aiToolTime.
  ///
  /// In en, this message translates to:
  /// **'Read current time'**
  String get aiToolTime;

  /// No description provided for @aiToolWeb.
  ///
  /// In en, this message translates to:
  /// **'Access webpage'**
  String get aiToolWeb;

  /// No description provided for @aiToolList.
  ///
  /// In en, this message translates to:
  /// **'List directory'**
  String get aiToolList;

  /// No description provided for @aiToolRead.
  ///
  /// In en, this message translates to:
  /// **'Read file'**
  String get aiToolRead;

  /// No description provided for @aiToolWrite.
  ///
  /// In en, this message translates to:
  /// **'Write file'**
  String get aiToolWrite;

  /// No description provided for @aiWritePreview.
  ///
  /// In en, this message translates to:
  /// **'Review the file content before approving'**
  String get aiWritePreview;

  /// No description provided for @aiBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get aiBefore;

  /// No description provided for @aiAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get aiAfter;

  /// No description provided for @aiPermissionResolvedPath.
  ///
  /// In en, this message translates to:
  /// **'Actual target'**
  String get aiPermissionResolvedPath;

  /// No description provided for @aiPermissionFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the folder picker. Please try again.'**
  String get aiPermissionFolderFailed;
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
