package;

/**
 * Test app to verify watchdog crash detection
 * This will start the watchdog, then freeze (stop pinging)
 */
class TestFreeze
{
	static function main()
	{
		trace("=== Watchdog Freeze Test ===");

		#if cpp
		// Set up log directory for watchdog
		var exePath = Sys.programPath();
		var dir = haxe.io.Path.directory(exePath);
		Sys.putEnv("KC_LOG_DIR", dir);
		trace("Log directory: " + dir);

		trace("Starting watchdog with 10 second timeout...");

		// Start watchdog
		var timeoutMs = 10000; // 10 seconds
		var restartCmd = '"' + exePath + '"'; // Restart same exe
		utils.WatchDog.start(timeoutMs, restartCmd);

		// Set notification URL with REAL values from config
		var notifyURL = "https://kontentum.link/rest/clientNotify/s3sxqb/344/WatchdogCrashDetected";
		utils.WatchDog.setNotifyURL(notifyURL);

		trace("Watchdog started. Notification URL: " + notifyURL);
		trace("Restart command: " + restartCmd);
		trace("");
		trace("Pinging watchdog for 15 seconds...");

		// Ping for 15 seconds (this should keep it alive)
		var startTime = Sys.time();
		while (Sys.time() - startTime < 15)
		{
			utils.WatchDog.ping();
			Sys.sleep(1);
			trace("  Ping... (" + Std.int(Sys.time() - startTime) + "s)");
		}

		trace("");
		trace("STOPPING PINGS - Watchdog should trigger in 10 seconds!");
		trace("Check watchdog.log in: " + dir);
		trace("");

		// Now do an infinite loop WITHOUT pinging - this will freeze the app
		// The watchdog should detect timeout after 10 seconds and kill/restart
		var counter = 0;
		while (true)
		{
			counter++;
			if (counter % 10000000 == 0)
			{
				trace("Still frozen... (" + Std.int(counter / 10000000) + "0M iterations)");
			}
		}
		#else
		trace("This test only works on C++ target");
		#end
	}
}
