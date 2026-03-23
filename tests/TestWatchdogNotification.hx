package;

/**
 * Simple test to verify watchdog notification URL generation logic
 * This simulates the URL generation without requiring full compilation
 */
class TestWatchdogNotification
{
	static function main()
	{
		trace("=== Watchdog Notification URL Test ===\n");

		// Test Case 1: With app_id from server
		var appID = 750;
		var clientID = 344;
		var exhibitToken = "ceu4x6";
		var ip = "https://kontentum.link";

		var idToUse = appID > 0 ? appID : (clientID > 0 ? clientID : 0);
		var notifyURL = ip + "/rest/clientNotify/" + exhibitToken + "/" + idToUse + "/WatchdogCrashDetected";

		trace("Test 1 - With app_id from server:");
		trace("  app_id: " + appID);
		trace("  clientID: " + clientID);
		trace("  URL: " + notifyURL);
		trace("  Expected: https://kontentum.link/rest/clientNotify/ceu4x6/750/WatchdogCrashDetected");
		trace("  PASS: " + (notifyURL == "https://kontentum.link/rest/clientNotify/ceu4x6/750/WatchdogCrashDetected"));
		trace("");

		// Test Case 2: Without app_id, using clientID fallback
		appID = 0;
		clientID = 344;

		idToUse = appID > 0 ? appID : (clientID > 0 ? clientID : 0);
		notifyURL = ip + "/rest/clientNotify/" + exhibitToken + "/" + idToUse + "/WatchdogCrashDetected";

		trace("Test 2 - Without app_id, using clientID fallback:");
		trace("  app_id: " + appID);
		trace("  clientID: " + clientID);
		trace("  URL: " + notifyURL);
		trace("  Expected: https://kontentum.link/rest/clientNotify/ceu4x6/344/WatchdogCrashDetected");
		trace("  PASS: " + (notifyURL == "https://kontentum.link/rest/clientNotify/ceu4x6/344/WatchdogCrashDetected"));
		trace("");

		// Test Case 3: Neither app_id nor clientID available
		appID = 0;
		clientID = 0;

		idToUse = appID > 0 ? appID : (clientID > 0 ? clientID : 0);
		notifyURL = ip + "/rest/clientNotify/" + exhibitToken + "/" + idToUse + "/WatchdogCrashDetected";

		trace("Test 3 - Neither app_id nor clientID available:");
		trace("  app_id: " + appID);
		trace("  clientID: " + clientID);
		trace("  URL: " + notifyURL);
		trace("  Expected: https://kontentum.link/rest/clientNotify/ceu4x6/0/WatchdogCrashDetected");
		trace("  PASS: " + (notifyURL == "https://kontentum.link/rest/clientNotify/ceu4x6/0/WatchdogCrashDetected"));
		trace("");

		// Test Case 4: Current config scenario (s3sxqb token, clientID 344)
		appID = 0;
		clientID = 344;
		exhibitToken = "s3sxqb";

		idToUse = appID > 0 ? appID : (clientID > 0 ? clientID : 0);
		notifyURL = ip + "/rest/clientNotify/" + exhibitToken + "/" + idToUse + "/WatchdogCrashDetected";

		trace("Test 4 - Current config (before app_id received):");
		trace("  exhibitToken: " + exhibitToken);
		trace("  app_id: " + appID);
		trace("  clientID: " + clientID);
		trace("  URL: " + notifyURL);
		trace("  Expected: https://kontentum.link/rest/clientNotify/s3sxqb/344/WatchdogCrashDetected");
		trace("  PASS: " + (notifyURL == "https://kontentum.link/rest/clientNotify/s3sxqb/344/WatchdogCrashDetected"));
		trace("");

		trace("=== All Tests Complete ===");
	}
}
