/// English copy is centralized so additional locales can be added without editing screens.
abstract final class S {
  static const appName = 'NetProbe';
  static const test = 'Test';
  static const servers = 'Servers';
  static const history = 'History';
  static const settings = 'Settings';
  static const download = 'Download';
  static const upload = 'Upload';
  static const normal = 'Speed test';
  static const constantDownload = 'Constant download';
  static const constantUpload = 'Constant upload';
  static const start = 'Start test';
  static const stop = 'Stop transfer';
  static const stopPending = 'Stopping…';
  static const starting = 'Starting…';
  static const ready = 'Ready to test';
  static const latency = 'HTTP latency';
  static const transferred = 'Data transferred';
  static const elapsed = 'Elapsed';
  static const testSetup = 'Test setup';
  static const parallelThreads = 'Parallel threads';
  static const threadsHelp = 'More threads can saturate fast connections.';
  static const limits = 'Transfer limits';
  static const phaseDuration = 'Seconds per phase';
  static const duration = 'Duration in seconds';
  static const dataLimit = 'Data limit in GB';
  static const limitsHelp =
      'Stops at the first limit reached. Leave both blank to run until you tap Stop.';
  static const untilStopped = 'Until stopped';
  static const normalHelp =
      'Runs download, then upload. Each phase uses the selected number of threads.';
  static const sustainedHelp =
      'Runs continuously until a limit is reached or you tap Stop.';
  static const details = 'Details';
  static const mobileNetwork = 'Mobile';
  static const startupPermissionDenied =
      'Some permissions are off. Enable them in Settings for network details and background notifications.';
  static const dataHelp =
      'Decimal GB. Counts transfer payload; carrier usage also includes protocol overhead.';
  static const currentNetwork = 'Current network';
  static const networkDetails = 'Network details';
  static const networkDetailsHelp =
      'Android needs phone permission for the radio type and precise location permission for the Wi-Fi name. Location services must also be on.';
  static const permissions = 'Allow network details';
  static const device = 'Device';
  static const publicIp = 'Public IP';
  static const localIp = 'Local IP';
  static const isp = 'Internet provider';
  static const location = 'IP location';
  static const operator = 'Registered operator';
  static const simOperator = 'SIM provider';
  static const roaming = 'Roaming';
  static const networkType = 'Radio type';
  static const wifiName = 'Wi-Fi name';
  static const refresh = 'Refresh';
  static const retry = 'Try again';
  static const selectedServer = 'Selected server';
  static const chooseServer = 'Choose a server';
  static const noServer = 'No server selected';
  static const findingServers = 'Finding nearby servers…';
  static const searchServers = 'Search city, country or provider';
  static const nearby = 'Nearby';
  static const favorites = 'Favorites';
  static const custom = 'Custom';
  static const addServer = 'Add custom server';
  static const noServers = 'No servers found';
  static const noServersHelp = 'Try another search or add your own endpoint.';
  static const noFavorites = 'Your favorites live here';
  static const noFavoritesHelp =
      'Tap a server’s star to save it on this device.';
  static const noCustom = 'Bring your own server';
  static const noCustomHelp = 'Add a download URL, an upload URL, or both.';
  static const serverName = 'Server name';
  static const downloadUrl = 'Download URL';
  static const uploadUrl = 'Upload URL';
  static const customHelp =
      'Download must return a file or binary stream. Upload must accept a streamed HTTP POST with application/octet-stream.';
  static const save = 'Save';
  static const cancel = 'Cancel';
  static const delete = 'Delete';
  static const discardTitle = 'Discard changes?';
  static const discardBody = 'Your changes have not been saved.';
  static const keepEditing = 'Keep editing';
  static const discard = 'Discard';
  static const favorite = 'Save favorite';
  static const unfavorite = 'Remove favorite';
  static const deleteServer = 'Delete custom server';
  static const deleteServerBody =
      'This removes the saved endpoint from this device.';
  static const appearance = 'Appearance';
  static const system = 'System';
  static const light = 'Light';
  static const dark = 'Dark';
  static const speedUnits = 'Speed units';
  static const unitsHelp = '1 MB/s = 8 Mbps. Mb/s and Mbps are the same unit.';
  static const background = 'Background transfers';
  static const backgroundHelp =
      'An Android foreground service keeps transfers active with a live notification and Stop action. Android and device power controls can still stop the service. Data-sync services have a six-hour background allowance on Android 15 and later.';
  static const measurements = 'About measurements';
  static const measurementsHelp =
      'Uses HTTP transfers against discovered Speedtest servers. Results are payload throughput, not Ookla’s licensed measurement algorithm. Upload counts bytes written to the connection. Some servers may reject these endpoints; select another or use a custom URL.';
  static const noHistory = 'Your next test starts here';
  static const noHistoryHelp =
      'Completed and stopped transfers are saved on this device.';
  static const clearHistory = 'Clear history';
  static const clearHistoryBody =
      'Delete all saved test results from this device?';
  static const offline = 'No network connection';
  static const offlineHelp = 'Connect to Wi-Fi or mobile data to run a test.';
  static const unavailable = 'Unavailable';
  static const on = 'On';
  static const off = 'Off';
  static const locationSettings = 'Turn on location services';
  static const appSettings = 'Open app permissions';
  static const limitedConnection =
      'Connected network has no validated internet access.';
  static const notificationDenied =
      'Notifications are off. Enable them in Settings for live speed and a Stop action while the app is in the background.';
  static const incompatible = 'This server does not support the selected mode.';
  static const saved = 'Server saved';
  static const secondsError = 'Enter a whole number from 1 to 86400.';
  static const budgetError = 'Enter a positive data limit, up to 9000000 GB.';
  static const nameRequired = 'Give this server a name.';
  static const urlError =
      'Enter an HTTP or HTTPS URL without credentials or a fragment.';
  static const endpointRequired = 'Add at least one transfer URL.';
  static const modeLabels = ['Speed test', 'Download', 'Upload'];
}
