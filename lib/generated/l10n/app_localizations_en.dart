/*
 * @Description: 自动生成的本地化文件
 * @Author: LILYGO_L
 * @Date: 2025-10-27 11:20:43
 * @LastEditTime: 2026-10-01 15:52:48
 * @License: GPL 3.0
 * @Generated: flutter gen-l10n
 * @Note: 请勿手动编辑，翻译内容请在 lib/l10n 目录下的 .arb 文件中修改。
 */

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get sidebarHome => 'Home';

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
}
