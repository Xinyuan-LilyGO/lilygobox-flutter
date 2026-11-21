/*
 * @Description: 自动生成的本地化文件
 */

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aiAverageOutputSpeed => 'Stream speed';

  @override
  String aiOutputTokensPerSecond(String rate) {
    return '$rate tok/s';
  }

  @override
  String get aiAverageOutputSpeedHint =>
      'Estimated from the output received in the last completed reply. Insufficient samples show a dash.';

  @override
  String get githubSignInDialogDescription =>
      'Authorize this app in your browser, then return here to finish signing in. Closing this dialog cancels this sign-in attempt.';

  @override
  String get theme => 'Theme';

  @override
  String get themeDescription => 'Choose your current theme';

  @override
  String get font => 'Font';

  @override
  String get fontDescription =>
      'Choose the application font. System follows the operating system default.';

  @override
  String get fontSystem => 'System default';

  @override
  String get fontInter => 'Inter';

  @override
  String get fontGoogleSansFlex => 'Google Sans Flex';

  @override
  String get fontRoboto => 'Roboto';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get settings => 'Settings';

  @override
  String get moreActions => 'More actions';

  @override
  String get basic => 'Basic';

  @override
  String get general => 'General';

  @override
  String get application => 'Application';

  @override
  String get languageAndRegion => 'Language And Region';

  @override
  String get personalization => 'Personalization';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get copyright => 'Copyright';

  @override
  String get allRightsReserved => '. All rights reserved.';

  @override
  String get addDevice => 'Add Device';

  @override
  String get addDeviceDescription =>
      'You can add development devices here, please select the method to add a development device';

  @override
  String get addByDeviceType => 'Add by device type';

  @override
  String get selectDevice => 'Select Device';

  @override
  String get selectDeviceDescription =>
      'Click below to select the device you want to add';

  @override
  String get searchForDeviceModel => 'Search for device model';

  @override
  String get home => 'Home';

  @override
  String get start => 'Start';

  @override
  String get homePageContentStartTitle => 'Welcome to LilygoBox';

  @override
  String get homePageContentStartDescription =>
      'LilygoBox is an integrated development and control center built specifically for Lilygo hardware.';

  @override
  String get language => 'Language';

  @override
  String get languageAutoDetect => 'Automatic';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languageDescription =>
      'Automatically follow your system language or choose an application interface language.';

  @override
  String get deviceSettings => 'Device Settings';

  @override
  String get homeDeviceCardLabel => 'Device';

  @override
  String get deviceBatteryPageTitle => 'Battery status';

  @override
  String get deviceDetails => 'Device overview';

  @override
  String get deviceControlTab => 'Device controls';

  @override
  String get deviceConnectionTab => 'Device connection';

  @override
  String get deviceInfoTab => 'Device information';

  @override
  String get deviceNameLabel => 'Device name';

  @override
  String get deviceScreenControls => 'Screen controls';

  @override
  String get deviceScreenDisplay => 'Screen display';

  @override
  String get deviceBrightness => 'Brightness';

  @override
  String get deviceSound => 'Device sounds';

  @override
  String get deviceDisplaySettings => 'Display settings';

  @override
  String get deviceControlUnavailable => 'Not supported yet';

  @override
  String get deviceControlsUnavailable =>
      'These controls are not available for this device yet.';

  @override
  String get deviceConnectionStatus => 'Connection status';

  @override
  String get deviceConnectionMethod => 'Connection method';

  @override
  String get deviceSettingsUnavailable =>
      'Settings are not available for this device yet.';

  @override
  String get refresh => 'Refresh';

  @override
  String get delete => 'Delete';

  @override
  String get resetThisSetting => 'Reset this setting';

  @override
  String get controlCenter => 'Control Center';

  @override
  String get sidebarHome => 'Agents';

  @override
  String get deviceManagement => 'Devices';

  @override
  String get assistantTitle => 'Assistant';

  @override
  String get assistantGreeting => 'What can I help you with today?';

  @override
  String get assistantDescription =>
      'Share an idea, or ask the assistant to adjust LilygoBox.';

  @override
  String get aiPromptDevices => 'Show my devices';

  @override
  String get aiPromptAppearance => 'Change the app theme';

  @override
  String get aiPromptLanguage => 'Change the app language';

  @override
  String get aiInputHint => 'Ask a question, or describe a setting to change…';

  @override
  String get aiAttachFile => 'Attach files';

  @override
  String get aiStop => 'Stop generating';

  @override
  String get aiContinue => 'Continue generating';

  @override
  String get aiGuideTurn => 'Add to queue';

  @override
  String get aiGuidanceHint => 'Add a follow-up message…';

  @override
  String get aiGuidancePending => 'Queued messages';

  @override
  String get aiRemoveGuidance => 'Remove queued message';

  @override
  String get aiSendPendingGuidance => 'Steer current turn';

  @override
  String get aiGuidanceAwaitingBoundary => 'Waiting to apply guidance…';

  @override
  String get aiEditQueuedMessage => 'Edit queued message';

  @override
  String get aiSaveQueuedMessage => 'Save changes';

  @override
  String get aiRemoveImage => 'Remove image';

  @override
  String get aiViewOriginal => 'View original image';

  @override
  String get aiImagePreviewFailed => 'Could not load the image.';

  @override
  String get aiSaveImageAs => 'Save image as';

  @override
  String get aiSaveImageFailed => 'Failed to save image. Please try again.';

  @override
  String get aiCopyImage => 'Copy image';

  @override
  String get aiImageUnsupported =>
      'This model is declared text-only. Switch models to send images or continue a conversation containing images. Your draft has been kept.';

  @override
  String get aiCopyImageFailed => 'Could not copy the image. Please try again.';

  @override
  String get aiPasteImageFailed =>
      'Could not read clipboard images. Please try again.';

  @override
  String get aiSend => 'Send message';

  @override
  String get aiClearConversation => 'Clear conversation';

  @override
  String get aiConfigureMessage =>
      'Configure an AI service in Settings to start chatting.';

  @override
  String get aiSetupAction => 'Configure AI service';

  @override
  String get aiAssistantThinking => 'Thinking…';

  @override
  String get aiConnecting => 'Connecting';

  @override
  String get aiAwaitingReply => 'Waiting for the model response';

  @override
  String get aiProcessCompleted => 'Completed';

  @override
  String get aiProcessReasoning => 'Model reasoning';

  @override
  String aiProcessActionSucceeded(String action) {
    return 'Executed: $action';
  }

  @override
  String aiProcessActionFailed(String action) {
    return 'Failed: $action';
  }

  @override
  String get aiStreaming => 'Responding';

  @override
  String get aiPreparingTools => 'Preparing tool calls';

  @override
  String aiRequestRetryRecord(int attempt) {
    return 'Model request retry $attempt';
  }

  @override
  String get aiWebInvalidUrl =>
      'Invalid webpage address. Check the complete URL.';

  @override
  String get aiWebUnsupportedScheme =>
      'Only HTTPS webpages are supported. Provide an HTTPS URL.';

  @override
  String get aiWebUnsupportedPort =>
      'Only the default HTTPS port 443 is supported.';

  @override
  String get aiWebCredentialsNotAllowed =>
      'Webpage URLs cannot contain a username or password.';

  @override
  String get aiWebBlockedAddress =>
      'Local, private, or reserved addresses are blocked. Use a public webpage URL.';

  @override
  String get aiWebDns =>
      'Could not resolve the website hostname. Check the URL or try again later.';

  @override
  String get aiWebConnection =>
      'The connection failed or was interrupted. Check the network and try again.';

  @override
  String get aiWebTimeout => 'Reading the webpage timed out. Try again later.';

  @override
  String get aiWebTls =>
      'Could not establish a secure connection. Check the website certificate and system time.';

  @override
  String get aiWebUnauthorized =>
      'The website requires authentication (HTTP 401). Signed-in access is not supported.';

  @override
  String get aiWebForbidden =>
      'The website refused access (HTTP 403). Check whether the page allows public access.';

  @override
  String get aiWebNotFound =>
      'The webpage was not found (HTTP 404). Check the URL.';

  @override
  String get aiWebRateLimited =>
      'The website rate limit was reached (HTTP 429). Try again later.';

  @override
  String aiWebServerError(int status) {
    return 'The website returned a server error (HTTP $status). Try again later.';
  }

  @override
  String aiWebHttpStatus(int status) {
    return 'The website returned HTTP $status. The page could not be read.';
  }

  @override
  String get aiWebInvalidRedirect =>
      'The website returned a missing or invalid redirect URL. No further request was made.';

  @override
  String get aiWebRedirectLoop =>
      'A redirect loop was detected. Webpage access was stopped.';

  @override
  String get aiWebTooManyRedirects =>
      'The webpage exceeded the limit of 5 redirects. Access was stopped.';

  @override
  String get aiWebContentType =>
      'This URL did not return supported text content. Images and PDFs are not supported.';

  @override
  String get aiWebEncoding =>
      'The webpage uses an unsupported encoding or could not be decoded.';

  @override
  String get aiWebTooLarge =>
      'The webpage exceeds the 1 MiB limit. No partial content was returned.';

  @override
  String get aiWebEmptyContent =>
      'The website returned empty content. No page text was received.';

  @override
  String get aiWebCancelled => 'Webpage access was cancelled.';

  @override
  String get aiAccessingWeb => 'Accessing webpage';

  @override
  String aiWebSucceeded(String url) {
    return 'Accessed webpage $url';
  }

  @override
  String aiWebFailed(String url) {
    return 'Failed to access webpage $url';
  }

  @override
  String get aiExecutingTools => 'Executing tools';

  @override
  String get aiOperationError => 'Error details';

  @override
  String get aiOperationTarget => 'Target';

  @override
  String get aiOperationSummary => 'Outcome';

  @override
  String aiDirectoryListed(String target) {
    return 'Listed directory · $target';
  }

  @override
  String aiFileReadCompleted(String target) {
    return 'Read file · $target';
  }

  @override
  String aiFileWriteCompleted(String target) {
    return 'Wrote file · $target';
  }

  @override
  String get aiTimeReadCompleted => 'Read current time';

  @override
  String get aiWebReadSummary => 'Read the webpage content.';

  @override
  String get aiDirectoryReadSummary => 'Listed the directory entries.';

  @override
  String get aiFileReadSummary => 'Read the file content.';

  @override
  String get aiFileWriteSummary => 'Wrote the content to the target file.';

  @override
  String get aiExecutingListDirectory => 'Listing directory';

  @override
  String get aiExecutingReadFile => 'Reading file';

  @override
  String get aiExecutingWriteFile => 'Writing file';

  @override
  String get aiExecutingReadTime => 'Reading current time';

  @override
  String get aiExecutingSetTheme => 'Changing theme';

  @override
  String get aiExecutingSetLanguage => 'Changing language';

  @override
  String get aiExecutingSetFont => 'Changing font';

  @override
  String get aiExecutingSetSidebarVisibility => 'Changing sidebar visibility';

  @override
  String get aiExecutingSetSidebarWidth => 'Adjusting sidebar width';

  @override
  String get aiExecutingSetContentSplitWidth => 'Adjusting content split width';

  @override
  String aiExecutingNamedTool(String name) {
    return 'Executing $name';
  }

  @override
  String get aiResponseFailed => 'Processing failed';

  @override
  String get aiResponseStopped => 'Stopped';

  @override
  String get aiTurnFailed => 'This turn failed';

  @override
  String aiRetryingRequest(int attempt, int total) {
    return 'Retrying model request ($attempt/$total)';
  }

  @override
  String aiStatusElapsed(String status, String duration) {
    return '$status · $duration';
  }

  @override
  String aiResponseElapsed(String duration) {
    return 'Worked for $duration';
  }

  @override
  String aiResponseModel(String model) {
    return 'Model: $model';
  }

  @override
  String aiThinkingElapsed(String duration) {
    return 'Thinking… $duration';
  }

  @override
  String get aiApprovalTitle => 'Approval required';

  @override
  String aiRequestCountdown(int seconds) {
    return '${seconds}s';
  }

  @override
  String get aiRequestCountdownHint =>
      'Click anywhere on this card to keep it open without a time limit.';

  @override
  String get aiApprovalTimedOut => 'Approval timed out and was denied';

  @override
  String get aiQuestionTimedOut => 'Question timed out and was cancelled';

  @override
  String get aiApprove => 'Allow once';

  @override
  String get aiReject => 'Deny';

  @override
  String get aiActionApproved => 'Approved';

  @override
  String get aiActionRejected => 'Denied';

  @override
  String aiActionTheme(String value) {
    return 'Change theme to $value';
  }

  @override
  String aiActionLanguage(String value) {
    return 'Change language to $value';
  }

  @override
  String aiActionFont(String value) {
    return 'Change font to $value';
  }

  @override
  String get aiActionShowSidebar => 'Show the main sidebar';

  @override
  String get aiActionHideSidebar => 'Hide the main sidebar';

  @override
  String aiActionSidebarWidth(String value) {
    return 'Set main sidebar width to $value px';
  }

  @override
  String aiActionSplitWidth(String value) {
    return 'Set device split width to $value px';
  }

  @override
  String aiActionSettingsWidth(String value) {
    return 'Set settings sidebar width to $value px';
  }

  @override
  String get aiActionUnknown => 'Tool operation';

  @override
  String get aiSearchChatHistory => 'Search original chat history';

  @override
  String get aiReadChatHistory => 'Read original chat message';

  @override
  String aiHistoryMatches(int count) {
    return 'Matching messages returned: $count';
  }

  @override
  String get aiHistoryMessageMissing =>
      'Message not found in this conversation.';

  @override
  String aiHistoryMessageRead(String id) {
    return 'Read message $id';
  }

  @override
  String get aiServiceTitle => 'Model services';

  @override
  String get aiServiceDescription =>
      'Add model services and configure endpoints, keys and models. Keys use this device’s system secure storage.';

  @override
  String get aiProviderLabel => 'Provider';

  @override
  String get aiProviderDescription =>
      'Official providers set the API URL and protocol automatically. Choose Custom to configure them yourself. Switching providers clears the entered key and model list.';

  @override
  String get aiProviderDeepseek => 'DeepSeek (official)';

  @override
  String get aiProviderOpenAi => 'OpenAI (official)';

  @override
  String get aiProviderCustom => 'Custom';

  @override
  String get aiProviderCompatible => 'OpenAI-compatible API';

  @override
  String get aiBaseUrlLabel => 'API URL';

  @override
  String get aiBaseUrlDescription =>
      'Enter the API URL. The client adds the path required by the selected protocol.';

  @override
  String get aiDragService => 'Drag to reorder services';

  @override
  String get aiModelLabel => 'Model';

  @override
  String get aiModelDescription =>
      'Model identifier used by the selected service.';

  @override
  String get aiApiKeyLabel => 'API key';

  @override
  String get aiApiKeyDescription =>
      'The key is saved locally using the operating system secure storage.';

  @override
  String get aiApiKeyStored =>
      'A key is saved securely. Enter a new key to replace it.';

  @override
  String get aiRemoveApiKey => 'Remove saved API key';

  @override
  String get aiSaveAndTest => 'Save and test connection';

  @override
  String get profile => 'Profile';

  @override
  String get notSignedIn => 'Not signed in';

  @override
  String get accountUnavailable =>
      'Accounts are not available yet. You can still use local device features.';

  @override
  String get showSidebar => 'Show sidebar';

  @override
  String get hideSidebar => 'Hide sidebar';

  @override
  String get minimizeWindow => 'Minimize';

  @override
  String get maximizeWindow => 'Maximize';

  @override
  String get restoreWindow => 'Restore';

  @override
  String get closeWindow => 'Close';

  @override
  String get closeSettings => 'Close settings';

  @override
  String get decreaseValue => 'Decrease value';

  @override
  String get increaseValue => 'Increase value';

  @override
  String get homeDevicesSubtitle => 'Your LILYGO devices, all in one place';

  @override
  String get homeDevicesEmpty => 'No devices yet';

  @override
  String get homeDevicesEmptyDescription =>
      'Add your first device\nand bring it into LilygoBox.';

  @override
  String get homeDeviceSearch => 'Search by name or model';

  @override
  String get homeClearSearch => 'Clear search';

  @override
  String get homeDeviceOnline => 'Online';

  @override
  String get homeDeviceOffline => 'Offline';

  @override
  String get homeDeviceConnecting => 'Connecting…';

  @override
  String get homeDevicesNoResults => 'No matching devices';

  @override
  String get back => 'Back';

  @override
  String get connectYourDevice => 'Connect your device';

  @override
  String get discoveryDescription =>
      'Make sure your device is powered on and allows LilygoBox connections, then select the device to connect.';

  @override
  String get discoveredDevices => 'Discovered devices';

  @override
  String get searchingDevices => 'Looking for devices…';

  @override
  String get deleteDevice => 'Delete device';

  @override
  String get deleteDeviceConfirmTitle => 'Delete device?';

  @override
  String deleteDeviceConfirmDescription(String deviceName) {
    return 'This will disconnect from “$deviceName” and remove its settings and pairing information from this computer. Adding it again will require new approval.';
  }

  @override
  String get deleteDeviceSucceeded => 'Device deleted.';

  @override
  String get deleteDeviceFailed =>
      'Unable to delete this device. Please try again.';

  @override
  String get discoveryEmpty => 'No devices found';

  @override
  String get discoveryEmptyDescription =>
      'Make sure your device is powered on and allows app connections.\nFor local network connections, make sure both devices are on the same network.';

  @override
  String get discoveryUnavailable => 'Device discovery unavailable';

  @override
  String get discoveryUnavailableDescription =>
      'Device connections are not available in this version yet.';

  @override
  String get discoveryFailed => 'Unable to find devices';

  @override
  String get discoveryFailedDescription =>
      'The search could not finish. Check your network connection and network access permissions, then try again.';

  @override
  String get searchAgain => 'Search again';

  @override
  String get deviceConnecting => 'Connecting to your device…';

  @override
  String get lanConnectingDescription =>
      'Establishing the connection. Please wait.';

  @override
  String get deviceConnected => 'Device connected';

  @override
  String get deviceConnectionComplete => 'Connection complete';

  @override
  String get backToHome => 'Back to home';

  @override
  String get deviceConnectionFailed => 'Could not connect';

  @override
  String get deviceConnectionFailedDescription =>
      'Could not establish a connection. Make sure the device is online and allows LilygoBox connections, then try again.';

  @override
  String get retryConnection => 'Try again';

  @override
  String get cancelConnection => 'Cancel connection';

  @override
  String get openDevice => 'Open device';

  @override
  String get deviceConnectionHelp => 'Connection help';

  @override
  String get deviceConnectionTroubleshooting => 'Troubleshoot connection';

  @override
  String get closeHelp => 'Close help';

  @override
  String get deviceHelpPreparation => 'Prepare your device';

  @override
  String get deviceHelpPreparationDescription =>
      'Make sure your device is powered on and allows LilygoBox connections. Refer to the instructions for your device.';

  @override
  String get deviceHelpNetwork => 'Check the network';

  @override
  String get deviceHelpNetworkDescription =>
      'For local network connections, connect your computer or phone and the device to the same network. If the device is still not found, check firewall permissions for the app and whether your router blocks communication between devices.';

  @override
  String get deviceHelpApproval => 'Approve the connection';

  @override
  String get deviceHelpApprovalDescription =>
      'Follow the device prompts to approve the first connection. Previously authorized devices usually do not require confirmation again. Adding a deleted device requires new approval.';

  @override
  String get tapToConnect => 'Select to connect';

  @override
  String get resizeSettingsSidebar => 'Resize settings sidebar';

  @override
  String get appearanceSettingsDescription =>
      'Customize the interface with your preferred theme.';

  @override
  String get languageSettingsDescription =>
      'Choose the display language for LilygoBox.';

  @override
  String get generalSettingsDescription =>
      'Manage application preferences and defaults.';

  @override
  String get aboutSettingsDescription => 'Application information and version.';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checkForAppUpdates => 'Check for app updates';

  @override
  String get appUpdateTitle => 'App update';

  @override
  String get appVersion => 'App version';

  @override
  String get downloadAppUpdate => 'Download update';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get installAppUpdate => 'Install update';

  @override
  String get preparingAppUpdate => 'Preparing installer…';

  @override
  String get downloadingAppUpdate => 'Downloading update…';

  @override
  String appUpdateDownloadProgress(Object received, Object total) {
    return '$received MB / $total MB';
  }

  @override
  String get appUpdateDownloaded =>
      'Download complete. The installer passed integrity verification.';

  @override
  String get appUpdateDownloadFailure =>
      'Update download failed. Check your network and free disk space, then retry.';

  @override
  String get appUpdateIntegrityFailure =>
      'The installer size or SHA-256 does not match. Installation was stopped.';

  @override
  String get appUpdateInstallerLaunchFailure =>
      'Could not start the update installer. Try again, or open the downloaded installer manually.';

  @override
  String get checkingForUpdates => 'Checking for updates…';

  @override
  String get upToDate => 'You are up to date';

  @override
  String updateAvailable(Object version) {
    return 'Update available: $version';
  }

  @override
  String get updateCheckFailed => 'Unable to check for updates';

  @override
  String get updateCheckNetworkFailure =>
      'Could not connect to GitHub. Check your network connection or proxy settings.';

  @override
  String get updateCheckTimeout =>
      'The connection to GitHub timed out. Try again later.';

  @override
  String updateCheckManifestMissing(Object channel) {
    return 'The $channel update manifest has not been published on GitHub yet.';
  }

  @override
  String get updateChannelAlpha => 'Alpha';

  @override
  String get updateChannelBeta => 'Beta';

  @override
  String get updateChannelStable => 'Stable';

  @override
  String get updateCheckServerFailure =>
      'GitHub returned a server error. Try again later.';

  @override
  String get updateCheckHttpFailure =>
      'GitHub rejected the update request. Check that the release is public.';

  @override
  String get updateCheckInvalidManifest =>
      'GitHub returned an invalid update manifest.';

  @override
  String get updateCheckUnknownFailure =>
      'An unexpected error occurred while checking for updates.';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get configurationTitle => 'Configuration';

  @override
  String get configurationDescription =>
      'Export or import appearance and layout preferences. Account data, devices, and firmware cache are excluded.';

  @override
  String get configurationExport => 'Export configuration';

  @override
  String get configurationImport => 'Import configuration';

  @override
  String get configurationExportSucceeded =>
      'Configuration exported successfully.';

  @override
  String get configurationImportSucceeded =>
      'Configuration imported successfully.';

  @override
  String get configurationExportFailed =>
      'Could not export the configuration file.';

  @override
  String get configurationImportFailed =>
      'Could not import the configuration file.';

  @override
  String get configurationImportInvalid =>
      'This file is invalid or uses an unsupported configuration version.';

  @override
  String get configurationImportConfirmTitle => 'Import configuration?';

  @override
  String get configurationImportConfirmDescription =>
      'Importing this file will overwrite the current configuration.';

  @override
  String get configurationMainSidebar => 'Main sidebar';

  @override
  String get configurationSettingsSidebar => 'Settings sidebar';

  @override
  String get configurationContentPane => 'Content pane';

  @override
  String get configurationVisible => 'Visible';

  @override
  String get configurationCollapsed => 'Collapsed';

  @override
  String get configurationFileType => 'LilygoBox configuration (JSON)';

  @override
  String get restoreDefaults => 'Restore defaults';

  @override
  String get restoreDefaultsDescription =>
      'Reset application preferences while keeping your account and added devices.';

  @override
  String get restoreDefaultsConfirmTitle => 'Restore default settings?';

  @override
  String get restoreDefaultsConfirmDescription =>
      'The theme will reset to Dark, the language to English, and sidebar layouts to their defaults. Your account and added devices will be kept.';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get profileDescription => 'View and manage your personal profile.';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get githubSignIn => 'Sign in with GitHub';

  @override
  String get githubAccountDescription =>
      'Link your public GitHub profile. Devices and app settings stay on this device.';

  @override
  String get githubRequesting => 'Requesting an authorization code…';

  @override
  String get githubRestoring => 'Checking your session…';

  @override
  String get githubCompleting => 'Finishing sign-in…';

  @override
  String get githubSigningOut => 'Signing out…';

  @override
  String get githubCodeInstructions =>
      'Copy the code below, enter it on GitHub, and approve access. Then return to the app.';

  @override
  String get githubWaiting => 'Waiting for GitHub authorization…';

  @override
  String get githubCopyCode => 'Copy code';

  @override
  String get githubCodeCopied => 'Code copied';

  @override
  String get githubOpenBrowser => 'Open GitHub authorization';

  @override
  String get githubSignOut => 'Sign out';

  @override
  String get githubSignOutConfirmTitle => 'Sign out?';

  @override
  String get githubSignOutDescription =>
      'Signing out removes the saved session on this device. Your GitHub account and local devices are kept. Revoke app access in GitHub authorized application settings.';

  @override
  String get githubNotConfigured =>
      'GitHub sign-in is not configured yet. Local device features are available.';

  @override
  String get githubUnsupported =>
      'GitHub sign-in is not available on this platform yet.';

  @override
  String get githubNetworkError =>
      'Cannot connect to GitHub. Check your connection and try again.';

  @override
  String get githubDenied =>
      'Authorization was declined. You can start sign-in again.';

  @override
  String get githubExpired =>
      'The authorization code or session has expired. Please sign in again.';

  @override
  String get githubConfigurationError =>
      'GitHub sign-in is misconfigured. Please contact the app maintainer.';

  @override
  String get githubRateLimited =>
      'GitHub has limited requests. Please try again later.';

  @override
  String get githubInvalidResponse =>
      'Could not complete GitHub authorization. Please try again later.';

  @override
  String get githubStorageError =>
      'Cannot access secure storage. Check system permissions and try again.';

  @override
  String get githubBrowserError =>
      'Cannot open the browser. Visit https://github.com/login/device and enter the code above.';

  @override
  String get githubRetryRestore => 'Retry session verification';

  @override
  String get githubRetry => 'Retry';

  @override
  String get preferencesReadError =>
      'Local settings could not be read. Defaults are in use and the original settings have not been overwritten. Check folder permissions and retry.';

  @override
  String get preferencesWriteError =>
      'Local settings could not be saved. Changes may be lost after restarting. Check disk space and folder permissions, then retry.';

  @override
  String get preferencesRetry => 'Retry';

  @override
  String get preferencesExitWithoutSaving => 'Exit without saving';

  @override
  String get trayShowWindow => 'Show window';

  @override
  String get trayExit => 'Exit';

  @override
  String get lanOffline => 'Not connected';

  @override
  String get lanModel => 'Model';

  @override
  String get lanModelVersion => 'Model version';

  @override
  String get lanMacAddress => 'MAC address';

  @override
  String get lanIdentityChanged =>
      'The device identity has changed. Connection stopped. If you reset this device, pair it again.';

  @override
  String get lanRepair => 'Pair again';

  @override
  String get lanRepairDescription =>
      'Continue only if you reset this device. This clears its local pairing information. You will need to approve the connection on the device again.';

  @override
  String get lanDeviceId => 'Device ID';

  @override
  String get lanAddress => 'IP address';

  @override
  String get lanFirmware => 'Firmware';

  @override
  String get lanUptime => 'Device uptime';

  @override
  String get uptimeDaySingular => 'day';

  @override
  String uptimeDayPlural(int days) {
    return 'days';
  }

  @override
  String get lanDisconnect => 'Disconnect';

  @override
  String get lanDisconnectConfirmTitle => 'Disconnect device?';

  @override
  String get lanDisconnectDescription =>
      'Your pairing information will be kept. Automatic connection will pause for this session. You can reconnect manually or restart the app to resume automatic connection.';

  @override
  String get lanConnectedDescription =>
      'Connected to the device. Device information is refreshed automatically.';

  @override
  String get lanConfirmOnDevice =>
      'Please allow the connection on your device.';

  @override
  String get lanReconnectDescription =>
      'Make sure your device is online and allows LilygoBox connections, then try again. If you still cannot connect, search for the device again.';

  @override
  String get deviceDashboardSubtitle => 'Screen, sound and device connection';

  @override
  String get deviceDashboardMyDevice => 'Device information';

  @override
  String get deviceDashboardIdentity => 'Model and firmware';

  @override
  String get deviceDashboardViewInfo => 'View device information';

  @override
  String get deviceDashboardBattery => 'Battery';

  @override
  String get deviceDashboardCharging => 'Charging';

  @override
  String get deviceDashboardViewBattery => 'View charge and battery status';

  @override
  String get deviceDashboardSound => 'Sound';

  @override
  String get deviceDisableVibration => 'Disable vibration';

  @override
  String get deviceEnableVibration => 'Enable vibration';

  @override
  String get deviceMute => 'Mute';

  @override
  String get deviceSoundAndHaptics => 'Sound and haptics';

  @override
  String get deviceVibrationIntensity => 'Vibration intensity';

  @override
  String get deviceUnmute => 'Unmute';

  @override
  String get deviceScreenTurnOff => 'Turn screen off';

  @override
  String get deviceScreenTurnOn => 'Turn screen on';

  @override
  String get deviceDashboardScreenOn => 'Screen is on';

  @override
  String get deviceDashboardScreenOff => 'Screen is off';

  @override
  String get deviceDashboardRotation => 'Screen rotation';

  @override
  String get deviceAutoLock => 'Auto lock';

  @override
  String get deviceAutoLockNever => 'Never';

  @override
  String deviceAutoLockSeconds(int seconds) {
    return '$seconds sec';
  }

  @override
  String deviceAutoLockMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get deviceDashboardConnection => 'Device connection';

  @override
  String get deviceInformationTitle => 'Device information';

  @override
  String get deviceInformationIdentity => 'LilygoBox device';

  @override
  String get deviceInformationConnection => 'Device connection';

  @override
  String get deviceInformationView => 'View';

  @override
  String get connectionReady => 'Connection ready';

  @override
  String get connectionThisComputer => 'This computer';

  @override
  String get connectionInformation => 'Connection information';

  @override
  String get connectionStatus => 'Connection status';

  @override
  String get connectionMethod => 'Connection method';

  @override
  String get connectionManage => 'Manage connection';

  @override
  String get connectionManualRecovery =>
      'After disconnecting manually, select Reconnect to restore the connection.';

  @override
  String get connectionCredentialTitle => 'Connection credentials';

  @override
  String get connectionCredentialDescription =>
      'Credentials are saved after initial authorization, so reconnecting does not require approval again. Disconnecting keeps them; deleting the device removes its locally saved credentials.';

  @override
  String get deviceConnectionStatusTitle => 'Device status';

  @override
  String get deviceBatteryUnknown => 'Unknown';

  @override
  String get deviceBatteryFull => 'Fully charged';

  @override
  String get deviceBatteryChargingState => 'Charging';

  @override
  String get deviceBatteryPowerState => 'On battery';

  @override
  String get deviceBatteryOffline => 'Device not connected';

  @override
  String get deviceBatteryNoData => 'No battery data';

  @override
  String get deviceBatteryChargerConnected => 'Charger connected';

  @override
  String get deviceBatteryNotCharging => 'Not charging';

  @override
  String get deviceBatteryVoltage => 'Voltage';

  @override
  String get deviceBatteryTemperature => 'Temperature';

  @override
  String get deviceBatteryChargingStatus => 'Charging status';

  @override
  String get deviceBatteryCurrent => 'Current';

  @override
  String get deviceRotationConfirmTitle => 'Change display orientation?';

  @override
  String get deviceRotationConfirmDescription =>
      'Rotating will close the current page on the device and return to its home screen. Unsaved changes will be discarded. If the device is locked, it will stay locked.';

  @override
  String get deviceRotationConfirmAction => 'Rotate';

  @override
  String get deviceBatteryHealth => 'Battery health';

  @override
  String get deviceBatteryTimeToFull => 'Estimated time to full';

  @override
  String get deviceBatteryTimeToEmpty => 'Estimated battery runtime';

  @override
  String deviceBatteryDuration(int hours, int minutes) {
    return '$hours hr $minutes min';
  }

  @override
  String get deviceBatteryCapacity => 'Rated battery capacity';

  @override
  String get deviceBatteryCapacityEdit => 'Edit';

  @override
  String get deviceBatteryCapacityDescription =>
      'Enter the rated capacity in mAh. This setting is saved on the device and used for battery and runtime estimates; it is not the remaining capacity.';

  @override
  String deviceBatteryCapacityRange(int minimum, int maximum) {
    return 'Range: $minimum–$maximum mAh';
  }

  @override
  String get deviceBatteryCapacityInvalid =>
      'Enter a whole-number capacity within the range.';

  @override
  String get deviceBatteryCapacitySaveFailed =>
      'Could not save. Check the device connection and try again.';

  @override
  String get deviceBatteryCapacitySaving => 'Saving…';

  @override
  String get deviceBatteryCapacitySave => 'Save';

  @override
  String deviceBatteryEstimateMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String deviceBatteryEstimateToFull(String duration) {
    return '$duration to full';
  }

  @override
  String deviceBatteryEstimateRemaining(Object duration) {
    return '$duration remaining';
  }

  @override
  String get deviceBatteryLevel => 'Battery level';

  @override
  String get deviceWifiSignal => 'Wi-Fi signal';

  @override
  String get deviceNameEditDescription =>
      'Enter a device name (up to 64 UTF-8 bytes). The name is saved on the device.';

  @override
  String get deviceNameInvalid =>
      'Enter a non-empty name within 64 UTF-8 bytes, without control characters.';

  @override
  String get deviceNameSaveFailed =>
      'Could not save the name. Check the device connection and try again.';

  @override
  String get deviceNameStorageFailed =>
      'The device could not save the name to storage. Your input has been kept; please try again.';

  @override
  String get otaUpdating => 'Updating';

  @override
  String get otaCheck => 'Check for updates';

  @override
  String get otaNewVersion => 'Update available';

  @override
  String get otaViewStatus => 'View device update status';

  @override
  String get otaCheckTitle => 'Check for device updates';

  @override
  String otaUpdateTo(String version) {
    return 'Update to $version';
  }

  @override
  String get otaUpdateFirmware => 'Device update';

  @override
  String get otaWirelessVersion => 'Wireless firmware version';

  @override
  String get otaMainVersion => 'Main firmware version';

  @override
  String get otaUnknown => 'Unknown';

  @override
  String get otaCheckDisconnected =>
      'The device disconnected or changed. Reconnect before checking for updates.';

  @override
  String get otaCheckTimeout =>
      'The update check timed out. Check your network and try again.';

  @override
  String get otaManifestMissing =>
      'No OTA manifest was found for this device (HTTP 404).';

  @override
  String get otaManifestTimeout =>
      'The OTA manifest request timed out. Check your network and try again.';

  @override
  String get otaManifestIncompatible =>
      'The OTA manifest does not match this device model, hardware version, or chip.';

  @override
  String get otaManifestNetwork =>
      'Could not retrieve the OTA manifest. Check your network and try again.';

  @override
  String otaCheckError(String detail) {
    return 'Could not check for updates: $detail';
  }

  @override
  String get otaCheckFailed => 'Update check failed';

  @override
  String get otaChecking => 'Checking for updates…';

  @override
  String get otaLatest => 'You are up to date';

  @override
  String get otaCancel => 'Cancel';

  @override
  String get otaClose => 'Close';

  @override
  String get otaRetry => 'Retry';

  @override
  String get otaFound => 'Firmware update available';

  @override
  String get otaDeviceTitle => 'Device update';

  @override
  String get otaTitle => 'Device update';

  @override
  String get otaRemoteSource =>
      'Device online update · Closing this window does not stop the device task';

  @override
  String get otaLocalSource =>
      'LAN update · Firmware is provided by the app that started the update';

  @override
  String get otaDeviceCacheHint =>
      'The device already has all firmware required for this update. It can verify the files again and prepare installation.';

  @override
  String get otaCacheChecking =>
      'Verifying firmware downloaded on this computer…';

  @override
  String otaAppCacheHint(String components) {
    return 'Downloaded and verified: $components. Use these files and download any missing components.';
  }

  @override
  String get otaMainComponent => 'Main firmware';

  @override
  String get otaWirelessComponent => 'Wireless firmware';

  @override
  String get otaComponentsSeparator => ', ';

  @override
  String get otaCancelling => 'Cancelling update…';

  @override
  String get otaCancelUpdate => 'Cancel update';

  @override
  String get otaRedownload => 'Download again';

  @override
  String get otaUseDeviceCache => 'Use device firmware';

  @override
  String get otaUseCache => 'Use downloaded firmware';

  @override
  String get otaDownloadUpdate => 'Download update';

  @override
  String get otaInstall => 'Restart and install';

  @override
  String get otaDownloadingMain => 'Downloading main firmware';

  @override
  String get otaDownloadingWireless => 'Downloading wireless firmware';

  @override
  String get otaRequestCache =>
      'Requesting verification of firmware already on the device…';

  @override
  String get otaCacheTimeout => 'Device firmware cache verification timed out.';

  @override
  String get otaCacheRejected =>
      'The device did not accept the cached firmware. Try again or download the files again.';

  @override
  String otaCacheFailed(String detail) {
    return 'Could not use the device firmware cache: $detail';
  }

  @override
  String get otaDownloadTimeout => 'The download timed out. Please try again.';

  @override
  String otaDownloadFailed(String detail) {
    return 'Firmware download or verification failed: $detail';
  }

  @override
  String get otaWaitingTransfer =>
      'Waiting for the device to accept the transfer…';

  @override
  String get otaTransferTimeout => 'Firmware transfer to the device timed out.';

  @override
  String get otaTransferRejected =>
      'The device did not accept the transfer. Make sure its firmware supports staged updates.';

  @override
  String otaTransferFailed(String detail) {
    return 'Could not transfer firmware: $detail';
  }

  @override
  String get otaRequestInstall =>
      'Requesting restart and installation…\nYou may close this window. Do not turn off the device.';

  @override
  String get otaInstallRejected =>
      'The device did not confirm restart and installation.';

  @override
  String get otaInstallConfirmed =>
      'Restart and installation confirmed. The device will install automatically and restart. Do not turn it off.';

  @override
  String get otaDeviceChanged =>
      'The selected device changed. This update has stopped.';

  @override
  String get otaInstallDisconnected =>
      'The device disconnected. Waiting for confirmation of restart and installation…';

  @override
  String get otaObserverDisconnected =>
      'The device disconnected. Reconnect to view its update status.';

  @override
  String get otaDisconnected =>
      'The device disconnected. The update has stopped.';

  @override
  String get otaTaskChanged =>
      'The device update task changed. Reopen the update window.';

  @override
  String get otaOtherTask =>
      'The device is already updating. Close this window to view its current task.';

  @override
  String get otaLatestComplete => 'You are up to date.';

  @override
  String get otaCheckAvailable =>
      'An update is available. Start the download on the device or close this window to choose it in the app.';

  @override
  String get otaNoTask => 'The device has no update task in progress.';

  @override
  String otaDeviceFailed(String detail) {
    return 'The device update failed: $detail';
  }

  @override
  String get otaDeviceCancelled =>
      'The device cancelled the update and kept its current firmware.';

  @override
  String get otaPrepared =>
      'Firmware received and verified. Select Restart and install to turn off the device screen, install the update, and restart automatically.';

  @override
  String get otaPreparedOtherApp =>
      'Firmware is ready. Confirm restart and installation in the app that started the update.';

  @override
  String get otaInstalling =>
      'The device is installing and restarting. Do not turn it off.\nClosing this window does not stop installation.';

  @override
  String get otaDeviceChecking =>
      'The device is checking for firmware updates online…';

  @override
  String get otaPaused =>
      'The device paused the download. Resume it on the device or cancel this update.';

  @override
  String get otaVerifyingMain =>
      'The device is verifying the main firmware image and SHA-256…';

  @override
  String get otaVerifyingWireless =>
      'The device is verifying the wireless firmware image and SHA-256…';

  @override
  String get otaPreparing =>
      'The device is preparing firmware for installation…';

  @override
  String get otaCancelled =>
      'Update cancelled. The current firmware has been kept.';

  @override
  String get otaCancelRejected =>
      'The device rejected cancellation of this task.';

  @override
  String otaCancelUnconfirmed(String detail) {
    return 'The device did not confirm cancellation: $detail';
  }

  @override
  String otaProgress(String action, String received, String total) {
    return '$action · $received / $total';
  }

  @override
  String get otaDownloadMain => 'Download main firmware';

  @override
  String get otaDownloadWireless => 'Download wireless firmware';

  @override
  String get otaDeviceDownloadMain => 'Device downloading main firmware';

  @override
  String get otaDeviceDownloadWireless =>
      'Device downloading wireless firmware';

  @override
  String get otaTransferMain => 'Transfer main firmware';

  @override
  String get otaTransferWireless => 'Transfer wireless firmware';

  @override
  String otaAwaitingProgress(String action) {
    return '$action · Waiting for device progress';
  }

  @override
  String otaDownloadComplete(String component) {
    return '$component downloaded. Waiting for device verification…';
  }

  @override
  String get redownloadUpdate => 'Download again';

  @override
  String otaIntegrityFailed(String component) {
    return '$component failed verification. Download it again to continue. Other verified components will be kept.';
  }

  @override
  String otaTransferComplete(String component) {
    return '$component transferred. Waiting for device verification…';
  }

  @override
  String get aiSettingsGroup => 'Agents';

  @override
  String get aiProtocolLabel => 'API protocol';

  @override
  String get aiProtocolDescription =>
      'Choose the API protocol supported by your provider.';

  @override
  String get aiProtocolChatCompletions => 'OpenAI Chat Completions';

  @override
  String get aiProtocolResponses => 'OpenAI Responses';

  @override
  String get aiCurrentService => 'Current service';

  @override
  String get aiResetEdits => 'Revert';

  @override
  String get aiAvailableActions => 'Available settings actions';

  @override
  String get aiPermissionTheme => 'Switch application theme';

  @override
  String get aiPermissionLanguage => 'Change interface language';

  @override
  String get aiPermissionFont => 'Change application font';

  @override
  String get aiPermissionSidebar => 'Show, hide or resize the main sidebar';

  @override
  String get aiPermissionLayout =>
      'Resize device panes and the settings sidebar';

  @override
  String get aiAddModelService => 'Add model service';

  @override
  String get aiAddedServices => 'Added services';

  @override
  String get aiMoveServiceUp => 'Move service up';

  @override
  String get aiMoveServiceDown => 'Move service down';

  @override
  String get aiNoServices =>
      'No model services yet. Add a service to get started.';

  @override
  String get aiCreateRequiresServiceTitle => 'Configure a model service first';

  @override
  String get aiCreateRequiresServiceDescription =>
      'Creating an agent requires an available model service. Add a service, enter its API key, and configure at least one model.';

  @override
  String get aiGoToModelSettings => 'Go to settings';

  @override
  String get aiServiceName => 'Service name';

  @override
  String get aiServiceNameDescription =>
      'Identifies this service in the home model selector.';

  @override
  String get aiEditService => 'Edit service';

  @override
  String get aiSaveService => 'Save';

  @override
  String get aiDeleteService => 'Delete service';

  @override
  String aiDeleteServiceMessage(String name) {
    return 'Delete “$name” and its local key? Existing chat messages will be kept.';
  }

  @override
  String get aiModelsHint =>
      'Enter one model ID per line, or separate with commas. You can enter IDs manually if fetching fails.';

  @override
  String get aiFetchModels => 'Fetch models';

  @override
  String get aiSelectModel => 'Select model';

  @override
  String get aiSearchModels => 'Search models or providers';

  @override
  String get aiSearchModelsDescription =>
      'Filter by model name or service name.';

  @override
  String get aiForNextMessages => 'For next messages';

  @override
  String get aiNoMatchingModels => 'No matching models';

  @override
  String get aiInvalidAddress =>
      'Enter a valid HTTP or HTTPS endpoint without query parameters or credentials.';

  @override
  String get aiNameRequired => 'Enter a service name.';

  @override
  String get aiModelsRequired =>
      'Enter at least one model ID, or fetch the model list.';

  @override
  String get aiKeyRequired =>
      'Enter an API key. A new key is required when changing the service provider or host.';

  @override
  String get aiStorageError =>
      'Unable to load or save service settings. Check local storage and try again.';

  @override
  String get aiServiceBusy =>
      'Wait for the current request or resolve pending approvals before changing services.';

  @override
  String get aiInvalidResponse =>
      'The service returned an invalid response. Check its endpoint.';

  @override
  String get aiRequestFailed =>
      'Unable to connect to the model service. Check the endpoint, network and API key.';

  @override
  String get aiRequestTimeout => 'The service timed out. Try again later.';

  @override
  String get aiCopyMessage => 'Copy message';

  @override
  String get aiMessageCopied => 'Copied';

  @override
  String get aiTaskLinkUnavailable =>
      'This agent has been deleted or cannot be opened here.';

  @override
  String get aiOpenLinkFailed => 'Unable to open this link.';

  @override
  String get aiCopyCode => 'Copy code';

  @override
  String get aiEnableCodeWrap => 'Enable word wrap';

  @override
  String get aiDisableCodeWrap => 'Disable word wrap';

  @override
  String get aiPlainText => 'Plain text';

  @override
  String get aiScrollToLatest => 'Scroll to latest message';

  @override
  String aiResponseReasoningEffort(String effort) {
    return 'Reasoning effort: $effort';
  }

  @override
  String get aiReasoningEffort => 'Reasoning effort';

  @override
  String get aiReasoningNone => 'Off';

  @override
  String get aiReasoningMinimal => 'Minimal';

  @override
  String get aiReasoningLow => 'Low';

  @override
  String get aiReasoningMedium => 'Medium';

  @override
  String get aiReasoningHigh => 'High';

  @override
  String get aiReasoningXhigh => 'Extra high';

  @override
  String get aiReasoningMax => 'Maximum';

  @override
  String get aiReasoningUltra => 'Ultra';

  @override
  String get aiPermissions => 'Permissions';

  @override
  String get aiPermissionRequest => 'Manual approval';

  @override
  String get aiPermissionAutomatic => 'Automatic approval';

  @override
  String get aiPermissionAutomaticSummary => 'Model approves eligible actions.';

  @override
  String get aiPermissionApprovalModel => 'Approval model';

  @override
  String aiPermissionApprovalModelNotUsed(String model) {
    return 'Configured approval model: $model (not called)';
  }

  @override
  String get aiPermissionApprovalModelHelp =>
      'Defaults to the current chat model. The model uses this turn’s request and target path to decide whether to allow eligible actions. Actions it does not approve are blocked without a manual prompt.';

  @override
  String aiAuxiliaryModelUnavailable(String model) {
    return 'Unavailable: $model';
  }

  @override
  String get aiPermissionCustom => 'Custom approval';

  @override
  String get aiPermissionRequestSummary => 'Confirm each restricted action.';

  @override
  String get aiPermissionCustomSummary => 'Follow your approval rules.';

  @override
  String get aiPermissionRequestHelp =>
      'App settings and public HTTPS pages can be accessed directly. Local file operations require approval unless granted in Custom approval. Each approval applies only to the displayed operation.';

  @override
  String get aiPermissionNetwork => 'Allow network access';

  @override
  String get aiPermissionNetworkHelp =>
      'Allow web access. Ask for approval when disabled.';

  @override
  String get aiPermissionFiles => 'Default access for newly added folders';

  @override
  String get aiPermissionFolderAccess => 'Folder permissions';

  @override
  String get aiPermissionNone => 'Require approval every time';

  @override
  String get aiPermissionReadOnly => 'Allow reading only';

  @override
  String get aiPermissionReadWrite => 'Allow reading and editing';

  @override
  String get aiPermissionFoldersHelp =>
      'Access is limited to authorized folders and their subfolders. Operations outside this scope still require approval.';

  @override
  String get aiPermissionFolders => 'Authorized folders';

  @override
  String get aiPermissionNoFolders =>
      'No folders added. Every file operation requires approval.';

  @override
  String get aiPermissionAddFolder => 'Add folder';

  @override
  String get aiPermissionRemoveFolder => 'Remove authorization';

  @override
  String get aiPermissionSessionHelp =>
      'The approval mode and custom rules are saved for this agent and reset when the conversation is cleared. File contents and command output may be sent to the configured model service. Local commands are not sandboxed and can access files, networks and devices.';

  @override
  String get aiAwaitingApproval => 'Waiting for approval';

  @override
  String get aiManualApprovalGranted => 'Manually approved';

  @override
  String get aiManualApprovalDenied => 'Manually denied';

  @override
  String get aiManualApprovalCancelled => 'Manual approval cancelled';

  @override
  String get aiManualApprovalTimedOut => 'Manual approval timed out';

  @override
  String get aiCustomApprovalGranted => 'Allowed by custom rules';

  @override
  String get aiCustomApprovalNotGranted =>
      'Not allowed directly by custom rules';

  @override
  String get aiPermissionReviewing => 'Checking for automatic approval';

  @override
  String get aiPermissionReviewApproved => 'Approved automatically';

  @override
  String get aiPermissionReviewDenied => 'Denied by the approval model';

  @override
  String get aiPermissionReviewFailed => 'Automatic approval failed';

  @override
  String get aiPermissionReviewSkipped => 'Not eligible for automatic approval';

  @override
  String get aiPermissionReviewCancelled => 'Automatic approval cancelled';

  @override
  String get aiToolTime => 'Read current time';

  @override
  String get aiToolWeb => 'Access webpage';

  @override
  String get aiToolList => 'List directory';

  @override
  String get aiToolRead => 'Read file';

  @override
  String get aiToolWrite => 'Write file';

  @override
  String get aiWritePreview => 'Review the file content before approving';

  @override
  String get aiBefore => 'Before';

  @override
  String get aiAfter => 'After';

  @override
  String get aiPermissionResolvedPath => 'Actual target';

  @override
  String get aiPermissionFolderFailed =>
      'Unable to open the folder picker. Please try again.';

  @override
  String get aiPermissionCommandNoApproval => 'Command approval bypass';

  @override
  String get aiPermissionCommandNoApprovalHelp =>
      'Run commands without requesting approval.';

  @override
  String get aiPermissionFullFilesWarningTitle => 'Allow access to all files?';

  @override
  String get aiPermissionFullFilesWarningDescription =>
      'Within system permissions, this allows reading, creating, modifying or deleting any local file, without folder restrictions.\n\nThis may cause loss of important files or disclosure of sensitive information.';

  @override
  String get aiPermissionCommandNoApprovalWarningTitle =>
      'Run commands without approval?';

  @override
  String get aiPermissionCommandNoApprovalWarningDescription =>
      'Complex scripts and commands flagged as risky will run without approval. Explicitly forbidden commands remain blocked.\n\nCommands and their child processes may modify or delete files, access the network and change system settings, causing data loss or disclosure.';

  @override
  String get aiPermissionWarningFooter =>
      'Enable this only for agents you trust. You can turn it off at any time.';

  @override
  String get aiPermissionWarningConfirm => 'Confirm and enable';

  @override
  String get aiShowApiKey => 'Show API key';

  @override
  String get aiHideApiKey => 'Hide API key';

  @override
  String get aiQuestionTitle => 'Input needed';

  @override
  String get aiAwaitingUserInput => 'Waiting for your answer';

  @override
  String get aiAskUser => 'Ask a question';

  @override
  String get aiQuestionAnswered => 'Answers received';

  @override
  String get aiQuestionCancelled => 'Question cancelled';

  @override
  String get aiQuestionAnswerDetails => 'Questions and answers';

  @override
  String get aiQuestionAnswerLabel => 'Answer';

  @override
  String get aiQuestionNote => 'Add details or enter your own answer';

  @override
  String get aiQuestionSubmit => 'Submit answers';

  @override
  String get aiQuestionCancel => 'Cancel';

  @override
  String get aiQuestionChoose => 'Choose an option or enter an answer.';

  @override
  String get aiPermissionExecution => 'Allow running local commands';

  @override
  String get aiPermissionExecutionHelp =>
      'Allow commands and programs to run on this computer.';

  @override
  String get aiPermissionFullFiles => 'Allow access to all files';

  @override
  String get aiPermissionFullFilesHelp =>
      'Allow access to local files without folder grants, within system permissions.';

  @override
  String get aiCommandNoticeTitle => 'Risk notice';

  @override
  String get aiCommandApprovalNotice =>
      'Commands are not sandboxed. Approval covers only this command and its child processes.';

  @override
  String get aiCommandReason => 'Purpose';

  @override
  String get aiCommandArguments => 'Arguments';

  @override
  String get aiCommandDirectory => 'Working directory';

  @override
  String get aiToolCommand => 'Run local command';

  @override
  String get aiToolProcessRead => 'Read process output';

  @override
  String get aiToolProcessInput => 'Send process input';

  @override
  String get aiToolProcessStop => 'Stop process';

  @override
  String get aiToolEnvironment => 'Inspect execution environment';

  @override
  String get aiCommandSafetyTitle => 'Command needs confirmation';

  @override
  String get aiCommandRiskForceDelete =>
      'This command includes forced or recursive deletion and may permanently delete files.';

  @override
  String get aiCommandRiskDiscardChanges =>
      'This command may discard local file changes.';

  @override
  String get aiCommandRiskDiskWrite =>
      'This command may modify disks or partitions and cause data loss.';

  @override
  String get aiCommandRiskOpaqueScript =>
      'Contains a script or dynamic expressions whose behavior cannot be fully predicted.';

  @override
  String get aiCommandRulePrompt =>
      'A command rule requires approval for this call.';

  @override
  String get aiCommandMatchedRules => 'Matched rules';

  @override
  String get aiCommandPolicyForbidden =>
      'A forbidden rule blocked this command. It was not executed.';

  @override
  String get aiCommandPolicyInvalidRules =>
      'Command rules could not be read or validated. The command was not executed. Check command-rules.json.';

  @override
  String get aiCommandPolicyApprovalRequired =>
      'This command requires approval and was not executed.';

  @override
  String get aiCommandPolicyChanged =>
      'Command rules changed while this call was pending. The command was not executed; submit it again for review.';

  @override
  String aiCommandStarted(String target) {
    return 'Process started · $target';
  }

  @override
  String aiCommandFinished(String target) {
    return 'Command completed · $target';
  }

  @override
  String aiCommandFailed(String target) {
    return 'Command failed · $target';
  }

  @override
  String aiCommandTimedOut(String target) {
    return 'Command timed out · $target';
  }

  @override
  String aiProcessStoppedLabel(String target) {
    return 'Process stopped · $target';
  }

  @override
  String aiProcessOutputRead(String target) {
    return 'Read process output · $target';
  }

  @override
  String get aiProcessRunningSummary => 'The process is still running.';

  @override
  String aiProcessExitedSummary(int code) {
    return 'The process exited with code $code.';
  }

  @override
  String get aiProcessTimedOutSummary =>
      'Execution timed out. Process termination was requested.';

  @override
  String get aiProcessStoppedSummary => 'The process has stopped.';

  @override
  String get aiProcessStoppingSummary =>
      'Stop requested. Waiting for the process to exit.';

  @override
  String get aiProcessInputSentSummary => 'Input was sent to the process.';

  @override
  String aiCommandStopping(String target) {
    return 'Stopping process · $target';
  }

  @override
  String get aiCommandFull => 'Full command';

  @override
  String get aiServiceConfiguration => 'Model service configuration';

  @override
  String get aiServiceConfigurationHelp =>
      'Back up services and models separately. Exported files contain plaintext API keys; keep them secure.';

  @override
  String get aiServiceConfigurationFileType =>
      'LilygoBox model service configuration (JSON)';

  @override
  String get aiServiceConfigurationImportTitle =>
      'Import model service configuration?';

  @override
  String get aiServiceConfigurationImportHelp =>
      'Matching service IDs and their keys will be updated. New services will be added; other existing services will be kept.';

  @override
  String get aiServiceConfigurationInvalid =>
      'This file is invalid or is not a supported model service configuration.';

  @override
  String get aiAddedServicesHelp => 'Add, edit or delete model services.';

  @override
  String get aiWorkspaceTitle => 'Agents';

  @override
  String get aiWorkspaceDescription =>
      'Create independent agents, follow their progress, or continue a conversation.';

  @override
  String get aiWorkspaceCreate => 'New agent';

  @override
  String get aiWorkspaceEmptyTitle => 'No child agents yet';

  @override
  String get aiWorkspaceEmptyDescription =>
      'Create an agent here or ask the main agent to create a child.';

  @override
  String get aiWorkspaceTaskTitle => 'Agent name';

  @override
  String get aiWorkspaceTaskPrompt => 'Work instructions';

  @override
  String get aiWorkspaceCreateDescription =>
      'Work independently using the current service and model.';

  @override
  String get aiWorkspaceRunning => 'Running';

  @override
  String get aiWorkspaceCompleted => 'Completed';

  @override
  String get aiWorkspaceNeedsApproval => 'Awaiting approval';

  @override
  String get aiWorkspaceNeedsAnswer => 'Awaiting answer';

  @override
  String get aiWorkspaceFailed => 'Failed';

  @override
  String get aiWorkspaceStopped => 'Stopped';

  @override
  String get aiWorkspaceIdle => 'Not started';

  @override
  String get aiWorkspaceOpenMain => 'Back to main agent';

  @override
  String get aiWorkspaceStop => 'Stop agent';

  @override
  String get aiWorkspaceTaskRequired => 'Enter the work instructions.';

  @override
  String get aiWorkspaceOpenAction => 'Open agent';

  @override
  String get aiWorkspaceSpawnAction => 'Create child agent';

  @override
  String get aiWorkspaceConfigureAction => 'Configure child agent model';

  @override
  String get aiWorkspaceSendAction => 'Send agent message';

  @override
  String get aiWorkspaceConnectAction => 'Connect agents';

  @override
  String get aiWorkspaceDisconnectAction => 'Disconnect agents';

  @override
  String get aiModelDiscoveryLoading => 'Reading model list…';

  @override
  String get aiModelDiscoveryCancel => 'Cancel reading';

  @override
  String get aiModelDiscoveryEmpty =>
      'The service returned no available models.';

  @override
  String get aiModelDiscoveryUnchanged =>
      'No new models. Your existing list is unchanged.';

  @override
  String get aiModelDiscoveryNewModels => 'Select new models to add';

  @override
  String get aiModelDiscoveryAdd => 'Add selected models';

  @override
  String get aiModelDiscoveryUpdate => 'Update model information';

  @override
  String aiModelDiscoverySummary(int total, int added, int existing) {
    return 'Found $total models: $added new, $existing already listed.';
  }

  @override
  String get aiWorkspaceWaitAction => 'Wait for child agents';

  @override
  String get aiWorkspaceListAction => 'List child agents';

  @override
  String get aiWorkspaceStopAction => 'Stop child agent';

  @override
  String get aiTopologyTitle => 'Agent workflow';

  @override
  String get aiTopologyLoading => 'Loading agents…';

  @override
  String get aiTopologyRestoring => 'Restoring agents…';

  @override
  String get agentStorageTransferChecksumming => 'Checking data integrity';

  @override
  String get aiTopologyRestoreFailed => 'Could not load the saved agents.';

  @override
  String get aiTopologyDescription =>
      'Connect agents at every level and collaborate.';

  @override
  String get aiTopologyCreatePrimary => 'Create main agent';

  @override
  String get aiTopologyCreateChild => 'Add child agent';

  @override
  String get aiTopologyPrimary => 'Main agent';

  @override
  String get aiTopologyPermanent => 'Child agent';

  @override
  String get aiTopologyClosed => 'Closed';

  @override
  String get aiTopologyOpen => 'Open conversation';

  @override
  String get aiTopologyInspect => 'Inspect activity';

  @override
  String get aiTopologyBack => 'Back to agent workflow';

  @override
  String get aiTopologyCopyWorkflow => 'Copy agent workflow';

  @override
  String get aiTopologyPasteAgent => 'Paste agent';

  @override
  String get aiTopologyPasteWorkflow => 'Paste agent workflow';

  @override
  String get aiTopologyDuplicate => 'Copy agent';

  @override
  String get aiTopologyRenameHelp =>
      'Identify this agent on the canvas and in conversations. Line breaks are supported.';

  @override
  String get aiTopologyNameOptional => 'Agent name (optional)';

  @override
  String get aiTopologyTaskContentRequired => 'Enter the work instructions.';

  @override
  String get aiTopologyNameHelp =>
      'Leave blank to generate a name from the work instructions.';

  @override
  String get aiTopologyModelHelp =>
      'Choose the service and model for this agent.';

  @override
  String get aiTopologyPermissionsHelp =>
      'Set the operations this agent is allowed to perform.';

  @override
  String get aiTopologyTaskHelp =>
      'Describe the goal and necessary context. Execution starts after creation.';

  @override
  String get aiTopologyParentLabel => 'Parent agent';

  @override
  String get aiTopologyBringToFront => 'Bring to front';

  @override
  String get aiTopologyRename => 'Rename';

  @override
  String get aiTopologyMakeRootTitle => 'Make this agent a main agent?';

  @override
  String aiTopologyMakeRootHelp(String task) {
    return '“$task” will become a main agent and disconnect from its previous agent group. Its conversation, descendants, and connections within its subtree will remain.';
  }

  @override
  String get aiTopologyMergeTitle => 'Change agent ownership?';

  @override
  String aiTopologyMergeRootHelp(String task, String parent) {
    return 'Main agent “$task” will become a child of “$parent”. Descendants, conversations, and internal connections remain; communication links across the branch boundary will be disconnected.';
  }

  @override
  String aiTopologyMergeChildHelp(String task, String parent) {
    return '“$task” and its descendants will disconnect from the current parent and move under “$parent”. Other agents in the original group stay in place. Conversations and internal connections remain; communication links across the branch boundary will be disconnected.';
  }

  @override
  String get aiTopologyMergeConfirm => 'Confirm and connect';

  @override
  String get aiTopologyConnectSelected => 'Connect selected agents';

  @override
  String get aiTopologyMakeRoot => 'Split into independent workflow';

  @override
  String get aiTopologyMakeWorkflowMain => 'Make main agent of this workflow';

  @override
  String get aiTopologyMakeChild => 'Change direct parent';

  @override
  String get aiTopologyChooseParent => 'Choose parent agent';

  @override
  String get aiTopologyChooseParentHelp =>
      'Choose a parent for task delegation and layout. This agent and its descendants become child agents. Conversations and communication links are preserved.';

  @override
  String get aiTopologyAutoLayout => 'Auto layout';

  @override
  String get aiTopologyReset => 'Reset view';

  @override
  String get aiTopologyZoomIn => 'Zoom in';

  @override
  String get aiTopologyZoomOut => 'Zoom out';

  @override
  String get aiTopologyNewPrimaryHelp =>
      'Create the starting point of an independent agent tree. Child agents can delegate further.';

  @override
  String get aiTopologyNewChildHelp =>
      'Keep an independent conversation and delegate further agents.';

  @override
  String get aiTopologyEmptyHelp =>
      'Create a main agent to start a workflow. Each connected workflow has exactly one main agent.';

  @override
  String get aiTopologyDelete => 'Delete agent';

  @override
  String get aiTopologyNoParent => 'Select a main agent or child agent first.';

  @override
  String get aiTopologyModel => 'Execution model';

  @override
  String get aiWorkspaceDeleteAction => 'Delete child agent';

  @override
  String aiTopologyMessageFrom(String title) {
    return 'From agent: $title';
  }

  @override
  String aiTopologyMessageFromMain(String title) {
    return 'From main agent: $title';
  }

  @override
  String aiTopologyMessageFromChild(String title) {
    return 'From child agent: $title';
  }

  @override
  String aiAgentIdValue(String id) {
    return 'Agent ID: $id';
  }

  @override
  String aiAgentModelServiceValue(String value) {
    return 'Model service: $value';
  }

  @override
  String get aiTopologyTaskId => 'Agent ID';

  @override
  String get aiTopologyCopyId => 'Copy agent ID';

  @override
  String get aiTopologyCanvasBackground => 'Canvas background';

  @override
  String get aiTopologyCanvasDots => 'Dots';

  @override
  String get aiTopologyCanvasGrid => 'Grid';

  @override
  String get aiTopologyCanvasPlain => 'Plain';

  @override
  String get aiTopologyStopSelected => 'Stop selected agents';

  @override
  String get aiTopologyDeleteSelected => 'Delete selected agents';

  @override
  String get aiTopologyDisconnect => 'Disconnect';

  @override
  String get aiTopologyDisconnectSelected => 'Disconnect selected links';

  @override
  String get aiTopologySelectAll => 'Select all agents';

  @override
  String get aiTopologyClearSelection => 'Clear selection';

  @override
  String get aiTopologyConnectHint =>
      'Drag between agent handles to connect them. Joining different agent trees requires confirmation.';

  @override
  String get aiTopologyInvalidConnection =>
      'Cannot connect: choose a valid agent without creating a cycle.';

  @override
  String aiTopologySelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get aiTopologySelectionHelp =>
      'Left-drag to select · Ctrl/Shift + click to multi-select · Right-drag to pan · Wheel to pan vertically · Shift + wheel to pan horizontally · Ctrl + wheel to zoom';

  @override
  String get aiTopologyShortcutsHelp =>
      'Left-click: select a card or link\nLeft-drag empty canvas: box-select cards and links\nCtrl/Shift + click or box-select: extend selection\nDouble-click a card: open conversation\nDrag a card: move it\nDrag a connection port: connect agents\nRight-drag / middle-drag / Space + left-drag: pan canvas\nWheel: pan vertically\nShift + wheel: pan horizontally\nCtrl + wheel: zoom\nCtrl + A: select all\nCtrl + C / Ctrl + V: copy / paste cards\nCtrl + Z: undo\nCtrl + Y or Ctrl + Shift + Z: redo\nDelete / Backspace: delete selected cards or disconnect selected links\nEsc: cancel selection or connection';

  @override
  String get aiTopologyDisconnectTitle => 'Disconnect agents?';

  @override
  String get aiTopologyDisconnectHelp =>
      'Disconnect the selected links. Communication links do not change roles. Detaching a delegation branch makes its root a main agent. Work instructions and conversation history are retained.';

  @override
  String get aiProcessingSpeed => 'Processing speed';

  @override
  String get aiProcessingSpeedStandard => 'Standard';

  @override
  String get aiProcessingSpeedFast => 'Fast';

  @override
  String get aiProcessingSpeedUltra => 'Ultrafast';

  @override
  String get aiProcessingSpeedCost => 'Fast and Ultrafast usually cost more';

  @override
  String get agentStorageScopeHint =>
      'Identify agents by their full ID; the full name and ID appear below.';

  @override
  String get agentStorageBackupTitle => 'Import and export';

  @override
  String get agentStorageManageHint =>
      'Search, add and edit memories in the selected scope.';

  @override
  String get agentStorageDevice => 'This device';

  @override
  String get agentStorageDeviceHint =>
      'Local conversations, memories and workflow data.';

  @override
  String get agentStorageManageAction => 'Manage';

  @override
  String get agentStorageCleanAction => 'Clean up now';

  @override
  String get agentStorageBackupHint =>
      'Import or export workflows, agents, conversations and long-term memories.';

  @override
  String get agentStorageMemoryCategory => 'Long-term memory';

  @override
  String get agentStorageOtherCategory => 'Indexes and database space';

  @override
  String get agentStorageTitle => 'Storage';

  @override
  String get agentStorageDescription =>
      'Manage conversations, memories and portable backups.';

  @override
  String get agentStorageMemoryScopeHint =>
      'Choose the agent whose long-term memories you want to manage. The memories and automatic memory settings below apply only to that agent.';

  @override
  String get agentStorageScope => 'Long-term memory owner';

  @override
  String get agentStorageContextScope => 'Conversation and context owner';

  @override
  String get agentStorageMemories => 'Long-term memories';

  @override
  String get agentStorageContextTitle => 'Chat history and context';

  @override
  String get agentStorageContextManageHint =>
      'Manage chat context, compacted summaries and the context cache.';

  @override
  String get agentStorageRecords => 'Conversations and workflow';

  @override
  String get agentStorageAdd => 'Add memory';

  @override
  String get agentStorageManageContext => 'Manage chat history and context';

  @override
  String get agentStorageManage => 'Manage memories';

  @override
  String get agentStorageImport => 'Import package';

  @override
  String get agentStorageExportMemory => 'Export long-term memory package';

  @override
  String get agentStorageImportMemory => 'Import long-term memory package';

  @override
  String get agentStorageExportAgent => 'Export agent package';

  @override
  String get agentStorageExportBranch => 'Export agent branch';

  @override
  String get agentStorageExportChat =>
      'Export chat history and context package';

  @override
  String get agentStorageExportWorkflow => 'Export agent workflow';

  @override
  String get agentStorageExportAll => 'Back up all agent data';

  @override
  String get agentStorageDeleteChat => 'Delete conversation and context';

  @override
  String get agentStorageDeleteChatHint =>
      'Delete this agent’s chat history and context summary? Its saved memories remain.';

  @override
  String get agentStorageDeleteMemoryHint =>
      'Delete this memory? This does not delete the original conversation.';

  @override
  String get agentStorageEmpty => 'No saved memories.';

  @override
  String get agentStorageMemoriesLoading => 'Loading long-term memories…';

  @override
  String get agentStorageContent => 'Memory content';

  @override
  String get agentStorageSource => 'Source';

  @override
  String get agentStorageImportPreview => 'Import preview';

  @override
  String get agentStorageImportHint =>
      'New agents receive new IDs. Memories are merged into the selected scope; exact duplicates are skipped. Imported permissions are reset and no operations resume.';

  @override
  String get agentStorageSuccess => 'Completed';

  @override
  String agentStorageCompactResult(int before, int after) {
    return 'Context compacted: $before → $after tokens (estimated).';
  }

  @override
  String get agentStorageCompactTooShort =>
      'There is not enough conversation history to compact yet.';

  @override
  String get agentStorageCompactUnavailable =>
      'Configure an available model service before compacting context.';

  @override
  String get aiContextCompactionBusy =>
      'Context compaction is already in progress.';

  @override
  String get agentStorageCompactCancelled => 'Context compaction cancelled.';

  @override
  String get agentStorageCompactUnchanged =>
      'No usable summary was generated. Context is unchanged.';

  @override
  String get agentStorageCompactFailed =>
      'Context compaction failed. Check the model service and try again.';

  @override
  String get aiCacheHit => 'Cache hit';

  @override
  String get aiContextUsed => 'Context used';

  @override
  String get aiCacheUsageDetails => 'Cache usage details';

  @override
  String get aiCacheNotReported => 'No data';

  @override
  String get aiCacheNotReportedHint =>
      'No cache usage has been reported for the current model in this chat.';

  @override
  String get aiContextUsageDetails => 'Context usage details';

  @override
  String get aiContextChatHistory => 'Conversation history';

  @override
  String get aiContextSummaryUsage => 'Compaction summary';

  @override
  String get aiCacheInputTokens => 'Input tokens';

  @override
  String get aiCacheCachedTokens => 'Cached input tokens';

  @override
  String get aiCacheUncachedTokens => 'Uncached input tokens';

  @override
  String get aiCacheOutputTokens => 'Output tokens';

  @override
  String aiMetricTokenCount(int count) {
    return '$count tokens';
  }

  @override
  String get aiContextBudgetUsage => 'Estimated usage';

  @override
  String get aiContextCompactionThreshold => 'Auto-compaction threshold';

  @override
  String get aiContextLastCompaction => 'Last compaction';

  @override
  String get aiManualCompaction => 'Manual context compaction';

  @override
  String get aiAutoCompaction => 'Automatic context compaction';

  @override
  String aiCompactionDuration(String seconds) {
    return 'Took $seconds s';
  }

  @override
  String aiCompactionTokenChange(int before, int after) {
    return 'Estimated tokens: $before → $after';
  }

  @override
  String get aiCompactionUnchanged => 'Unchanged';

  @override
  String get aiCompactionFailed => 'Context compaction failed';

  @override
  String get aiCompactionOutputLimitReached =>
      'The model reached its output token limit before finishing the summary. If thinking is enabled, try lowering it or choosing a different compaction model.';

  @override
  String get aiCompactionReasoningOnly =>
      'The model returned reasoning but no summary. The service did not report an output limit. Try lowering the compaction model’s thinking effort or choosing a different model.';

  @override
  String get aiCompactionEmptySummary => 'The model returned an empty summary.';

  @override
  String get aiCompactionUnexpectedToolCall =>
      'The model tried to call a tool instead of returning a summary.';

  @override
  String get aiCompactionFiltered =>
      'The model service filtered the summary output.';

  @override
  String get aiCompactionNoTokenSavings =>
      'The summary did not reduce the estimated token count, so the context was kept unchanged.';

  @override
  String get aiCompactionNoRecordedReason =>
      'No specific reason was recorded for this attempt.';

  @override
  String aiCompactionFinishReason(String reason) {
    return 'Model finish reason: $reason';
  }

  @override
  String aiCompactionProviderCode(String code) {
    return 'Service error code: $code';
  }

  @override
  String aiCompactionOutputLimit(int limit) {
    return 'Requested output limit: $limit tokens';
  }

  @override
  String aiCompactionOutputUsage(int used, int limit) {
    return 'Output reported by the model: $used tokens (requested limit: $limit)';
  }

  @override
  String get aiCompactionCancelledStatus => 'Cancelled';

  @override
  String get aiContextNoCompaction => 'Not compacted yet';

  @override
  String get aiContextCompacting => 'Compacting context…';

  @override
  String get aiCancelCompaction => 'Cancel compaction';

  @override
  String get aiCompactionCancelHint => 'Right-click to cancel compaction';

  @override
  String get agentStorageCleanFailed =>
      'Clean-up failed. Please try again later.';

  @override
  String get agentStorageCleanNothing => 'Nothing to clean up.';

  @override
  String agentStorageCleanResult(int count, String size) {
    return 'Removed $count leftover items and freed $size.';
  }

  @override
  String agentStorageCleanSpaceResult(String size) {
    return 'Storage organized. Freed $size.';
  }

  @override
  String get agentStoragePackageType => 'LilygoBox data package (7z)';

  @override
  String get agentStorageCompact => 'Compact context';

  @override
  String get agentStorageRetrieving => 'Retrieve memories';

  @override
  String get agentStorageSaving => 'Save memory';

  @override
  String get agentStorageDeleting => 'Delete memory';

  @override
  String get agentStorageMemoryEnabled =>
      'Automatically use long-term memories';

  @override
  String get agentStorageMemoryHint =>
      'Retrieve relevant memories before each turn to inform replies, and allow the agent to search, save or delete memories.';

  @override
  String get agentStorageUsage => 'Local storage usage';

  @override
  String get agentStorageUsageLoading => 'Loading local storage usage…';

  @override
  String get agentStorageSearch => 'Search memories';

  @override
  String get agentStorageNoAgent => 'Select an agent first.';

  @override
  String get agentStorageBusy =>
      'Stop the selected agents before importing or deleting their data.';

  @override
  String get agentMemoryDuplicate => 'Identical — skip';

  @override
  String get agentMemoryConflict => 'Different versions of the same memory';

  @override
  String get agentMemoryNew => 'New memory';

  @override
  String get agentMemorySkip => 'Skip';

  @override
  String get agentMemoryBoth => 'Keep both';

  @override
  String get agentMemoryReplace => 'Replace existing';

  @override
  String get agentMemoryIncoming => 'Incoming content (editable)';

  @override
  String get agentMemoryExisting => 'Existing content';

  @override
  String get agentMemoryReview => 'Review memories';

  @override
  String get agentStorageMore => 'Load more';

  @override
  String get agentStorageEditMemory => 'Edit';

  @override
  String get agentStorageCopyMemoryId => 'Copy memory ID';

  @override
  String get cardSelect => 'Select';

  @override
  String get cardDeselect => 'Deselect';

  @override
  String get cardSelectAll => 'Select all';

  @override
  String get agentStorageMemoryIdLabel => 'Memory ID:';

  @override
  String agentStorageMemoryId(String id) {
    return 'Memory ID: $id';
  }

  @override
  String get agentStorageClean => 'Free up storage space';

  @override
  String get agentStorageCleanHint =>
      'Remove leftover files now to free up storage space. Chats, memories and recycle bin contents are kept.';

  @override
  String get agentStorageContextBudget => 'Context budget';

  @override
  String get agentStorageContextHint =>
      'Budget × percentage = automatic compaction threshold. Press Enter or leave the field to save. Refer to the provider’s model capacity and leave room for the full request.';

  @override
  String get agentStorageArchived => 'Archived scope';

  @override
  String get agentStorageFailure =>
      'Operation failed. Check the file or storage permissions.';

  @override
  String get agentStorageSensitiveHint =>
      'Packages contain the selected conversations, context or long-term memory text, but no API keys. Keep them private.';

  @override
  String agentStorageTokens(int count) {
    return '$count tokens (estimated)';
  }

  @override
  String get agentStorageExportTab => 'Export data';

  @override
  String get agentStorageImportAgents => 'Import data';

  @override
  String get agentStorageImportTab => 'Import data';

  @override
  String get agentStoragePackageKind => 'Export contents';

  @override
  String get agentStoragePackageKindHint =>
      'Choose the contents to export as one .7z file.';

  @override
  String get agentStorageMemoryPackage => 'Long-term memory package';

  @override
  String get agentStorageChatPackage => 'Conversation and context package';

  @override
  String get agentStorageAgentPackage => 'Agent package';

  @override
  String get agentStorageWorkflowPackage => 'Workflow package';

  @override
  String get agentStorageBackupPackage => 'Complete data package';

  @override
  String get agentStorageMemoryPackageHint =>
      'Export the selected agent’s long-term memories. Import them into another agent.';

  @override
  String get agentStorageChatPackageHint =>
      'Export the selected agent’s chat history, context and compaction summary, activity records, attachments, and model, compaction, and approval settings. Does not include long-term memories.';

  @override
  String get agentStorageAgentPackageHint =>
      'Export one agent’s name, model selections, approval settings, chat, context, long-term memories, and attachments. Optionally include its children.';

  @override
  String get agentStorageWorkflowPackageHint =>
      'Export all agents with their model selections, approval settings, chats, context, long-term memories, attachments, connections, and canvas layout.';

  @override
  String get agentStorageBackupPackageHint =>
      'Includes the workflow and the conversations, attachments and memories in the recycle bin.';

  @override
  String get agentStorageIncludeChildren => 'Include child agents';

  @override
  String get agentStorageChooseAgent => 'Choose an agent to export';

  @override
  String get agentStorageNoExportAgents => 'No agents available to export';

  @override
  String get agentStorageNoManagedAgents => 'No agents available to manage';

  @override
  String get agentStorageNoExportWorkflow =>
      'No agent workflow available to export';

  @override
  String get agentStorageMemoryDestination =>
      'Where to import long-term memories';

  @override
  String get agentStorageMemoryDestinationHint =>
      'Choose an existing agent, or create a main agent for these long-term memories.';

  @override
  String get agentStorageExportTarget => 'Export target';

  @override
  String get agentStorageExportTargetHint =>
      'Choose an agent or the agent workflow, then select what to export.';

  @override
  String get agentStorageChooseExportTarget => 'Choose what to export';

  @override
  String get agentStorageAgentTarget => 'Agent';

  @override
  String get agentStorageIncludeArchived => 'Include agents in the recycle bin';

  @override
  String get agentRecycleSearch => 'Search agents';

  @override
  String get agentRecycleBin => 'Recycle bin';

  @override
  String get agentRecycleHint =>
      'Restore or permanently delete removed agents.';

  @override
  String get agentRecycleRetention => 'Automatically delete';

  @override
  String get agentRecycleDays7 => 'After 7 days';

  @override
  String get agentRecycleDays30 => 'After 30 days';

  @override
  String get agentRecycleDays90 => 'After 90 days';

  @override
  String get agentRecycleNever => 'Never';

  @override
  String get agentRecycleEmpty => 'The recycle bin is empty';

  @override
  String get agentRecycleRestore => 'Restore';

  @override
  String get agentRecycleRestoring => 'Restoring agents…';

  @override
  String agentRecycleRestoreConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restore the $count selected agents?',
      one: 'Restore this agent?',
    );
    return '$_temp0';
  }

  @override
  String get agentRecycleRestoreFailed =>
      'Restore failed. You can try again from the recycle bin.';

  @override
  String get agentRecycleDelete => 'Delete permanently';

  @override
  String get agentRecycleRestoreAll => 'Restore all';

  @override
  String agentRecycleRestoreAllConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count agents',
      one: '1 agent',
    );
    return 'Restore all $_temp0 in the recycle bin?';
  }

  @override
  String get agentRecycleEmptyAction => 'Empty all';

  @override
  String get agentRecycleDeleteHint =>
      'Conversations, attachments and memories will be permanently deleted. This cannot be undone.';

  @override
  String get agentRecycleRestoreHint =>
      'The original ID, conversation and memory are preserved. If the parent no longer exists, the agent is restored as a main agent. Permissions must be granted again. Expired items are removed at the next startup if the app is closed.';

  @override
  String get agentRecycleDeletedAt => 'Deleted';

  @override
  String get agentRecycleExpiresAt => 'Expires';

  @override
  String get agentRecycleRetentionConfirm =>
      'Changing retention permanently deletes any agents that have already expired. Continue?';

  @override
  String get agentTopologyHintSelectAll =>
      'Ctrl + A · Select all agents and connections';

  @override
  String get agentTopologyHintCopy => 'Ctrl + C · Copy agents or workflow';

  @override
  String get agentTopologyHintPaste => 'Ctrl + V · Paste agents or workflow';

  @override
  String get agentTopologyHintUndo => 'Ctrl + Z · Undo';

  @override
  String get agentTopologyHintRedo => 'Ctrl + Y · Redo';

  @override
  String get agentTopologyHintDelete => 'Delete · Delete selected content';

  @override
  String get agentTopologyHintEscape => 'Esc · Clear selection or connection';

  @override
  String get agentTopologyHintBoxSelect =>
      'Left-drag · Select agents and connections';

  @override
  String get agentTopologyHintPan => 'Wheel / Shift + wheel · Pan canvas';

  @override
  String get agentTopologyHintZoom => 'Ctrl + wheel · Zoom canvas';

  @override
  String get agentStorageWorkflowCategory => 'Workflow';

  @override
  String get agentStorageContextUsage => 'Current context';

  @override
  String get agentStorageContextUsageHint =>
      'Local estimate of chat history, excluding the full request’s system instructions, tool definitions and retrieved memories.';

  @override
  String get agentStorageContextInvalid =>
      'Enter a whole number greater than 0.';

  @override
  String get agentStorageCompactHint =>
      'Summarize older conversation for future requests. Original conversations and attachments are retained.';

  @override
  String get agentStorageCompactionModel => 'Context compaction model';

  @override
  String get agentStorageCompactionModelHint =>
      'Applies to automatic and manual compaction. By default, both use the current chat model and its reasoning effort.';

  @override
  String get agentStorageCompactNow => 'Compact now';

  @override
  String get agentStorageChatDataTitle => 'Conversation and context';

  @override
  String get agentStorageContextPercent => 'Compaction trigger';

  @override
  String agentStorageContextTriggerTokens(int count) {
    return 'Automatic compaction threshold: $count tokens (estimated)';
  }

  @override
  String get agentStorageContextPercentInvalid =>
      'Enter a whole percentage from 1 to 100.';

  @override
  String get agentStorageContextPercentWarning =>
      'A high percentage may leave too little room for new messages, tools and responses. Compact before the context window is full.';

  @override
  String get agentTopologyZoomPercentage => 'Zoom percentage';

  @override
  String get agentTopologyControlHints =>
      'Ctrl + A Select all · Ctrl + C Copy · Ctrl + V Paste · Ctrl + Z Undo · Ctrl + Y Redo · Ctrl + Wheel Zoom';

  @override
  String get agentTopologyShiftHints =>
      'Shift + Wheel Pan horizontally · Shift + Click / Drag Add to selection · Ctrl + Shift + Z Redo';

  @override
  String get agentTopologySpaceHints => 'Space + Left drag Pan canvas';

  @override
  String get agentStorageDatabaseLocation =>
      'Agent data directory (conversations, context and long-term memories)';

  @override
  String get agentStorageChoosePackage => 'Choose data package';

  @override
  String get agentStorageImportAutoHint =>
      'Choose a .7z package to detect its type, then review its contents before importing. Packages contain no API keys; keep them private.';

  @override
  String get agentStorageImportCreatesAgents =>
      'New agents will receive new IDs. Existing agents will not be overwritten.';

  @override
  String get agentStorageImportMemoryCreatesAgent =>
      'A new agent will be created with these long-term memories. Existing agents stay unchanged. The new agent will not run automatically; select a model to use it.';

  @override
  String get agentStorageImportedMemoryAgent => 'Imported agent';

  @override
  String get agentStorageImportMemoryMergeHint =>
      'Long-term memories will be merged into the selected agent. Exact duplicates are skipped; conflicts can be reviewed before importing.';

  @override
  String get agentStorageImportSuccess => 'Data imported.';

  @override
  String get agentStorageExportSuccess => 'Data exported.';

  @override
  String get agentStorageTransferCancelled => 'Operation cancelled.';

  @override
  String get agentStorageTransferTitle => 'Processing data package';

  @override
  String get agentStorageTransferPreparing => 'Preparing data';

  @override
  String get agentStorageTransferReading => 'Reading package';

  @override
  String get agentStorageTransferCompressing => 'Compressing data';

  @override
  String get agentStorageTransferDecompressing => 'Decompressing data';

  @override
  String get agentStorageTransferVerifying => 'Verifying package';

  @override
  String get agentStorageTransferAnalyzing => 'Analyzing data';

  @override
  String get agentStorageTransferWriting => 'Saving file';

  @override
  String get agentStorageTransferCommitting => 'Completing import';

  @override
  String get agentStorageTransferCancelling => 'Cancelling';

  @override
  String agentStorageTransferElapsed(String duration) {
    return 'Elapsed $duration';
  }

  @override
  String get agentStorageImportFile => 'Data package';

  @override
  String get agentStorageChangePackage => 'Choose another package';

  @override
  String get agentStorageAutoMemoryTitle =>
      'Automatically organize long-term memories';

  @override
  String get agentStorageAutoMemoryHint =>
      'After each completed turn, select useful lasting information, compare it with existing memories and save new items. Makes an additional request to the current model.';

  @override
  String get agentStorageAutoMemoryAction => 'Organize long-term memories';

  @override
  String agentStorageAutoMemoryResult(int saved, int duplicates) {
    return 'Saved $saved long-term memories; skipped $duplicates duplicates.';
  }

  @override
  String get agentStorageImportInvalidKind =>
      'This package is not supported by this entry. Choose the appropriate long-term memory, agent or workflow package.';

  @override
  String get agentStorageTransferFailedTitle => 'Import or export failed';

  @override
  String get agentStorageInvalidPackage =>
      'The package is invalid, damaged or unsupported. Select a valid data package.';

  @override
  String agentStorageDeleteSelected(int count) {
    return 'Delete selected ($count)';
  }

  @override
  String agentStorageRestoreSelected(int count) {
    return 'Restore selected ($count)';
  }

  @override
  String agentStorageDeleteSelectedHint(int count) {
    return 'Permanently delete the $count selected long-term memories? This cannot be undone.';
  }

  @override
  String agentRecycleDeleteSelectedHint(int count) {
    return 'Permanently delete the $count selected agents and their chat history, context, and long-term memories? This cannot be undone.';
  }

  @override
  String agentRecycleDeleteSelected(int count) {
    return 'Permanently delete selected ($count)';
  }

  @override
  String agentRecycleRemainingDays(int count) {
    return 'Automatically deletes in $count days';
  }

  @override
  String agentRecycleRemainingHours(int count) {
    return 'Automatically deletes in $count hours';
  }

  @override
  String agentRecycleRemainingMinutes(int count) {
    return 'Automatically deletes in $count minutes';
  }

  @override
  String get agentRecyclePendingDeletion => 'Pending automatic deletion';

  @override
  String get agentMemoryAdd => 'Import';

  @override
  String get agentMemoryEmptyContent => 'Memory content cannot be empty.';

  @override
  String get agentStorageNewAgent => 'New agent';

  @override
  String get aiAgentTopologyQuery => 'Read agent topology';

  @override
  String get aiLeadershipTransfer => 'Transfer leadership';

  @override
  String get aiLeadershipUndo => 'Undo leadership transfer';

  @override
  String get aiTimer => 'Timer';

  @override
  String get aiTimerStart => 'Start timer';

  @override
  String get aiTimerQuery => 'Check timer status';

  @override
  String get aiTimerWait => 'Wait for timer';

  @override
  String get aiTimerCancel => 'Cancel timer';
}
